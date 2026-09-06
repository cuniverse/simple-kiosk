import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/windows_kiosk_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simple_kiosk/windows_kiosk_mode');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('PC shutdown requests the native operation without exiting the app',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await WindowsKioskMode.shutdownComputer();
    expect(calls, ['shutdownComputer']);
  }, skip: !Platform.isWindows);

  test('Windows shutdown rejection reaches the admin action caller', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'pc-shutdown-failed', message: '권한 없음');
    });
    await expectLater(
        WindowsKioskMode.shutdownComputer(),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'pc-shutdown-failed')));
  }, skip: !Platform.isWindows);

  test('older Windows runners report an update requirement', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });
    await expectLater(
        WindowsKioskMode.shutdownComputer(), throwsA(isA<UnsupportedError>()));
  }, skip: !Platform.isWindows);
}
