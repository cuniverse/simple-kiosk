import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/menu_config_loader.dart';
import 'package:simple_kiosk/service/menu_config_merger.dart';

void main() {
  Map<String, dynamic> clone(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  test('unchanged effective config creates no override fields', () {
    final defaults = {
      'schemaVersion': 2,
      'layout': {
        'barHeight': 100,
        'colors': {'bar': '#000000'},
      },
      'idle': {
        'gallery': {
          'urls': ['https://example.com/gallery'],
        },
      },
    };

    expect(MenuConfigMerger.createOverride(defaults, clone(defaults)), {
      'schemaVersion': 2,
    });
  });

  test('nested values are minimal while changed arrays remain complete', () {
    final defaults = {
      'schemaVersion': 2,
      'layout': {
        'barHeight': 100,
        'colors': {'bar': '#000000', 'button': '#111111'},
      },
      'idle': {
        'gallery': {
          'urls': ['https://example.com/a', 'https://example.com/b'],
          'intervalSec': 8,
        },
      },
    };
    final effective = clone(defaults);
    (effective['layout'] as Map)['barHeight'] = 120;
    ((effective['idle'] as Map)['gallery'] as Map)['urls'] = [
      'https://example.com/b',
    ];

    final override = MenuConfigMerger.createOverride(defaults, effective);

    expect(override, {
      'schemaVersion': 2,
      'layout': {'barHeight': 120},
      'idle': {
        'gallery': {
          'urls': ['https://example.com/b'],
        },
      },
    });
    expect(MenuConfigMerger.merge(defaults, override).json, effective);
  });

  test('saveOverride compacts a full config and removes an empty override',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('menu-override-test-');
    final overrideFile =
        File('${directory.path}${Platform.pathSeparator}menu.override.json');
    final defaults = jsonDecode(
      File('assets/config/menu.defaults.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final loader = MenuConfigLoader(
      overridePath: overrideFile.path,
      defaultsReader: () async => defaults,
    );
    addTearDown(() => directory.delete(recursive: true));

    final effective = clone(defaults);
    (effective['layout'] as Map<String, dynamic>)['barHeight'] = 111;
    await loader.saveOverride(effective);

    final saved = jsonDecode(await overrideFile.readAsString()) as Map;
    expect(saved, {
      'schemaVersion': 2,
      'layout': {'barHeight': 111},
    });
    expect((await loader.readEffective())['layout']['barHeight'], 111);

    await loader.saveOverride(defaults);
    expect(await overrideFile.exists(), isFalse);
    expect(await loader.readOverride(), isEmpty);
  });

  test('partial override input remains supported and new defaults flow through',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('menu-override-partial-test-');
    final overrideFile =
        File('${directory.path}${Platform.pathSeparator}menu.override.json');
    var defaults = jsonDecode(
      File('assets/config/menu.defaults.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final loader = MenuConfigLoader(
      overridePath: overrideFile.path,
      defaultsReader: () async => defaults,
    );
    addTearDown(() => directory.delete(recursive: true));

    await loader.saveOverride({
      'schemaVersion': 2,
      'layout': {'barHeight': 123},
    });
    defaults = clone(defaults);
    (defaults['layout'] as Map<String, dynamic>)['toolbarAutoHideSec'] = 17;

    final effective = await loader.readEffective();
    expect(effective['layout']['barHeight'], 123);
    expect(effective['layout']['toolbarAutoHideSec'], 17);
  });
}
