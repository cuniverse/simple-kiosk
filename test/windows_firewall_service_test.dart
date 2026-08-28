import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/admin_api_settings.dart';
import 'package:simple_kiosk/service/windows_firewall_service.dart';

void main() {
  late Directory directory;
  late File script;
  late File state;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('firewall-sync-test-');
    script = File(
      '${directory.path}${Platform.pathSeparator}'
      'updater${Platform.pathSeparator}configure-firewall.ps1',
    );
    state = File(
      '${directory.path}${Platform.pathSeparator}'
      'state${Platform.pathSeparator}firewall.json',
    );
    await script.parent.create(recursive: true);
    await script.writeAsString('# test helper');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('일치하는 방화벽 상태는 관리자 승인을 다시 요청하지 않는다', () async {
    await _writeState(state, port: 8080, mdnsEnabled: true);
    var processCalls = 0;
    final service = WindowsFirewallService(
      supportedOverride: true,
      installRootOverride: directory.path,
      processRunner: (executable, arguments) async {
        processCalls++;
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await service.reconcile(
      const AdminApiSettings(port: 8080),
    );

    expect(result, WindowsFirewallSyncResult.unchanged);
    expect(processCalls, 0);
  });

  test('포트가 달라지면 관리자 권한으로 Install 후 상태를 검증한다', () async {
    await _writeState(state, port: 80, mdnsEnabled: true);
    late List<String> capturedArguments;
    final service = WindowsFirewallService(
      supportedOverride: true,
      installRootOverride: directory.path,
      processRunner: (executable, arguments) async {
        expect(executable, 'powershell.exe');
        capturedArguments = arguments;
        await _writeState(state, port: 8080, mdnsEnabled: false);
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await service.reconcile(
      const AdminApiSettings(port: 8080, mdnsEnabled: false),
    );

    expect(result, WindowsFirewallSyncResult.installed);
    expect(capturedArguments, contains('-Command'));
    final command = capturedArguments.last;
    expect(command, contains('-Verb RunAs'));
    expect(command, contains('-Action Install'));
    expect(command, isNot(contains(r'\"powershell.exe\"')));
  });

  test('관리 API를 끄면 기존 관리 규칙을 제거한다', () async {
    await _writeState(state, port: 80, mdnsEnabled: true);
    final service = WindowsFirewallService(
      supportedOverride: true,
      installRootOverride: directory.path,
      processRunner: (executable, arguments) async {
        expect(arguments.last, contains('-Action Remove'));
        await state.delete();
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await service.reconcile(
      const AdminApiSettings(enabled: false),
    );

    expect(result, WindowsFirewallSyncResult.removed);
  });

  test('사용자가 UAC를 취소하면 실패로 반환하고 상태를 성공 처리하지 않는다', () async {
    final service = WindowsFirewallService(
      supportedOverride: true,
      installRootOverride: directory.path,
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 1, '', 'cancelled'),
    );

    final result = await service.reconcile(const AdminApiSettings());

    expect(result, WindowsFirewallSyncResult.declinedOrFailed);
    expect(await state.exists(), isFalse);
  });

  test('승인 처리 중 설정이 다시 바뀌면 다음 규칙 동기화를 순서대로 실행한다', () async {
    final firstApproval = Completer<void>();
    var processCalls = 0;
    final service = WindowsFirewallService(
      supportedOverride: true,
      installRootOverride: directory.path,
      processRunner: (executable, arguments) async {
        processCalls++;
        if (processCalls == 1) {
          await firstApproval.future;
          await _writeState(state, port: 80, mdnsEnabled: true);
        } else {
          await _writeState(state, port: 8080, mdnsEnabled: false);
        }
        return ProcessResult(processCalls, 0, '', '');
      },
    );

    final first = service.reconcile(const AdminApiSettings());
    final second = service.reconcile(
      const AdminApiSettings(port: 8080, mdnsEnabled: false),
    );
    firstApproval.complete();

    expect(await first, WindowsFirewallSyncResult.installed);
    expect(await second, WindowsFirewallSyncResult.installed);
    expect(processCalls, 2);
  });
}

Future<void> _writeState(
  File state, {
  required int port,
  required bool mdnsEnabled,
}) async {
  await state.parent.create(recursive: true);
  await state.writeAsString(
    jsonEncode({
      'action': 'Install',
      'profile': ['Domain', 'Private'],
      'remoteAddress': 'LocalSubnet',
      'webAdmin': {'enabled': true, 'protocol': 'TCP', 'port': port},
      'mdns': {
        'enabled': mdnsEnabled,
        'protocol': 'UDP',
        'port': 5353,
      },
    }),
  );
}
