import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/update_manifest.dart';
import 'package:simple_kiosk/model/update_policy.dart';
import 'package:simple_kiosk/service/update_controller.dart';
import 'package:simple_kiosk/service/update_service.dart';

void main() {
  test('시작 시 자동 업데이트가 켜져 있으면 즉시 검사·다운로드·설치한다', () async {
    final service = _FakeUpdateService(updateAvailable: true);
    int? exitCode;
    final controller = UpdateController(
      service: service,
      supportedOverride: true,
      currentVersionLoader: () async => '1.2.23',
      policyLoader: () async => const UpdatePolicy(
        enabled: true,
        installWhenIdle: true,
        installWindow: UpdateInstallWindow(start: '00:00', end: '00:00'),
      ),
      policySaver: (_) async {},
      exitApplication: (code) => exitCode = code,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.startupUpdateDone;

    expect(service.checkCalls, 1);
    expect(service.downloadCalls, 1);
    expect(service.installCalls, 1);
    expect(exitCode, 0);
  });

  test('시작 시 자동 업데이트가 꺼져 있으면 검사하지 않는다', () async {
    final service = _FakeUpdateService(updateAvailable: true);
    final controller = UpdateController(
      service: service,
      supportedOverride: true,
      currentVersionLoader: () async => '1.2.23',
      policyLoader: () async => const UpdatePolicy(enabled: false),
      policySaver: (_) async {},
      exitApplication: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.startupUpdateDone;

    expect(service.checkCalls, 0);
    expect(service.downloadCalls, 0);
    expect(service.installCalls, 0);
  });
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({required this.updateAvailable});

  final bool updateAvailable;
  int checkCalls = 0;
  int downloadCalls = 0;
  int installCalls = 0;

  final _manifest = const UpdateManifest(
    version: '1.2.24',
    channel: 'stable',
    minimumUpdaterVersion: '1.0.0',
    configSchemaVersion: 1,
    packageFile: 'simple-kiosk-windows-1.2.24.zip',
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );

  @override
  Future<AvailableUpdate?> check({String? currentVersion}) async {
    checkCalls += 1;
    return updateAvailable
        ? AvailableUpdate(
            _manifest, Uri.parse('https://example.com/update.zip'))
        : null;
  }

  @override
  Future<File> download(AvailableUpdate update) async {
    downloadCalls += 1;
    return File('downloaded-update.zip');
  }

  @override
  Future<void> requestInstall(
    File package,
    UpdateManifest manifest, {
    int retainVersions = 2,
    int logRetentionDays = 30,
  }) async {
    installCalls += 1;
  }

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}
}
