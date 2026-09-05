import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/menu_config_loader.dart';
import 'package:simple_kiosk/service/ui_theme_service.dart';

void main() {
  late Directory directory;
  late MenuConfigLoader loader;
  late Map<String, dynamic> defaults;
  late Map<String, dynamic> values;
  var available = true;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('theme-update-');
    defaults = {
      'schemaVersion': 2,
      'uiTheme': 'preloaded:active',
      'layout': {'buttonColor': '#111111', 'navPosition': 'right'},
      'languageSelection': {'title': 'Choose', 'buttonColor': '#111111'},
      'languages': [
        {
          'id': 'en',
          'label': 'English',
          'topics': [
            {
              'id': 'general',
              'label': 'General',
              'items': [
                {'id': 'home', 'title': 'Home', 'url': 'https://example.com'},
              ],
            },
          ],
        },
      ],
    };
    values = {
      'buttonColor': '#222222',
      'hideItemIcons': true,
      'languageSelection': {'buttonColor': '#222222'},
    };
    available = true;
    loader = MenuConfigLoader(
      overridePath: '${directory.path}/menu.override.json',
      defaultsReader: () async => defaults,
      themeService: UiThemeService(
        userThemeDirectory: '${directory.path}/themes',
        preloadedThemeLoader: () async => [
          if (available) {'id': 'active', 'name': 'Active', 'values': values},
          {
            'id': 'other',
            'name': 'Other',
            'values': {'buttonColor': '#abcdef'},
          },
        ],
      ),
    );
  });

  tearDown(() => directory.delete(recursive: true));

  test('default theme changes flow through without an override', () async {
    expect((await loader.readEffective())['layout']['buttonColor'], '#222222');
    values['buttonColor'] = '#333333';
    values['hideTopicIcons'] = true;
    values['languageSelection'] = {
      'buttonColor': '#444444',
      'buttonWidth': 450
    };
    final updated = await loader.readEffective();
    expect(updated['layout']['buttonColor'], '#333333');
    expect(updated['layout']['hideTopicIcons'], isTrue);
    expect(updated['languageSelection']['buttonColor'], '#444444');
    expect(updated['languageSelection']['buttonWidth'], 450);
    expect(updated['languageSelection']['title'], 'Choose');
  });

  test('theme identity survives new defaults and custom edits survive updates',
      () async {
    final config = await loader.readEffective();
    config['layout']['buttonColor'] = '#111111'; // raw default, explicit edit
    config['layout']['navPosition'] = 'left';
    config['languageSelection']['buttonWidth'] = 500;
    await loader.saveOverride(config);
    final stored = await loader.readOverride();
    expect(stored['uiTheme'], 'preloaded:active');
    expect(stored['layout'], {'buttonColor': '#111111', 'navPosition': 'left'});
    expect(stored['languageSelection'], {'buttonWidth': 500});
    expect(stored['uiThemeFallback']['buttonColor'], '#222222');

    defaults['uiTheme'] = 'preloaded:other';
    values['buttonColor'] = '#333333';
    values['hideTopicIcons'] = true;
    values['languageSelection'] = {
      'buttonColor': '#444444',
      'buttonWidth': 450
    };
    final updated = await loader.readEffective();
    expect(updated['uiTheme'], 'preloaded:active');
    expect(updated['layout']['buttonColor'], '#111111');
    expect(updated['layout']['navPosition'], 'left');
    expect(updated['layout']['hideTopicIcons'], isTrue);
    expect(updated['languageSelection']['buttonColor'], '#444444');
    expect(updated['languageSelection']['buttonWidth'], 500);
    await loader.saveOverride(updated);
    expect((await loader.readOverride())['layout'], stored['layout']);
  });

  test('theme values are not pinned when saving a full effective config',
      () async {
    await loader.saveOverride(await loader.readEffective());
    final stored = await loader.readOverride();
    expect(stored.containsKey('layout'), isFalse);
    expect(stored.containsKey('languageSelection'), isFalse);
    values['buttonColor'] = '#555555';
    expect((await loader.readEffective())['layout']['buttonColor'], '#555555');
  });

  test('a removed theme field returns to the underlying default', () async {
    await loader.saveOverride(await loader.readEffective());
    values.remove('buttonColor');
    expect((await loader.readEffective())['layout']['buttonColor'], '#111111');
  });

  test('restoring an older full config rebases inherited values', () async {
    final oldConfig = await loader.readEffective();
    oldConfig['layout']['navPosition'] = 'left';
    oldConfig['languageSelection']['buttonWidth'] = 600;
    values['buttonColor'] = '#abcdef';
    values['languageSelection'] = {'buttonColor': '#fedcba'};
    await loader.saveOverride(oldConfig);
    final result = await loader.readEffective();
    expect(result['layout']['buttonColor'], '#abcdef');
    expect(result['languageSelection']['buttonColor'], '#fedcba');
    expect(result['layout']['navPosition'], 'left');
    expect(result['languageSelection']['buttonWidth'], 600);
    expect(oldConfig['layout']['buttonColor'], '#222222');
  });

  test('a missing theme uses its saved appearance and preserves custom edits',
      () async {
    final config = await loader.readEffective();
    config['layout']['buttonColor'] = '#888888';
    await loader.saveOverride(config);
    available = false;
    final result = await loader.readEffective();
    expect(result['layout']['buttonColor'], '#888888');
    expect(result['languageSelection']['buttonColor'], '#222222');
    expect(result['uiTheme'], 'preloaded:active');
  });

  test('detaching a theme freezes the current appearance', () async {
    final config = await loader.readEffective();
    config['uiTheme'] = '';
    await loader.saveOverride(config);
    values['buttonColor'] = '#ffffff';
    final result = await loader.readEffective();
    expect(result['layout']['buttonColor'], '#222222');
    expect(result.containsKey('uiThemeFallback'), isFalse);
  });

  test('unlinked legacy overrides retain their explicit appearance', () async {
    await File('${directory.path}/menu.override.json')
        .writeAsString(jsonEncode({
      'schemaVersion': 2,
      'layout': {'buttonColor': '#777777'},
    }));
    expect((await loader.readEffective())['layout']['buttonColor'], '#777777');
  });
}
