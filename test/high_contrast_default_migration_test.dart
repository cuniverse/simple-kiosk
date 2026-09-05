import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/high_contrast_default_migration.dart';
import 'package:simple_kiosk/service/menu_config_loader.dart';
import 'package:simple_kiosk/service/ui_theme_service.dart';

void main() {
  late Directory temporary;
  late File overrideFile;
  late File markerFile;
  late Directory backupDirectory;
  late UiThemeService themeService;
  late Map<String, dynamic> theme;

  const defaults = <String, dynamic>{
    'schemaVersion': 2,
    'items': [
      {'id': 'home', 'title': 'Home', 'url': 'https://example.com'},
    ],
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
      '${Platform.pathSeparator}${HighContrastDefaultMigration.migrationId}.json',
    );
    backupDirectory = Directory(
      '${temporary.path}${Platform.pathSeparator}backups',
    );
    theme = jsonDecode(
      File('assets/themes/high-contrast-text.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    themeService = UiThemeService(
      userThemeDirectory: '${temporary.path}/themes',
      preloadedThemeLoader: () async => [theme],
    );
  });

  tearDown(() => temporary.delete(recursive: true));

  test('기존 설정의 UI 모양만 고대비 기본값으로 한 번 강제 변경한다', () async {
    final original = <String, dynamic>{
      'schemaVersion': 2,
      'uiTheme': 'preloaded:calm-navy',
      'uiThemeFallback': {'buttonColor': '#123456'},
      'layout': {
        'navPosition': 'left',
        'windowsKioskLockdown': false,
        'sideWidth': 180,
        'barColor': '#123456',
        'selectedButtonColor': '#654321',
      },
      'languageSelection': {
        'buttonColor': '#abcdef',
        'backgroundColor': '#ffffff',
        'title': '언어 선택 안내',
        'skipSingleTopic': false,
      },
      'idle': {'timeoutSec': 60},
    };
    await overrideFile.create(recursive: true);
    await overrideFile.writeAsString(jsonEncode(original));
    final migration = HighContrastDefaultMigration(
      markerPath: markerFile.path,
      overridePath: overrideFile.path,
      backupRoot: backupDirectory.path,
      themeService: themeService,
    );

    final oldMarker =
        File('${markerFile.parent.path}/high-contrast-default-v1.json');
    await oldMarker.create(recursive: true);
    await oldMarker.writeAsString('{"migration":"high-contrast-default-v1"}');

    final migrated = await migration.apply(defaults, original);
    final layout = migrated!['layout'] as Map<String, dynamic>;
    expect(migrated['uiTheme'], 'preloaded:high-contrast-text');
    expect(layout.containsKey('barColor'), isFalse);
    expect(layout.containsKey('selectedButtonColor'), isFalse);
    expect(layout.containsKey('sideWidth'), isFalse);
    expect(layout['navPosition'], 'left');
    expect(layout['windowsKioskLockdown'], isFalse);
    expect(migrated['languageSelection'], {
      'title': '언어 선택 안내',
      'skipSingleTopic': false,
    });
    expect(migrated['idle'], original['idle']);
    final loader = MenuConfigLoader(
      defaultsReader: () async => defaults,
      overridePath: overrideFile.path,
      themeService: themeService,
    );
    final effective = await loader.readEffective();
    for (final key in UiThemeService.appearanceKeys) {
      if ((theme['values'] as Map).containsKey(key)) {
        expect(effective['layout'][key], theme['values'][key], reason: key);
      }
    }
    for (final key in UiThemeService.languageSelectionAppearanceKeys) {
      expect(effective['languageSelection'][key],
          theme['values']['languageSelection'][key],
          reason: key);
    }
    expect(await markerFile.exists(), isTrue);
    expect(
        await backupDirectory.list().where((entry) => entry is File).length, 1);
    final backup =
        await backupDirectory.list().where((entry) => entry is File).single;
    expect(jsonDecode(await File(backup.path).readAsString()), original);

    theme['values']['buttonColor'] = '#333333';
    expect((await loader.readEffective())['layout']['buttonColor'], '#333333');

    final userChangedAfterMigration = <String, dynamic>{
      ...migrated,
      'uiTheme': 'preloaded:calm-navy',
      'layout': {...layout, 'barColor': '#abcdef'},
    };
    final second = await migration.apply(defaults, userChangedAfterMigration);
    expect((second!['layout'] as Map)['barColor'], '#abcdef');
    expect(second['uiTheme'], 'preloaded:calm-navy');
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

  test('검증 실패 시 기존 설정과 마이그레이션 완료 상태를 변경하지 않는다', () async {
    final original = {
      'layout': {'barColor': '#123456'}
    };
    await overrideFile.create(recursive: true);
    await overrideFile.writeAsString(jsonEncode(original));
    final migration = HighContrastDefaultMigration(
      markerPath: markerFile.path,
      overridePath: overrideFile.path,
      backupRoot: backupDirectory.path,
      themeService: themeService,
    );
    await expectLater(
      migration.apply(defaults, original, validate: (_) async {
        throw const FormatException('invalid');
      }),
      throwsFormatException,
    );
    expect(jsonDecode(await overrideFile.readAsString()), original);
    expect(await markerFile.exists(), isFalse);
  });
}
