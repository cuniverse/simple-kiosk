import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/high_contrast_default_migration.dart';

void main() {
  late Directory temporary;
  late File overrideFile;
  late File markerFile;
  late Directory backupDirectory;

  const defaults = <String, dynamic>{
    'schemaVersion': 2,
    'layout': {
      'fontFamily': 'Catholic',
      'menuFontFamily': 'Catholic',
      'navPosition': 'right',
      'sideWidth': 230,
      'barHeight': 102,
      'buttonHeight': 0,
      'buttonWidth': 0,
      'buttonGap': 10,
      'barColor': '#000000',
      'selectedTopicLabelColor': '#f8fafc',
      'buttonColor': '#171717',
      'buttonForegroundColor': '#ffffff',
      'selectedButtonColor': '#facc15',
      'selectedButtonForegroundColor': '#000000',
    },
  };

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('contrast-migration-');
    overrideFile = File(
      '${temporary.path}${Platform.pathSeparator}config'
      '${Platform.pathSeparator}menu.override.json',
    );
    markerFile = File(
      '${temporary.path}${Platform.pathSeparator}state'
      '${Platform.pathSeparator}high-contrast-default-v1.json',
    );
    backupDirectory = Directory(
      '${temporary.path}${Platform.pathSeparator}backups',
    );
  });

  tearDown(() => temporary.delete(recursive: true));

  test('기존 설정의 UI 모양만 고대비 기본값으로 한 번 강제 변경한다', () async {
    final original = <String, dynamic>{
      'schemaVersion': 2,
      'layout': {
        'navPosition': 'left',
        'windowsKioskLockdown': false,
        'sideWidth': 180,
        'barColor': '#123456',
        'selectedButtonColor': '#654321',
      },
    };
    await overrideFile.create(recursive: true);
    await overrideFile.writeAsString(jsonEncode(original));
    final migration = HighContrastDefaultMigration(
      markerPath: markerFile.path,
      overridePath: overrideFile.path,
      backupRoot: backupDirectory.path,
    );

    final migrated = await migration.apply(defaults, original);
    final layout = migrated!['layout'] as Map<String, dynamic>;
    expect(layout['barColor'], '#000000');
    expect(layout['selectedButtonColor'], '#facc15');
    expect(layout['sideWidth'], 230);
    expect(layout['navPosition'], 'left');
    expect(layout['windowsKioskLockdown'], isFalse);
    expect(await markerFile.exists(), isTrue);
    expect(
        await backupDirectory.list().where((entry) => entry is File).length, 1);

    final userChangedAfterMigration = <String, dynamic>{
      ...migrated,
      'layout': {...layout, 'barColor': '#abcdef'},
    };
    final second = await migration.apply(defaults, userChangedAfterMigration);
    expect((second!['layout'] as Map)['barColor'], '#abcdef');
  });

  test('신규 설치는 설정 파일을 만들지 않고 적용 완료만 기록한다', () async {
    final migration = HighContrastDefaultMigration(
      markerPath: markerFile.path,
      overridePath: overrideFile.path,
      backupRoot: backupDirectory.path,
    );

    expect(await migration.apply(defaults, null), isNull);
    expect(await markerFile.exists(), isTrue);
    expect(await overrideFile.exists(), isFalse);
  });
}
