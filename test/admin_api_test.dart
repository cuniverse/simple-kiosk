import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/admin_api_settings.dart';
import 'package:simple_kiosk/service/admin_api_controller.dart';
import 'package:simple_kiosk/service/admin_api_settings_store.dart';
import 'package:simple_kiosk/service/admin_pin_store.dart';
import 'package:simple_kiosk/service/mdns_service_controller.dart';

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
    expect(settings.toJson()['schemaVersion'], 2);
    expect(
      () => AdminApiSettings.fromJson(
        const {'mdnsHostname': 'not-a-local-name'},
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
    await settingsStore.save(AdminApiSettings(port: port));
    Map<String, dynamic> config = {'schemaVersion': 1};
    String? action;
    final mdnsPublisher = _FakeMdnsPublisher();
    final controller = AdminApiController(
      pinStore: AdminPinStore(file: pinFile, iterations: 1),
      settingsStore: settingsStore,
      mdnsPublisher: mdnsPublisher,
      pageLoader: () async => '<html>admin</html>',
      statusProvider: () async => {'running': true},
      actionHandler: (value) async {
        action = value;
        return {'message': value};
      },
      configReader: () async => config,
      effectiveConfigReader: () async => {
        'schemaVersion': 2,
        'layout': {'barHeight': 96},
      },
      defaultConfigReader: () async => {
        'schemaVersion': 2,
        'layout': {'barHeight': 88},
      },
      configWriter: (value) async => config = value,
    );
    final client = http.Client();
    try {
      await controller.initialize();
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
      expect(json.decode(status.body)['running'], isTrue);
      expect(
        json.decode(status.body)['adminApi']['mdnsHostname'],
        'ysignage.local',
      );

      final effectiveConfig = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/config/effective'),
        headers: headers,
      );
      expect(effectiveConfig.statusCode, 200);
      expect(json.decode(effectiveConfig.body)['layout']['barHeight'], 96);

      final defaultConfig = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/config/defaults'),
        headers: headers,
      );
      expect(defaultConfig.statusCode, 200);
      expect(json.decode(defaultConfig.body)['layout']['barHeight'], 88);

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
    await settingsStore.save(AdminApiSettings(port: port));

    AdminApiController createController() => AdminApiController(
          pinStore: pinStore,
          settingsStore: settingsStore,
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
}
