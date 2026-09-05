import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/ui_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late UiThemeService service;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('ui-theme-test-');
    service = UiThemeService(
      userThemeDirectory: '${temporary.path}${Platform.pathSeparator}themes',
      preloadedThemeLoader: () async => [
        {
          'id': 'navy',
          'name': '프리로드 테마',
          'description': '테스트',
          'values': {
            'barColor': '#111827',
            'buttonGap': 8,
            'navPosition': 'right',
            'languageSelection': {
              'backgroundColor': '#030712',
              'buttonWidth': 420,
              'skipSingleTopic': false,
            },
          },
        },
      ],
    );
    await service.ensureReady();
  });

  tearDown(() => temporary.delete(recursive: true));

  test('프리로드 이름은 파일에서 읽고 UI 모양 값만 노출한다', () async {
    final themes = await service.list();
    expect(themes.single.name, '프리로드 테마');
    expect(themes.single.id, 'preloaded:navy');
    expect(themes.single.values['barColor'], '#111827');
    expect(themes.single.values['brightness'], 'light');
    expect(themes.single.values['hideItemIcons'], isFalse);
    expect(themes.single.values['hideTopicIcons'], isFalse);
    expect(themes.single.values.containsKey('navPosition'), isFalse);
    expect(
      themes.single.values['languageSelection'],
      {'backgroundColor': '#030712', 'buttonWidth': 420},
    );
  });

  test('사용자 테마를 별도 파일로 저장하고 삭제한다', () async {
    final saved = await service.saveUserTheme('나의 테마', {
      'brightness': 'dark',
      'hideItemIcons': true,
      'hideTopicIcons': true,
      'barColor': '#222222',
      'buttonGap': 10,
      'windowsKioskLockdown': false,
      'languageSelection': {
        'fontFamily': 'Catholic',
        'selectedButtonColor': '#facc15',
        'buttonHeight': 190,
      },
    });
    expect(saved.preloaded, isFalse);
    expect(saved.values['brightness'], 'dark');
    expect(saved.values['hideItemIcons'], isTrue);
    expect(saved.values['hideTopicIcons'], isTrue);
    expect(saved.values.containsKey('windowsKioskLockdown'), isFalse);
    expect(saved.values['languageSelection'], {
      'fontFamily': 'Catholic',
      'selectedButtonColor': '#facc15',
      'buttonHeight': 190,
    });
    expect(
        (await service.list()).map((theme) => theme.name), contains('나의 테마'));

    await service.deleteUserTheme(saved.id);
    expect((await service.list()).map((theme) => theme.name),
        isNot(contains('나의 테마')));
  });

  test('대소문자만 다른 같은 사용자 이름은 기존 파일을 갱신한다', () async {
    final first = await service.saveUserTheme('My Theme', {
      'barColor': '#111111',
    });
    final second = await service.saveUserTheme('my theme', {
      'barColor': '#222222',
    });

    expect(second.id, first.id);
    final users =
        (await service.list()).where((theme) => !theme.preloaded).toList();
    expect(users, hasLength(1));
    expect(users.single.values['barColor'], '#222222');
  });

  test('패키지의 프리로드 테마 파일을 자동 발견한다', () async {
    final packaged = UiThemeService(
      userThemeDirectory:
          '${temporary.path}${Platform.pathSeparator}packaged-themes',
    );
    final themes = await packaged.list();

    expect(themes.where((theme) => theme.preloaded).length,
        greaterThanOrEqualTo(3));
    expect(themes.every((theme) => theme.name.trim().isNotEmpty), isTrue);
  });

  test('languageSelection 테마 값의 형식을 검증한다', () async {
    expect(
      () => service.saveUserTheme('Invalid language theme', {
        'languageSelection': {'buttonWidth': 0},
      }),
      throwsA(isA<UiThemeException>().having(
        (error) => error.code,
        'code',
        'invalid-theme-language-selection',
      )),
    );
  });

  test('주제 아이콘 숨김 테마 값은 bool만 허용한다', () async {
    await expectLater(
      service.saveUserTheme('Invalid topic icons', {'hideTopicIcons': 'true'}),
      throwsA(isA<UiThemeException>().having(
        (error) => error.code,
        'code',
        'invalid-theme-hide-topic-icons',
      )),
    );
  });

  test('프리로드 테마와 같은 이름으로 저장할 수 없다', () async {
    expect(
      () => service.saveUserTheme('프리로드 테마', {'barColor': '#ffffff'}),
      throwsA(isA<UiThemeException>().having(
        (error) => error.code,
        'code',
        'reserved-theme-name',
      )),
    );
  });

  test('잘못된 ID의 사용자 테마는 건너뛰고 같은 이름을 정상 저장한다', () async {
    final directory = Directory(service.userThemeDirectory!);
    await File('${directory.path}${Platform.pathSeparator}broken.json')
        .writeAsString('''
{"id":"broken","name":"복구 테마","values":{"barColor":"#111111"}}
''');

    expect(
      (await service.list()).where((theme) => theme.name == '복구 테마'),
      isEmpty,
    );
    final saved = await service.saveUserTheme(
      '복구 테마',
      {'barColor': '#222222'},
    );
    expect(saved.id, startsWith('user:'));
    expect(saved.id, hasLength('user:'.length + 64));
  });
}
