import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simple_kiosk/model/update_manifest.dart';
import 'package:simple_kiosk/model/update_policy.dart';
import 'package:simple_kiosk/service/update_controller.dart';
import 'package:simple_kiosk/service/update_service.dart';

void main() {
  test('Release의 Setup EXE URL과 GitHub SHA-256을 확인한다', () async {
    const setupHash =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/releases/latest')) {
        return http.Response(
          json.encode({
            'draft': false,
            'prerelease': false,
            'assets': [
              {
                'name': 'update-manifest.json',
                'browser_download_url':
                    'https://github.com/example/update-manifest.json',
              },
              {
                'name': 'simple-kiosk-windows-1.2.25.zip',
                'browser_download_url': 'https://github.com/example/update.zip',
              },
              {
                'name': 'simple-kiosk-windows-setup-1.2.25.exe',
                'browser_download_url': 'https://github.com/example/setup.exe',
                'digest': 'sha256:$setupHash',
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        json.encode({
          'schemaVersion': 1,
          'version': '1.2.25',
          'channel': 'stable',
          'publishedAt': '2026-08-28T00:00:00Z',
          'minimumUpdaterVersion': '1.0.0',
          'configSchemaVersion': 1,
          'package': {
            'file': 'simple-kiosk-windows-1.2.25.zip',
            'sha256': 'a' * 64,
            'authenticodeRequired': false,
          },
        }),
        200,
      );
    });
    final service = UpdateService(client: client);
    addTearDown(service.close);

    final update = await service.check(currentVersion: '1.2.22');

    expect(update?.setupUrl, Uri.parse('https://github.com/example/setup.exe'));
    expect(update?.setupSha256, setupHash);
  });

  test('새 대상 버전에 이전 버전의 실패 횟수를 승계하지 않는다', () {
    final merged = UpdateService.mergeUpdateState(
      previous: const {
        'schemaVersion': 1,
        'status': 'failed',
        'version': '1.2.20',
        'failureCount': 13,
        'failureWindowStartedAt': '2026-08-27T00:00:00.000Z',
        'error': 'old failure',
      },
      state: const {
        'status': 'install-requested',
        'version': '1.2.25',
        'packagePath': 'update.zip',
      },
      updatedAt: DateTime.utc(2026, 8, 28),
    );

    expect(merged['version'], '1.2.25');
    expect(merged['failureCount'], isNull);
    expect(merged['failureWindowStartedAt'], isNull);
    expect(merged['error'], isNull);
  });

  test('같은 대상 버전의 실패 횟수는 유지한다', () {
    final merged = UpdateService.mergeUpdateState(
      previous: const {
        'version': '1.2.25',
        'failureCount': 2,
        'error': 'retry failure',
      },
      state: const {'status': 'install-requested', 'version': '1.2.25'},
      updatedAt: DateTime.utc(2026, 8, 28),
    );

    expect(merged['failureCount'], 2);
    expect(merged['error'], 'retry failure');
  });

  test('업데이터 조기 종료 시 상태 파일의 실제 오류를 표시한다', () {
    final message = UpdateService.updateStartFailureMessage(
      exitCode: 1,
      state: const {
        'status': 'failed',
        'error': 'StateError: 세 번 설치에 실패한 버전입니다.',
      },
      stderr: '표시되지 않아야 함',
    );

    expect(message, contains('세 번 설치에 실패한 버전입니다.'));
    expect(message, isNot(contains('표시되지 않아야 함')));
  });

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
    expect(service.lastForceRetry, isFalse);
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

  test('수동 설치는 실패 횟수 차단을 무시하도록 요청한다', () async {
    final service = _FakeUpdateService(updateAvailable: true);
    final controller = UpdateController(
      service: service,
      supportedOverride: true,
      currentVersionLoader: () async => '1.2.22',
      policyLoader: () async => const UpdatePolicy(enabled: false),
      policySaver: (_) async {},
      exitApplication: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.download(allowAutoInstall: false);
    await controller.installNow(manual: true);

    expect(service.installCalls, 1);
    expect(service.lastForceRetry, isTrue);
  });

  test('수동 updater 실패 시 검증한 Setup을 실행한다', () async {
    final service = _FakeUpdateService(
      updateAvailable: true,
      failNativeInstall: true,
      setupAvailable: true,
    );
    int? exitCode;
    final controller = UpdateController(
      service: service,
      supportedOverride: true,
      currentVersionLoader: () async => '1.2.22',
      policyLoader: () async => const UpdatePolicy(enabled: false),
      policySaver: (_) async {},
      exitApplication: (code) => exitCode = code,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.download(allowAutoInstall: false);
    await controller.installNow(
      manual: true,
      confirmSetupFallback: (_) async => true,
    );

    expect(service.setupDownloadCalls, 1);
    expect(service.setupLaunchCalls, 1);
    expect(exitCode, 0);
  });

  test('Setup 보조 설치를 거절하면 다운로드하지 않는다', () async {
    final service = _FakeUpdateService(
      updateAvailable: true,
      failNativeInstall: true,
      setupAvailable: true,
    );
    final controller = UpdateController(
      service: service,
      supportedOverride: true,
      currentVersionLoader: () async => '1.2.22',
      policyLoader: () async => const UpdatePolicy(enabled: false),
      policySaver: (_) async {},
      exitApplication: (_) {},
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.download(allowAutoInstall: false);
    await expectLater(
      controller.installNow(
        manual: true,
        confirmSetupFallback: (_) async => false,
      ),
      throwsA(isA<StateError>()),
    );

    expect(service.setupDownloadCalls, 0);
    expect(service.setupLaunchCalls, 0);
  });
}

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({
    required this.updateAvailable,
    this.failNativeInstall = false,
    this.setupAvailable = false,
  });

  final bool updateAvailable;
  final bool failNativeInstall;
  final bool setupAvailable;
  int checkCalls = 0;
  int downloadCalls = 0;
  int installCalls = 0;
  bool? lastForceRetry;
  int setupDownloadCalls = 0;
  int setupLaunchCalls = 0;

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
            _manifest,
            Uri.parse('https://example.com/update.zip'),
            setupUrl: setupAvailable
                ? Uri.parse('https://example.com/setup.exe')
                : null,
            setupSha256: setupAvailable ? 'b' * 64 : null,
          )
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
    bool forceRetry = false,
  }) async {
    installCalls += 1;
    lastForceRetry = forceRetry;
    if (failNativeInstall) throw StateError('native updater failed');
  }

  @override
  Future<File> downloadSetupInstaller(AvailableUpdate update) async {
    setupDownloadCalls += 1;
    return File('setup.exe');
  }

  @override
  Future<void> launchSetupInstaller(File installer) async {
    setupLaunchCalls += 1;
  }

  @override
  Future<void> writeState(Map<String, dynamic> state) async {}
}
