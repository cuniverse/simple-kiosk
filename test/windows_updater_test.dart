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
      '--require-authenticode',
      '--signer-thumbprint',
      'ab cd ef 01 23 45 67 89 ab cd ef 01 23 45 67 89 ab cd ef 01',
    ]);

    expect(options.version, '1.2.18');
    expect(options.appPid, 1234);
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
}
