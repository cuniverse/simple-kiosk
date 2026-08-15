import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/admin_api_settings.dart';
import 'package:simple_kiosk/service/admin_api_controller.dart';
import 'package:simple_kiosk/service/admin_api_settings_store.dart';
import 'package:simple_kiosk/service/admin_pin_store.dart';

void main() {
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
    final controller = AdminApiController(
      pinStore: AdminPinStore(file: pinFile, iterations: 1),
      settingsStore: settingsStore,
      pageLoader: () async => '<html>admin</html>',
      statusProvider: () async => {'running': true},
      actionHandler: (value) async {
        action = value;
        return {'message': value};
      },
      configReader: () async => config,
      configWriter: (value) async => config = value,
    );
    final client = http.Client();
    try {
      await controller.initialize();
      expect(controller.running, isTrue);

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
      final token = (json.decode(login.body) as Map<String, dynamic>)['token'];
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
    } finally {
      client.close();
      await controller.close();
      controller.dispose();
      await directory.delete(recursive: true);
    }
  });
}
