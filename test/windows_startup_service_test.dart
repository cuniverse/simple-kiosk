import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/windows_startup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simple_kiosk/windows_startup');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  final nativeCalls = <String>[];

  test('automatic migration uses only the conditional migration action',
      () async {
    final actions = <String>[];
    final service = WindowsStartupService(
        installRootOverride: root.path,
        processRunner: (_, arguments) async {
          actions.add(arguments[arguments.indexOf('-Action') + 1]);
          return ProcessResult(1, 0, '{"registered":false}', '');
        });
    await service.migrateLegacyRegistration();
    expect(actions, ['Migrate']);
    expect(nativeCalls, isEmpty);
  }, skip: !Platform.isWindows);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('startup-service-test-');
    await File('${root.path}/updater/configure-startup.ps1')
        .create(recursive: true);
    nativeCalls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'getStatus') {
        return {'supported': true, 'registered': true, 'mode': 'hidden'};
      }
      return true;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test('task registration preserves hidden mode and creates no legacy shortcut',
      () async {
    final service = WindowsStartupService(
        installRootOverride: root.path,
        processRunner: (executable, arguments) async {
          expect(arguments[arguments.indexOf('-Action') + 1], 'Register');
          expect(arguments[arguments.indexOf('-Mode') + 1], 'hidden');
          expect(arguments[arguments.indexOf('-InstallRoot') + 1], root.path);
          return ProcessResult(
              1,
              0,
              jsonEncode({
                'supported': true,
                'registered': true,
                'targetMatches': true,
                'method': 'task',
                'mode': 'hidden'
              }),
              '');
        });
    final status = await service.register(StartupLaunchMode.hidden);
    expect(status.fastStartup, isTrue);
    expect(status.mode, StartupLaunchMode.hidden);
    expect(nativeCalls, isEmpty);
  }, skip: !Platform.isWindows);

  test('failed task registration leaves legacy registration untouched',
      () async {
    final service = WindowsStartupService(
        installRootOverride: root.path,
        processRunner: (_, __) async =>
            ProcessResult(1, 1, '', 'access denied'));
    await expectLater(
        service.register(StartupLaunchMode.signage), throwsStateError);
    expect(nativeCalls, isEmpty);
  }, skip: !Platform.isWindows);

  test('legacy status is read without automatically registering a task',
      () async {
    final service = WindowsStartupService(
        installRootOverride: root.path,
        processRunner: (_, arguments) async {
          expect(arguments[arguments.indexOf('-Action') + 1], 'Status');
          return ProcessResult(1, 0, '{"registered":false}', '');
        });
    final status = await service.getStatus();
    expect(status.fastStartup, isFalse);
    expect(status.mode, StartupLaunchMode.hidden);
    expect(nativeCalls, ['getStatus']);
  }, skip: !Platform.isWindows);

  test('disabled scheduled task is reported without re-enabling it', () async {
    final service = WindowsStartupService(
        installRootOverride: root.path,
        processRunner: (_, arguments) async {
          expect(arguments[arguments.indexOf('-Action') + 1], 'Status');
          return ProcessResult(
              1, 0, '{"registered":true,"method":"task","enabled":false}', '');
        });
    final status = await service.getStatus();
    expect(status.fastStartup, isTrue);
    expect(status.enabled, isFalse);
    expect(nativeCalls, isEmpty);
  }, skip: !Platform.isWindows);

  test('unregister removes task before removing legacy shortcuts', () async {
    final actions = <String>[];
    final service = WindowsStartupService(
        installRootOverride: root.path,
        processRunner: (_, arguments) async {
          actions.add(arguments[arguments.indexOf('-Action') + 1]);
          if (actions.length == 1) expect(nativeCalls, isEmpty);
          return ProcessResult(1, 0, '{"registered":false}', '');
        });
    await service.unregister();
    expect(actions, ['Unregister', 'Status']);
    expect(nativeCalls, ['unregister', 'getStatus']);
  }, skip: !Platform.isWindows);
}
