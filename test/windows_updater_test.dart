import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/windows_updater.dart';

void main() {
  test('네이티브 업데이트 실행기 인수를 파싱한다', () {
    final options = NativeUpdateOptions.parse([
      '--package',
      r'C:\Signage\downloads\update.zip',
      '--version',
      '1.2.18',
      '--sha256',
      'a' * 64,
      '--app-pid',
      '1234',
      '--data-root',
      r'C:\Signage',
      '--retain-versions',
      '2',
      '--log-retention-days',
      '30',
      '--signature-verifier',
      r'C:\Signage\ysignage_launcher.exe',
      '--force-retry',
      '--require-authenticode',
      '--signer-thumbprint',
      'ab cd ef 01 23 45 67 89 ab cd ef 01 23 45 67 89 ab cd ef 01',
    ]);

    expect(options.version, '1.2.18');
    expect(options.appPid, 1234);
    expect(options.forceRetry, isTrue);
    expect(options.requireAuthenticode, isTrue);
    expect(
      options.expectedSignerThumbprint,
      'ABCDEF0123456789ABCDEF0123456789ABCDEF01',
    );
  });

  test('ZIP 경로 이탈과 심볼릭 링크용 절대 경로를 거부한다', () {
    expect(isSafeArchiveEntry('package/data/flutter_assets/a.json'), isTrue);
    expect(isSafeArchiveEntry('../outside.exe'), isFalse);
    expect(isSafeArchiveEntry(r'package\..\outside.exe'), isFalse);
    expect(isSafeArchiveEntry(r'C:\Windows\outside.exe'), isFalse);
    expect(isSafeArchiveEntry('/Windows/outside.exe'), isFalse);
    expect(isSafeArchiveEntry('package/file.txt:stream'), isFalse);
    expect(isSafeArchiveEntry('package/CON.txt'), isFalse);
  });

  test('필수 인수와 해시 형식을 검증한다', () {
    expect(
      () => NativeUpdateOptions.parse(const []),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => NativeUpdateOptions.parse([
        '--package',
        'update.zip',
        '--version',
        '1.2.18',
        '--sha256',
        'invalid',
        '--app-pid',
        '1',
        '--data-root',
        'data',
        '--retain-versions',
        '2',
        '--log-retention-days',
        '30',
        '--signature-verifier',
        'launcher.exe',
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('Windows 실행 파일 경로는 대소문자와 무관하게 비교한다', () {
    expect(
      sameWindowsPath(
        r'C:\Signage\updater\ysignage_updater.exe',
        r'c:\signage\UPDATER\ysignage_updater.exe',
      ),
      isTrue,
    );
  });

  test('수동 재시도는 3회 실패 차단을 우회한다', () async {
    final root = await Directory.systemTemp.createTemp('updater-force-retry-');
    addTearDown(() => root.delete(recursive: true));
    final stateFile = File(
      '${root.path}${Platform.pathSeparator}state'
      '${Platform.pathSeparator}update-state.json',
    );
    await stateFile.parent.create(recursive: true);

    NativeUpdateOptions options({required bool forceRetry}) =>
        NativeUpdateOptions(
          packagePath: '${root.path}${Platform.pathSeparator}missing.zip',
          version: '1.2.25',
          expectedSha256: 'a' * 64,
          appPid: 1,
          dataRoot: root.path,
          retainVersions: 2,
          logRetentionDays: 30,
          forceRetry: forceRetry,
          requireAuthenticode: false,
          expectedSignerThumbprint: null,
          signatureVerifierPath: 'launcher.exe',
        );

    Future<Map<String, dynamic>> run(
      bool forceRetry, {
      required DateTime windowStartedAt,
    }) async {
      await stateFile.writeAsString(json.encode({
        'schemaVersion': 1,
        'status': 'failed',
        'version': '1.2.25',
        'failureCount': 3,
        'failureWindowStartedAt': windowStartedAt.toUtc().toIso8601String(),
      }));
      await expectLater(
        NativeUpdateInstaller(options(forceRetry: forceRetry)).run(),
        throwsA(anything),
      );
      return json.decode(await stateFile.readAsString())
          as Map<String, dynamic>;
    }

    final automatic = await run(
      false,
      windowStartedAt: DateTime.now().toUtc(),
    );
    expect(automatic['error'], contains('자동 설치를 차단'));
    final manual = await run(
      true,
      windowStartedAt: DateTime.now().toUtc(),
    );
    expect(manual['error'], contains('업데이트 ZIP을 찾을 수 없습니다.'));
    expect(manual['error'], isNot(contains('자동 설치를 차단')));
    final expired = await run(
      false,
      windowStartedAt: DateTime.now()
          .toUtc()
          .subtract(updateFailureResetInterval)
          .subtract(const Duration(minutes: 1)),
    );
    expect(expired['error'], contains('업데이트 ZIP을 찾을 수 없습니다.'));
    expect(expired['failureCount'], 1);
  });
}
