import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/admin_api_settings.dart';
import 'package:simple_kiosk/service/admin_api_controller.dart';
import 'package:simple_kiosk/service/admin_api_settings_store.dart';
import 'package:simple_kiosk/service/admin_pin_store.dart';
import 'package:simple_kiosk/service/exdata_file_service.dart';
import 'package:simple_kiosk/service/mdns_service_controller.dart';
import 'package:simple_kiosk/service/ui_theme_service.dart';
import 'package:simple_kiosk/service/web_admin_ssh_tunnel_controller.dart';

class _FakeMdnsPublisher implements MdnsPublisher {
  @override
  bool running = false;
  String? hostname;
  int? port;

  @override
  Future<void> start({required String hostname, required int port}) async {
    this.hostname = hostname;
    this.port = port;
    running = true;
  }

  @override
  Future<void> stop() async => running = false;
}

void main() {
  test('mDNS 설정은 ysignage.local을 기본값으로 사용한다', () {
    final settings = AdminApiSettings.fromJson(const {});

    expect(settings.mdnsEnabled, isTrue);
    expect(settings.mdnsHostname, 'ysignage.local');
    expect(settings.webAdminSshForwardingEnabled, isTrue);
    expect(settings.webAdminSshForwardingId, isNull);
    expect(settings.toJson()['schemaVersion'], 3);
    expect(
      () => AdminApiSettings.fromJson(
        const {'mdnsHostname': 'not-a-local-name'},
      ),
      throwsFormatException,
    );
  });

  test('원격 WEB 관리자 ID를 저장하고 다음 접속 후보의 첫 번째로 사용한다', () {
    final settings = AdminApiSettings.fromJson(const {
      'webAdminSshForwardingEnabled': true,
      'webAdminSshForwardingId': 'ysignage7',
    });
    expect(settings.webAdminSshForwardingId, 'ysignage7');
    expect(settings.toJson()['webAdminSshForwardingId'], 'ysignage7');
    expect(
      WebAdminSshTunnelController.candidateIds('ysignage7').take(4),
      ['ysignage7', 'ysignage1', 'ysignage2', 'ysignage3'],
    );
    expect(
      () => AdminApiSettings.fromJson(
        const {'webAdminSshForwardingId': 'invalid'},
      ),
      throwsFormatException,
    );
  });

  test('관리 API는 동일 PIN으로 인증하고 상태·설정·작업을 제공한다', () async {
    final directory = await Directory.systemTemp.createTemp('admin-api-test-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final settingsFile =
        File('${directory.path}${Platform.pathSeparator}admin-api.json');
    final pinFile =
        File('${directory.path}${Platform.pathSeparator}admin-pin.json');
    final settingsStore = AdminApiSettingsStore(file: settingsFile);
    await settingsStore.save(
      AdminApiSettings(
        port: port,
        webAdminSshForwardingEnabled: false,
      ),
    );
    Map<String, dynamic> config = {'schemaVersion': 1};
    Map<String, dynamic> effectiveConfig = {
      'schemaVersion': 2,
      'layout': {'barHeight': 96},
      'idle': {
        'slideshow': {
          'images': ['exdata/photos/hello.txt'],
        },
      },
    };
    String? action;
    final mdnsPublisher = _FakeMdnsPublisher();
    var networkSyncCalls = 0;
    var synchronizedBeforeInitialBind = false;
    final controller = AdminApiController(
      pinStore: AdminPinStore(file: pinFile, iterations: 1),
      settingsStore: settingsStore,
      exdataFileService: ExdataFileService(
        rootPath: '${directory.path}${Platform.pathSeparator}exdata',
      ),
      uiThemeService: UiThemeService(
        userThemeDirectory: '${directory.path}${Platform.pathSeparator}themes',
        preloadedThemeLoader: () async => [
          {
            'id': 'built-in',
            'name': '기본 테마',
            'values': {'barColor': '#111111'},
          },
        ],
      ),
      mdnsPublisher: mdnsPublisher,
      pageLoader: () async => '<html>admin</html>',
      statusProvider: () async => {
        'running': true,
        'system': {
          'operatingSystem': Platform.operatingSystem,
          'buildMode': 'debug',
        },
      },
      actionHandler: (value) async {
        action = value;
        return {'message': value};
      },
      configReader: () async => config,
      effectiveConfigReader: () async => effectiveConfig,
      defaultConfigReader: () async => {
        'schemaVersion': 2,
        'layout': {'barHeight': 88},
      },
      configWriter: (value) async => config = value,
      beforeNetworkStart: (settings) async {
        networkSyncCalls++;
        if (networkSyncCalls != 1) return;
        final beforeBind = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          settings.port,
        );
        synchronizedBeforeInitialBind = true;
        await beforeBind.close();
      },
    );
    final client = http.Client();
    try {
      await controller.initialize();
      expect(synchronizedBeforeInitialBind, isTrue);
      expect(controller.running, isTrue);
      expect(mdnsPublisher.running, isTrue);
      expect(mdnsPublisher.hostname, 'ysignage.local');
      expect(mdnsPublisher.port, port);

      final unauthorized = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/status'),
      );
      expect(unauthorized.statusCode, 401);

      final login = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/login'),
        headers: {'content-type': 'application/json'},
        body: json.encode({'pin': AdminPinStore.defaultPin}),
      );
      expect(login.statusCode, 200);
      final loginBody = json.decode(login.body) as Map<String, dynamic>;
      expect(loginBody['expiresInSeconds'], 30 * 60);
      final token = loginBody['token'];
      final headers = {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };

      final status = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/status'),
        headers: headers,
      );
      expect(status.statusCode, 200);
      final statusBody = json.decode(status.body) as Map<String, dynamic>;
      expect(statusBody['running'], isTrue);
      expect(statusBody['system'], isA<Map<String, dynamic>>());
      expect(statusBody['system']['operatingSystem'], isNotEmpty);
      expect(statusBody['system']['buildMode'], anyOf('debug', 'release'));
      expect(
        statusBody['adminApi']['mdnsHostname'],
        'ysignage.local',
      );
      expect(
        json.decode(status.body)['adminApi']['webAdminSshForwarding']
            ['enabled'],
        isFalse,
      );
      expect(
        json.decode(status.body)['adminApi']['webAdminSshForwarding']
            ['forwardingVerified'],
        isFalse,
      );

      final serverSettings = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/server-settings'),
        headers: headers,
      );
      expect(serverSettings.statusCode, 200);
      expect(
        json.decode(serverSettings.body)['webAdminSshForwardingStatus'],
        'disabled',
      );
      expect(
        json.decode(serverSettings.body)['webAdminSshForwardingState'],
        contains('실제 reverse forwarding'),
      );

      final effectiveConfigResponse = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/config/effective'),
        headers: headers,
      );
      expect(effectiveConfigResponse.statusCode, 200);
      expect(
          json.decode(effectiveConfigResponse.body)['layout']['barHeight'], 96);

      final defaultConfig = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/config/defaults'),
        headers: headers,
      );
      expect(defaultConfig.statusCode, 200);
      expect(json.decode(defaultConfig.body)['layout']['barHeight'], 88);

      final initialThemes = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/themes'),
        headers: headers,
      );
      expect(initialThemes.statusCode, 200);
      expect(json.decode(initialThemes.body)['themes'][0]['name'], '기본 테마');

      final saveTheme = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/themes'),
        headers: headers,
        body: json.encode({
          'name': '사용자 테마',
          'values': {'barColor': '#222222', 'navPosition': 'left'},
        }),
      );
      expect(saveTheme.statusCode, 201, reason: saveTheme.body);
      final savedTheme = json.decode(saveTheme.body)['theme'];
      expect(savedTheme['values']['barColor'], '#222222');
      expect(savedTheme['values'].containsKey('navPosition'), isFalse);

      final reservedTheme = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/themes'),
        headers: headers,
        body: json.encode({
          'name': '기본 테마',
          'values': {'barColor': '#ffffff'},
        }),
      );
      expect(reservedTheme.statusCode, 409);

      final deleteTheme = await client.delete(
        Uri.parse(
          'http://127.0.0.1:$port/api/themes?id=${Uri.encodeQueryComponent(savedTheme['id'])}',
        ),
        headers: headers,
      );
      expect(deleteTheme.statusCode, 200);

      final createFolder = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/files/directory'),
        headers: headers,
        body: json.encode({'path': 'photos'}),
      );
      expect(createFolder.statusCode, 201);

      final upload = await client.put(
        Uri.parse(
          'http://127.0.0.1:$port/api/files/upload?path=photos%2Fhello.txt',
        ),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/octet-stream',
        },
        body: 'hello',
      );
      expect(upload.statusCode, 201);

      final jsonUpload = await client.put(
        Uri.parse(
          'http://127.0.0.1:$port/api/files/upload?path=photos%2Fmenu.defaults.json',
        ),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/octet-stream',
        },
        body: utf8.encode('{"schemaVersion":2}'),
      );
      expect(jsonUpload.statusCode, 201, reason: jsonUpload.body);

      final largeContents = List<int>.generate(
        1024 * 1024 + 12345,
        (index) => index % 251,
      );
      const chunkBytes = 512 * 1024;
      const uploadId = 'integration_upload_1234';
      for (var offset = 0;
          offset < largeContents.length;
          offset += chunkBytes) {
        final end = (offset + chunkBytes).clamp(0, largeContents.length);
        final complete = end == largeContents.length;
        final chunkUpload = await client.put(
          Uri.parse(
            'http://127.0.0.1:$port/api/files/upload'
            '?path=photos%2Flarge.json&uploadId=$uploadId'
            '&offset=$offset&complete=$complete',
          ),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/octet-stream',
          },
          body: largeContents.sublist(offset, end),
        );
        expect(
          chunkUpload.statusCode,
          complete ? 201 : 200,
          reason: chunkUpload.body,
        );
      }

      final files = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/files/list?path=photos'),
        headers: headers,
      );
      expect(files.statusCode, 200);
      expect(json.decode(files.body)['root'], 'exdata');
      expect(
        json.decode(files.body)['entries'].map((entry) => entry['name']),
        containsAll(['hello.txt', 'menu.defaults.json']),
      );

      final download = await client.get(
        Uri.parse(
          'http://127.0.0.1:$port/api/files/download?path=photos%2Fhello.txt',
        ),
        headers: headers,
      );
      expect(download.statusCode, 200);
      expect(download.body, 'hello');

      final largeDownload = await client.get(
        Uri.parse(
          'http://127.0.0.1:$port/api/files/download?path=photos%2Flarge.json',
        ),
        headers: headers,
      );
      expect(largeDownload.statusCode, 200);
      expect(largeDownload.bodyBytes, largeContents);

      final blockedRename = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/files/move'),
        headers: headers,
        body: json.encode({
          'source': 'photos/hello.txt',
          'destination': 'photos/renamed.txt',
        }),
      );
      expect(blockedRename.statusCode, 409);
      expect(json.decode(blockedRename.body)['error'], 'file-in-use');
      expect(
        json.decode(blockedRename.body)['message'],
        contains('idle.slideshow.images[0]'),
      );

      final blockedParentDelete = await client.delete(
        Uri.parse('http://127.0.0.1:$port/api/files?path=photos'),
        headers: headers,
      );
      expect(blockedParentDelete.statusCode, 409);
      expect(json.decode(blockedParentDelete.body)['error'], 'file-in-use');

      final blockedBatch = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/files/change-check'),
        headers: headers,
        body: json.encode({
          'paths': ['photos/large.json', 'photos/hello.txt'],
        }),
      );
      expect(blockedBatch.statusCode, 409);
      expect(json.decode(blockedBatch.body)['error'], 'file-in-use');

      final blocked = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/files/list?path=..%2F'),
        headers: headers,
      );
      expect(blocked.statusCode, 400);

      effectiveConfig = {
        'schemaVersion': 2,
        'layout': {'barHeight': 96},
      };

      final remove = await client.delete(
        Uri.parse('http://127.0.0.1:$port/api/files?path=photos'),
        headers: headers,
      );
      expect(remove.statusCode, 200);

      final save = await client.put(
        Uri.parse('http://127.0.0.1:$port/api/config'),
        headers: headers,
        body: json.encode({
          'schemaVersion': 1,
          'layout': {'barHeight': 80},
        }),
      );
      expect(save.statusCode, 200);
      expect(config['layout'], {'barHeight': 80});

      final hide = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/actions/hide'),
        headers: headers,
      );
      expect(hide.statusCode, 202);
      expect(action, 'hide');

      await controller.updateSettings(
        controller.settings.copyWith(
          mdnsHostname: 'ysignage-test.local',
        ),
      );
      expect(controller.running, isTrue);
      expect(mdnsPublisher.hostname, 'ysignage-test.local');
      expect(mdnsPublisher.running, isTrue);
    } finally {
      client.close();
      await controller.close();
      expect(mdnsPublisher.running, isFalse);
      controller.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('설정 적용으로 API 컨트롤러가 재생성되어도 로그인 세션을 유지한다', () async {
    final directory =
        await Directory.systemTemp.createTemp('admin-api-session-test-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final settingsStore = AdminApiSettingsStore(
      file: File('${directory.path}${Platform.pathSeparator}admin-api.json'),
    );
    final pinStore = AdminPinStore(
      file: File('${directory.path}${Platform.pathSeparator}admin-pin.json'),
      iterations: 1,
    );
    await settingsStore.save(
      AdminApiSettings(
        port: port,
        webAdminSshForwardingEnabled: false,
      ),
    );

    AdminApiController createController() => AdminApiController(
          pinStore: pinStore,
          settingsStore: settingsStore,
          exdataFileService: ExdataFileService(
            rootPath: '${directory.path}${Platform.pathSeparator}exdata',
          ),
          uiThemeService: UiThemeService(
            userThemeDirectory:
                '${directory.path}${Platform.pathSeparator}themes',
            preloadedThemeLoader: () async => [],
          ),
          mdnsPublisher: _FakeMdnsPublisher(),
          pageLoader: () async => '<html>admin</html>',
          statusProvider: () async => {'running': true},
          actionHandler: (value) async => {'message': value},
          configReader: () async => {'schemaVersion': 2},
          configWriter: (_) async {},
        );

    final client = http.Client();
    var controller = createController();
    try {
      await controller.initialize();
      final login = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/login'),
        headers: {'content-type': 'application/json'},
        body: json.encode({'pin': AdminPinStore.defaultPin}),
      );
      final token = json.decode(login.body)['token'];
      final headers = {'authorization': 'Bearer $token'};

      await controller.close();
      controller.dispose();
      controller = createController();
      await controller.initialize();

      final status = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/status'),
        headers: headers,
      );
      expect(status.statusCode, 200);

      final refresh = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/session/refresh'),
        headers: headers,
      );
      expect(refresh.statusCode, 200);
      expect(json.decode(refresh.body)['expiresInSeconds'], 30 * 60);

      final logout = await client.post(
        Uri.parse('http://127.0.0.1:$port/api/logout'),
        headers: headers,
      );
      expect(logout.statusCode, 200);
    } finally {
      client.close();
      await controller.close();
      controller.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('사용 중인 포트 설정은 기존 관리 서버와 저장 설정을 유지한다', () async {
    final directory =
        await Directory.systemTemp.createTemp('admin-api-port-rollback-');
    final availableProbe =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final currentPort = availableProbe.port;
    await availableProbe.close();
    final occupied = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final settingsStore = AdminApiSettingsStore(
      file: File('${directory.path}${Platform.pathSeparator}admin-api.json'),
    );
    final initial = AdminApiSettings(
      port: currentPort,
      webAdminSshForwardingEnabled: false,
    );
    await settingsStore.save(initial);
    final controller = AdminApiController(
      settingsStore: settingsStore,
      exdataFileService: ExdataFileService(
        rootPath: '${directory.path}${Platform.pathSeparator}exdata',
      ),
      uiThemeService: UiThemeService(
        userThemeDirectory: '${directory.path}${Platform.pathSeparator}themes',
        preloadedThemeLoader: () async => [],
      ),
      mdnsPublisher: _FakeMdnsPublisher(),
      pageLoader: () async => '<html>admin</html>',
      statusProvider: () async => {'running': true},
      actionHandler: (value) async => {'message': value},
      configReader: () async => {'schemaVersion': 2},
      configWriter: (_) async {},
    );
    try {
      await controller.initialize();
      expect(controller.actualPort, currentPort);

      await expectLater(
        controller.updateSettings(initial.copyWith(port: occupied.port)),
        throwsFormatException,
      );

      expect(controller.running, isTrue);
      expect(controller.actualPort, currentPort);
      expect((await settingsStore.load()).port, currentPort);
    } finally {
      await occupied.close();
      await controller.close();
      controller.dispose();
      await directory.delete(recursive: true);
    }
  });
}
