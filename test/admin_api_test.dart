import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/admin_api_settings.dart';
import 'package:simple_kiosk/service/admin_api_controller.dart';
import 'package:simple_kiosk/service/admin_api_settings_store.dart';
import 'package:simple_kiosk/service/admin_pin_store.dart';
import 'package:simple_kiosk/service/configuration_backup_service.dart';
import 'package:simple_kiosk/service/exdata_file_service.dart';
import 'package:simple_kiosk/service/mdns_service_controller.dart';
import 'package:simple_kiosk/service/manual_update_service.dart';
import 'package:simple_kiosk/service/screen_preview_service.dart';
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

class _BlockingStopMdnsPublisher extends _FakeMdnsPublisher {
  final Completer<void> stopStarted = Completer<void>();
  final Completer<void> allowStop = Completer<void>();

  @override
  Future<void> stop() async {
    if (!running) return;
    if (!stopStarted.isCompleted) stopStarted.complete();
    await allowStop.future;
    running = false;
  }
}

class _AssigningTunnel extends WebAdminSshTunnelController {
  Future<void> Function(String)? assign;
  String? preferred;
  bool fixed = false;

  @override
  Future<void> start(
      {required int localPort,
      required String? preferredId,
      bool fixedId = false,
      required Future<void> Function(String) onIdAssigned}) async {
    preferred = preferredId;
    fixed = fixedId;
    assign = onIdAssigned;
  }
}

void main() {
  test(
      'fixed forwarding ID survives save, reload and unrelated settings changes',
      () async {
    final directory = await Directory.systemTemp.createTemp('fixed-id-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/admin-api.json');
    final settings = AdminApiSettings.fromJson({
      'webAdminSshForwardingId': ' CHURCH-LOBBY ',
      'webAdminSshForwardingIdFixed': true,
    });
    await AdminApiSettingsStore(file: file).save(settings);
    final reloaded = await AdminApiSettingsStore(file: file).load();
    await AdminApiSettingsStore(file: file).save(reloaded.copyWith(port: 8080));
    final restored = await AdminApiSettingsStore(file: file).load();
    expect(restored.webAdminSshForwardingId, 'church-lobby');
    expect(restored.webAdminSshForwardingIdFixed, isTrue);
    final imported = ConfigurationBackupService.preserveDeviceIdentity(
      const AdminApiSettings(port: 9000, webAdminSshForwardingId: 'ysignage99'),
      restored,
    );
    expect(imported.webAdminSshForwardingId, 'church-lobby');
    expect(imported.webAdminSshForwardingIdFixed, isTrue);
    expect(imported.port, 9000);
    expect(
        WebAdminSshTunnelController.candidateIds('church-lobby', fixed: true)
            .take(4)
            .toList(),
        ['church-lobby', 'church-lobby-1', 'church-lobby-2', 'church-lobby-3']);
    expect(
        WebAdminSshTunnelController.candidateIds(null, fixed: true), isEmpty);
    expect(
        () => AdminApiSettings.fromJson({'webAdminSshForwardingIdFixed': true}),
        throwsFormatException);
  });

  test('suffixed IDs are valid and continue without nested suffixes', () {
    final settings = AdminApiSettings.fromJson({
      'webAdminSshForwardingId': ' YSIGNAGE42-2 ',
      'webAdminSshForwardingIdFixed': true,
    });
    expect(settings.webAdminSshForwardingId, 'ysignage42-2');
    expect(
        WebAdminSshTunnelController.candidateIds(
                settings.webAdminSshForwardingId,
                fixed: true)
            .take(4),
        ['ysignage42-2', 'ysignage42-3', 'ysignage42-4', 'ysignage42-5']);
    for (final invalid in [
      '',
      '-church',
      'church_lobby',
      'church.lobby',
      'church lobby',
      'ysignage7-',
      'ysignage7/1'
    ]) {
      expect(AdminApiSettings.isValidWebAdminSshForwardingId(invalid), isFalse);
    }
  });

  test(
      'custom fixed IDs preserve hyphens and continue collision suffixes within 63 characters',
      () {
    for (final id in [
      'yeouido',
      'church-lobby',
      'a',
      '7',
      'ysignage7-0',
      'building-7-1'
    ]) {
      expect(AdminApiSettings.isValidWebAdminSshForwardingId(id), isTrue);
    }
    final custom = AdminApiSettings.fromJson({
      'webAdminSshForwardingId': ' CHURCH-LOBBY ',
      'webAdminSshForwardingIdFixed': true,
    });
    expect(custom.webAdminSshForwardingId, 'church-lobby');
    expect(
        WebAdminSshTunnelController.candidateIds(custom.webAdminSshForwardingId,
                fixed: true)
            .take(3),
        ['church-lobby', 'church-lobby-1', 'church-lobby-2']);
    expect(
        WebAdminSshTunnelController.candidateIds('church-lobby-9', fixed: true)
            .take(3),
        ['church-lobby-9', 'church-lobby-10', 'church-lobby-11']);
    final longId = List.filled(63, 'a').join();
    expect(AdminApiSettings.isValidWebAdminSshForwardingId(longId), isTrue);
    expect(
        AdminApiSettings.isValidWebAdminSshForwardingId('${longId}a'), isFalse);
    final candidates =
        WebAdminSshTunnelController.candidateIds(longId, fixed: true)
            .take(12)
            .toList();
    expect(candidates.toSet().length, 12);
    expect(candidates.every(AdminApiSettings.isValidWebAdminSshForwardingId),
        isTrue);
    expect(candidates[1], '${longId.substring(0, 61)}-1');
    expect(candidates[10], '${longId.substring(0, 60)}-10');
  });

  test(
      'assigned suffix persists as fixed and stale connections cannot overwrite a new ID',
      () async {
    final root = await Directory.systemTemp.createTemp('assigned-id-test-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final store =
        AdminApiSettingsStore(file: File('${root.path}/admin-api.json'));
    await store.save(AdminApiSettings(
        port: port,
        mdnsEnabled: false,
        webAdminSshForwardingId: 'ysignage7',
        webAdminSshForwardingIdFixed: true));
    final tunnel = _AssigningTunnel();
    final controller = AdminApiController(
      settingsStore: store,
      webAdminSshTunnelController: tunnel,
      exdataFileService: ExdataFileService(rootPath: '${root.path}/exdata'),
      uiThemeService: UiThemeService(
          userThemeDirectory: '${root.path}/themes',
          preloadedThemeLoader: () async => []),
      mdnsPublisher: _FakeMdnsPublisher(),
      statusProvider: () async => {},
      actionHandler: (_) async => {},
      configReader: () async => {},
      configWriter: (_) async {},
    );
    try {
      await controller.initialize();
      final oldAssignment = tunnel.assign!;
      await oldAssignment('ysignage7-1');
      expect((await store.load()).webAdminSshForwardingId, 'ysignage7-1');
      expect((await store.load()).webAdminSshForwardingIdFixed, isTrue);
      await oldAssignment('ysignage7-2');
      await controller.updateSettings(controller.settings);
      expect(tunnel.preferred, 'ysignage7-2');
      expect(tunnel.fixed, isTrue);
      await controller.updateSettings(
          controller.settings.copyWith(webAdminSshForwardingId: 'ysignage99'));
      await oldAssignment('ysignage7-3');
      expect((await store.load()).webAdminSshForwardingId, 'ysignage99');
    } finally {
      await controller.close();
      controller.dispose();
      await root.delete(recursive: true);
    }
  });
  test('mDNS 설정은 ysignage.local을 기본값으로 사용한다', () {
    final settings = AdminApiSettings.fromJson(const {});

    expect(settings.mdnsEnabled, isTrue);
    expect(settings.mdnsHostname, 'ysignage.local');
    expect(settings.webAdminSshForwardingEnabled, isTrue);
    expect(settings.webAdminSshForwardingId, isNull);
    expect(settings.screenPreviewFps, 2);
    expect(settings.screenPreviewWidth, 1280);
    expect(settings.screenPreviewJpegQuality, 45);
    expect(settings.toJson()['schemaVersion'], 5);
    expect(
      () => AdminApiSettings.fromJson(
        const {'mdnsHostname': 'not-a-local-name'},
      ),
      throwsFormatException,
    );
    expect(
      () => AdminApiSettings.fromJson(const {'screenPreviewFps': 6}),
      throwsFormatException,
    );
    expect(
      () => AdminApiSettings.fromJson(const {'screenPreviewWidth': 2000}),
      throwsFormatException,
    );
    expect(
      () => AdminApiSettings.fromJson(
        const {'screenPreviewJpegQuality': 10},
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
        const {'webAdminSshForwardingId': 'invalid/id'},
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
    String? installedUploadVersion;
    final previewClicks = <(int, int)>[];
    final previewPointerEvents = <String>[];
    final mdnsPublisher = _FakeMdnsPublisher();
    var networkSyncCalls = 0;
    var synchronizedBeforeInitialBind = false;
    final controller = AdminApiController(
      pinStore: AdminPinStore(file: pinFile, iterations: 1),
      settingsStore: settingsStore,
      manualUpdateService:
          ManualUpdateService(rootPath: '${directory.path}/manual-upload'),
      uploadedUpdateInstaller: (update) async {
        installedUploadVersion = update.manifest.version;
      },
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
      screenPreviewService: ScreenPreviewService(
        clock: () => DateTime.utc(2026, 8, 29, 12),
        clicker: (_, x, y) async => previewClicks.add((x, y)),
        pointerSender: (_, x, y, phase) => previewPointerEvents.add(phase),
        frameCapturer: (_) async => ScreenPreviewFrame(
          jpegBytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
          width: 1280,
          height: 720,
          capturedAt: DateTime.utc(2026, 8, 29, 12),
          target: const ScreenPreviewTarget(
              window: 1, left: -1920, top: 0, width: 1920, height: 1080),
        ),
      ),
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

      const zipName = 'simple-kiosk-windows-1.2.36.zip';
      const zipUploadId = 'admin-upload-123';
      final archive = Archive();
      for (final name in [
        'ysignage.exe',
        'ysignage_launcher.exe',
        'flutter_windows.dll',
        'data/app.so',
        'updater/ysignage_updater.exe'
      ]) {
        archive.addFile(
            ArchiveFile('simple-kiosk-windows-1.2.36/$name', 3, [1, 2, 3]));
      }
      final zip = ZipEncoder().encode(archive);
      final uploadUri = Uri.parse('http://127.0.0.1:$port/api/updates/upload')
          .replace(queryParameters: {
        'filename': zipName,
        'uploadId': zipUploadId,
        'offset': '0',
        'total': '${zip.length}',
        'complete': 'true',
      });
      expect((await client.put(uploadUri, body: zip)).statusCode, 401);
      expect(installedUploadVersion, isNull);
      final uploaded = await client.put(uploadUri,
          headers: {
            ...headers,
            'content-type': 'application/octet-stream',
          },
          body: zip);
      expect(uploaded.statusCode, 201, reason: uploaded.body);
      expect(installedUploadVersion, isNull);
      final installUri =
          Uri.parse('http://127.0.0.1:$port/api/updates/install');
      expect(
          (await client.post(installUri,
                  body: json.encode({'uploadId': zipUploadId})))
              .statusCode,
          401);
      final installed = await client.post(installUri,
          headers: headers, body: json.encode({'uploadId': zipUploadId}));
      expect(installed.statusCode, 202);
      expect(installedUploadVersion, '1.2.36');
      expect(
          (await client.post(installUri,
                  headers: headers,
                  body: json.encode({'uploadId': zipUploadId})))
              .statusCode,
          404);

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
      expect(json.decode(serverSettings.body)['screenPreviewFps'], 2);
      expect(json.decode(serverSettings.body)['screenPreviewWidth'], 1280);
      expect(json.decode(serverSettings.body)['screenPreviewJpegQuality'], 45);

      final unauthorizedPreview = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/screen-preview'),
      );
      expect(unauthorizedPreview.statusCode, 401);

      final preview = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/screen-preview'),
        headers: headers,
      );
      expect(preview.statusCode, 200);
      expect(preview.headers['content-type'], startsWith('image/jpeg'));
      expect(preview.headers['x-screen-width'], '1280');
      expect(preview.headers['x-screen-height'], '720');
      expect(preview.headers['x-signage-state'], 'visible');
      expect(preview.bodyBytes, [0xff, 0xd8, 0xff, 0xd9]);
      expect(preview.headers['x-screen-clickable'], 'true');
      final clickUri =
          Uri.parse('http://127.0.0.1:$port/api/screen-preview/click');
      final clickBody = json.encode({
        'frameId': preview.headers['x-frame-id'],
        'x': 0.5,
        'y': 0.25,
      });
      final unauthorizedClick = await client.post(clickUri, body: clickBody);
      expect(unauthorizedClick.statusCode, 401);
      expect(previewClicks, isEmpty);
      final click =
          await client.post(clickUri, headers: headers, body: clickBody);
      expect(click.statusCode, 200);
      expect(previewClicks, [(-960, 270)]);
      final invalidClick = await client.post(clickUri,
          headers: headers,
          body: json.encode(
              {'frameId': preview.headers['x-frame-id'], 'x': 2, 'y': 0}));
      expect(invalidClick.statusCode, 400);
      final staleClick = await client.post(clickUri,
          headers: headers,
          body: json.encode({'frameId': 'unknown', 'x': 0, 'y': 0}));
      expect(staleClick.statusCode, 409);
      expect(previewClicks.length, 1);
      final pointerUri =
          Uri.parse('http://127.0.0.1:$port/api/screen-preview/pointer');
      final pointerBody = {
        'gestureId': 'test-drag',
        'sequence': 1,
        'phase': 'down',
        'frameId': preview.headers['x-frame-id'],
        'x': 0.5,
        'y': 0.5
      };
      expect(
          (await client.post(pointerUri, body: json.encode(pointerBody)))
              .statusCode,
          401);
      expect(previewPointerEvents, isEmpty);
      for (final phase in ['down', 'move', 'up']) {
        pointerBody['phase'] = phase;
        expect(
            (await client.post(pointerUri,
                    headers: headers, body: json.encode(pointerBody)))
                .statusCode,
            200);
        pointerBody['sequence'] = (pointerBody['sequence'] as int) + 1;
      }
      expect(previewPointerEvents, ['down', 'move', 'up']);
      pointerBody['phase'] = 'invalid';
      expect(
          (await client.post(pointerUri,
                  headers: headers, body: json.encode(pointerBody)))
              .statusCode,
          400);

      final savePreviewFps = await client.put(
        Uri.parse('http://127.0.0.1:$port/api/screen-preview/settings'),
        headers: headers,
        body: json.encode({'fps': 5, 'width': 1920, 'quality': 35}),
      );
      expect(savePreviewFps.statusCode, 200);
      expect(json.decode(savePreviewFps.body)['fps'], 5);
      expect(json.decode(savePreviewFps.body)['width'], 1920);
      expect(json.decode(savePreviewFps.body)['quality'], 35);
      expect((await settingsStore.load()).screenPreviewFps, 5);
      expect((await settingsStore.load()).screenPreviewWidth, 1920);
      expect((await settingsStore.load()).screenPreviewJpegQuality, 35);

      final invalidPreviewFps = await client.put(
        Uri.parse('http://127.0.0.1:$port/api/screen-preview/settings'),
        headers: headers,
        body: json.encode({'fps': 6}),
      );
      expect(invalidPreviewFps.statusCode, 400);

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

  test('이전 API 서버 종료가 끝난 뒤 새 컨트롤러가 같은 포트를 연다', () async {
    final directory = await Directory.systemTemp
        .createTemp('admin-api-lifecycle-serialization-test-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final settingsStore = AdminApiSettingsStore(
      file: File('${directory.path}${Platform.pathSeparator}admin-api.json'),
    );
    await settingsStore.save(
      AdminApiSettings(
        port: port,
        webAdminSshForwardingEnabled: false,
      ),
    );
    final firstMdns = _BlockingStopMdnsPublisher();

    AdminApiController createController(MdnsPublisher mdnsPublisher) =>
        AdminApiController(
          settingsStore: settingsStore,
          exdataFileService: ExdataFileService(
            rootPath: '${directory.path}${Platform.pathSeparator}exdata',
          ),
          uiThemeService: UiThemeService(
            userThemeDirectory:
                '${directory.path}${Platform.pathSeparator}themes',
            preloadedThemeLoader: () async => [],
          ),
          mdnsPublisher: mdnsPublisher,
          pageLoader: () async => '<html>admin</html>',
          statusProvider: () async => {'running': true},
          actionHandler: (value) async => {'message': value},
          configReader: () async => {'schemaVersion': 2},
          configWriter: (_) async {},
        );

    final first = createController(firstMdns);
    final second = createController(_FakeMdnsPublisher());
    try {
      await first.initialize();
      final firstClose = first.close();
      await firstMdns.stopStarted.future;

      var secondInitializeCompleted = false;
      final secondInitialize = second.initialize().then(
            (_) => secondInitializeCompleted = true,
          );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(secondInitializeCompleted, isFalse);

      firstMdns.allowStop.complete();
      await firstClose;
      await secondInitialize;
      expect(second.running, isTrue);
      expect(second.actualPort, port);
    } finally {
      if (!firstMdns.allowStop.isCompleted) firstMdns.allowStop.complete();
      await first.close();
      first.dispose();
      await second.close();
      second.dispose();
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
