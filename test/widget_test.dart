import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simple_kiosk/model/idle_config.dart';
import 'package:simple_kiosk/model/layout_config.dart';
import 'package:simple_kiosk/model/menu_language.dart';
import 'package:simple_kiosk/model/menu_item.dart';
import 'package:simple_kiosk/model/menu_topic.dart';
import 'package:simple_kiosk/model/update_manifest.dart';
import 'package:simple_kiosk/model/update_policy.dart';
import 'package:simple_kiosk/model/webview_slot_id.dart';
import 'package:simple_kiosk/model/webview_data_policy.dart';
import 'package:simple_kiosk/service/gallery_feed_loader.dart';
import 'package:simple_kiosk/service/admin_api_controller.dart';
import 'package:simple_kiosk/service/admin_pin_store.dart';
import 'package:simple_kiosk/widget/admin_pin_keypad.dart';
import 'package:simple_kiosk/service/menu_config_merger.dart';
import 'package:simple_kiosk/service/menu_config_loader.dart';
import 'package:simple_kiosk/service/menu_config_migrator.dart';
import 'package:simple_kiosk/service/keyboard_controller.dart';
import 'package:simple_kiosk/service/system_keyboard.dart';
import 'package:simple_kiosk/service/update_service.dart';
import 'package:simple_kiosk/service/update_controller.dart';
import 'package:simple_kiosk/service/windows_startup_service.dart';
import 'package:simple_kiosk/widget/idle_gate.dart';
import 'package:simple_kiosk/widget/idle_overlay.dart';
import 'package:simple_kiosk/widget/kiosk_shortcuts.dart';
import 'package:simple_kiosk/widget/kiosk_webview.dart';
import 'package:simple_kiosk/widget/language_selection.dart';
import 'package:simple_kiosk/widget/navigation_menu.dart';
import 'package:simple_kiosk/widget/webview_loading_overlay.dart';
import 'package:simple_kiosk/widget/update_admin_dialog.dart';

class _RunningAdminApiController extends AdminApiController {
  _RunningAdminApiController({required this.port})
      : super(
          statusProvider: () async => const {},
          actionHandler: (_) async => const {},
          configReader: () async => const {'schemaVersion': 2},
          configWriter: (_) async {},
        );

  final int port;

  @override
  bool get running => true;

  @override
  int? get actualPort => port;
}

void main() {
  test('WebView 슬롯은 언어·주제·메뉴 ID로 순서와 무관하게 식별된다', () {
    const koreanHome = WebViewSlotId(
      languageId: 'ko',
      topicId: 'parish',
      menuId: 'home',
    );
    const sameAfterReorder = WebViewSlotId(
      languageId: 'ko',
      topicId: 'parish',
      menuId: 'home',
    );
    const anotherTopicHome = WebViewSlotId(
      languageId: 'ko',
      topicId: 'pilgrimage',
      menuId: 'home',
    );
    const englishHome = WebViewSlotId(
      languageId: 'en',
      topicId: 'parish',
      menuId: 'home',
    );
    final controllers = <WebViewSlotId, String>{koreanHome: 'controller'};

    expect(controllers[sameAfterReorder], 'controller');
    expect(englishHome, isNot(koreanHome));
    expect(anotherTopicHome, isNot(koreanHome));
    expect(controllers[englishHome], isNull);
  });

  test('WebView 세대가 바뀌면 이전 세대 콜백은 무효가 된다', () {
    final generation = WebViewGeneration();
    final first = generation.value;

    expect(generation.isCurrent(first), isTrue);

    final second = generation.next();
    expect(generation.isCurrent(first), isFalse);
    expect(generation.isCurrent(second), isTrue);
  });

  test('웹 관리자에 전체·섹션·필드·메뉴 기본값 복원 기능이 포함된다', () {
    final page = File('assets/admin/index.html').readAsStringSync();

    expect(page, contains('사이니지 구성'));
    expect(page, isNot(contains('외부 메뉴 설정')));
    expect(page, contains('/api/config/defaults'));
    expect(page, contains('전체 기본값 복원'));
    expect(page, contains('이 섹션 기본값 복원'));
    expect(page, contains('이 값 복원'));
    expect(page, contains('이 메뉴 복원'));
    expect(page, contains("function visibilityField(target,onRestore)"));
    expect(page, contains("['false','표시'],['true','숨김']"));
    expect(page, contains('주제 선택 후 첫 메뉴'));
    expect(page, contains('주제 추가'));
    expect(page, contains("webViewData.idlePolicy"));
    expect(page, contains('Local Storage'));
    expect(page, contains('id="reauthOverlay"'));
    expect(page, contains('현재 화면과 저장하지 않은 설정은 그대로 유지됩니다.'));
    expect(page, contains('function requireReauthentication'));
    expect(page, contains('await requireReauthentication()'));
    expect(page,
        contains('sessionStorage.getItem(\'simpleKioskAdminExpiresAt\')'));
    expect(page, isNot(contains('logout(false)')));
    expect(page, contains('/api/session/refresh'));
    expect(
        page, contains("['pointerdown','keydown','input','change','wheel']"));
  });

  testWidgets('관리자 PIN 키패드로 숫자 입력과 삭제를 수행한다', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminPinKeypad(controller: controller)),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('0'));
    expect(controller.text, '120');

    await tester.tap(find.byTooltip('한 자리 삭제'));
    expect(controller.text, '12');

    await tester.tap(find.text('전체 삭제'));
    expect(controller.text, isEmpty);
  });

  testWidgets('관리 API가 실행 중이면 PIN 창에 웹 관리자 링크를 표시한다', (
    tester,
  ) async {
    final adminController = _RunningAdminApiController(port: 8181);
    final updateController = UpdateController();
    addTearDown(() {
      updateController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              UpdateAdminDialog.show(
                context,
                updateController,
                adminApiController: adminController,
              );
            },
            child: const Text('설정 열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('설정 열기'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('open-web-admin')), findsOneWidget);
    expect(find.text('웹 관리자 열기'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('관리 API가 비활성화되면 PIN 창에 웹 관리자 링크를 숨긴다', (
    tester,
  ) async {
    final updateController = UpdateController();
    addTearDown(updateController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              UpdateAdminDialog.show(context, updateController);
            },
            child: const Text('설정 열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('설정 열기'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('open-web-admin')), findsNothing);

    await tester.tap(find.text('취소'));
    await tester.pump(const Duration(milliseconds: 300));
  });

  test('관리자 PIN은 기본값, 변경 파일, 파일 삭제 순서로 동작한다', () async {
    final directory = await Directory.systemTemp.createTemp('admin-pin-test-');
    final file =
        File('${directory.path}${Platform.pathSeparator}admin-pin.json');
    final store = AdminPinStore(
      file: file,
      random: Random(1),
      iterations: 20,
    );
    addTearDown(() => directory.delete(recursive: true));

    expect(await store.verify('1259'), isTrue);
    expect(await store.verify('0000'), isFalse);

    await store.changePin('9876');
    expect(await store.hasCustomPin, isTrue);
    expect(await store.verify('1259'), isFalse);
    expect(await store.verify('9876'), isTrue);
    expect(await file.readAsString(), isNot(contains('9876')));

    await file.delete();
    expect(await store.verify('1259'), isTrue);
    expect(await store.verify('9876'), isFalse);
  });

  test('menu override preserves edits and receives new default items', () {
    final merged = MenuConfigMerger.merge(
      {
        'schemaVersion': 1,
        'layout': {'toolbarAutoHideSec': 10, 'newOption': true},
        'items': [
          {'id': 'home', 'title': 'Home', 'url': 'https://default.example'},
          {'id': 'new', 'title': 'New', 'url': 'https://new.example'},
        ],
      },
      {
        'schemaVersion': 1,
        'layout': {'toolbarAutoHideSec': 20},
        'items': {
          'overrides': {
            'home': {'url': 'https://custom.example'},
          },
          'additions': [
            {'id': 'custom', 'title': 'Custom', 'url': 'https://added.example'},
          ],
          'disabledIds': <String>[],
          'order': ['home', 'custom'],
        },
      },
    ).json;

    expect(merged['layout'], {
      'toolbarAutoHideSec': 20,
      'newOption': true,
    });
    final items = merged['items'] as List;
    expect(items.map((item) => item['id']), ['home', 'custom', 'new']);
    expect(items.first['url'], 'https://custom.example');
  });

  test('구형 items 패치 설정을 시작 마이그레이션용 현재 구조로 변환한다', () {
    final defaults = {
      'schemaVersion': 2,
      'languages': [
        {
          'id': 'ko',
          'label': '한국어',
          'topics': [
            {
              'id': 'general',
              'label': '전체',
              'items': [
                {'id': 'home', 'title': '홈', 'url': 'https://default'},
              ],
            },
          ],
        },
      ],
    };
    final legacy = {
      'schemaVersion': 1,
      'items': {
        'overrides': {
          'home': {'url': 'https://custom'},
        },
        'additions': [
          {'id': 'new', 'title': '추가', 'url': 'https://new'},
        ],
      },
    };

    expect(MenuConfigMigrator.needsMigration(defaults, legacy), isTrue);
    final migrated = MenuConfigMigrator.migrate(defaults, legacy);
    final language = (migrated['languages'] as List).single as Map;
    final topic = (language['topics'] as List).single as Map;
    final items = topic['items'] as List;

    expect(migrated['schemaVersion'], 2);
    expect(migrated, isNot(contains('items')));
    expect(language['defaultTopic'], 'default');
    expect(items.map((item) => item['id']), ['home', 'new']);
    expect((items.first as Map)['url'], 'https://custom');
    expect(() => MenuConfigLoader.parse(migrated), returnsNormally);
  });

  test('합성된 단일 default 주제를 새 기본 주제들과 병합한다', () {
    final defaults = {
      'schemaVersion': 2,
      'defaultLanguage': 'ko',
      'languages': [
        {
          'id': 'ko',
          'label': '한국어',
          'defaultTopic': 'wyd',
          'topics': [
            {
              'id': 'wyd',
              'label': 'WYD',
              'items': [
                {'id': 'home', 'title': 'WYD', 'url': 'https://default'},
                {'id': 'aos', 'title': '교구', 'url': 'https://aos'},
              ],
            },
            {
              'id': 'parish',
              'label': '본당',
              'items': [
                {'id': 'parish', 'title': '본당', 'url': 'https://parish'},
                {'id': 'aos', 'title': '교구', 'url': 'https://aos'},
              ],
            },
          ],
        },
      ],
    };
    final legacy = {
      'schemaVersion': 2,
      'layout': {'toolbarAutoHideSec': 25},
      'languages': [
        {
          'id': 'ko',
          'label': '한국어 사용자 설정',
          'defaultTopic': 'default',
          'topics': [
            {
              'id': 'default',
              'label': '기본 주제',
              'defaultMenu': 'home',
              'items': [
                {'id': 'home', 'title': '사용자 홈', 'url': 'https://custom'},
                {'id': 'aos', 'title': '사용자 교구', 'url': 'https://aos'},
                {
                  'id': 'parish',
                  'title': '사용자 본당',
                  'url': 'https://parish',
                },
              ],
            },
          ],
        },
      ],
    };

    expect(MenuConfigMigrator.needsMigration(defaults, legacy), isTrue);
    final migrated = MenuConfigMigrator.migrate(defaults, legacy);
    final language = (migrated['languages'] as List).single as Map;
    final topics = language['topics'] as List;
    final wyd = topics.first as Map;
    final parish = topics.last as Map;

    expect(topics.map((topic) => topic['id']), ['wyd', 'parish']);
    expect(language['defaultTopic'], 'wyd');
    expect(language['label'], '한국어 사용자 설정');
    expect(((wyd['items'] as List).first as Map)['url'], 'https://custom');
    expect(((parish['items'] as List).first as Map)['title'], '사용자 본당');
    expect((migrated['layout'] as Map)['toolbarAutoHideSec'], 25);
    expect(() => MenuConfigLoader.parse(migrated), returnsNormally);
    expect(MenuConfigMigrator.needsMigration(defaults, migrated), isFalse);
  });

  test('언어별 메뉴 설정을 파싱하고 기본 언어를 선택한다', () {
    final config = MenuConfigLoader.parse({
      'defaultLanguage': 'en',
      'languages': [
        {
          'id': 'ko',
          'label': '한국어',
          'icon': '🇰🇷',
          'items': [
            {'id': 'home', 'title': '홈', 'url': 'https://ko.example'},
          ],
        },
        {
          'id': 'en',
          'label': 'English',
          'defaultMenu': 'news',
          'items': [
            {'id': 'home', 'title': 'Home', 'url': 'https://en.example'},
            {'id': 'news', 'title': 'News', 'url': 'https://news.example'},
          ],
        },
      ],
    });

    expect(config.languages.map((language) => language.id), ['ko', 'en']);
    expect(config.language('ko').icon, '🇰🇷');
    expect(config.defaultLanguageId, 'en');
    expect(config.items.map((item) => item.title), ['Home', 'News']);
    expect(config.language('en').defaultItem.id, 'news');
    expect(config.language('ko').defaultItem.id, 'home');
  });

  test('등록되지 않은 defaultMenu는 설정 오류로 거부한다', () {
    expect(
      () => MenuConfigLoader.parse({
        'languages': [
          {
            'id': 'ko',
            'label': '한국어',
            'defaultMenu': 'missing',
            'items': [
              {'id': 'home', 'title': '홈', 'url': 'https://example.com'},
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('언어별 주제와 주제별 메뉴를 파싱한다', () {
    final config = MenuConfigLoader.parse({
      'languageSelection': {'skipSingleTopic': false},
      'languages': [
        {
          'id': 'ko',
          'label': '한국어',
          'defaultTopic': 'pilgrimage',
          'topics': [
            {
              'id': 'parish',
              'label': '본당',
              'items': [
                {'id': 'home', 'title': '홈', 'url': 'https://parish.example'},
              ],
            },
            {
              'id': 'pilgrimage',
              'label': '순례',
              'defaultMenu': 'map',
              'items': [
                {'id': 'map', 'title': '지도', 'url': 'https://map.example'},
              ],
            },
          ],
        },
      ],
    });

    final language = config.language('ko');
    expect(language.effectiveTopics.map((topic) => topic.id), [
      'parish',
      'pilgrimage',
    ]);
    expect(language.defaultTopic.id, 'pilgrimage');
    expect(language.defaultItem.id, 'map');
    expect(config.skipSingleTopic, isFalse);
  });

  test('숨긴 언어·주제·메뉴를 제외하고 숨긴 기본값은 표시 항목으로 대체한다', () {
    final config = MenuConfigLoader.parse({
      'defaultLanguage': 'ko',
      'languages': [
        {
          'id': 'ko',
          'label': '한국어',
          'hidden': true,
          'items': [
            {'id': 'home', 'title': '홈', 'url': 'https://ko.example'},
          ],
        },
        {
          'id': 'en',
          'label': 'English',
          'defaultTopic': 'hidden-topic',
          'topics': [
            {
              'id': 'hidden-topic',
              'label': 'Hidden',
              'hidden': true,
              'items': [
                {
                  'id': 'hidden-home',
                  'title': 'Hidden home',
                  'url': 'https://hidden.example',
                },
              ],
            },
            {
              'id': 'visible-topic',
              'label': 'Visible',
              'defaultMenu': 'hidden-menu',
              'items': [
                {
                  'id': 'hidden-menu',
                  'title': 'Hidden menu',
                  'url': 'https://hidden-menu.example',
                  'hidden': true,
                },
                {
                  'id': 'visible-menu',
                  'title': 'Visible menu',
                  'url': 'https://visible.example',
                },
              ],
            },
          ],
        },
      ],
    });

    expect(config.languages.map((language) => language.id), ['en']);
    expect(config.defaultLanguageId, 'en');
    expect(config.language(config.defaultLanguageId).defaultTopic.id,
        'visible-topic');
    expect(config.language(config.defaultLanguageId).defaultItem.id,
        'visible-menu');
  });

  test('모든 언어 또는 한 주제의 모든 메뉴를 숨긴 설정은 거부한다', () {
    expect(
      () => MenuConfigLoader.parse({
        'languages': [
          {
            'id': 'ko',
            'label': '한국어',
            'hidden': true,
            'items': [
              {'id': 'home', 'title': '홈', 'url': 'https://example.com'},
            ],
          },
        ],
      }),
      throwsFormatException,
    );

    expect(
      () => MenuConfigLoader.parse({
        'languages': [
          {
            'id': 'ko',
            'label': '한국어',
            'topics': [
              {
                'id': 'default',
                'label': '기본',
                'items': [
                  {
                    'id': 'home',
                    'title': '홈',
                    'url': 'https://example.com',
                    'hidden': true,
                  },
                ],
              },
            ],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('숨긴 언어에서는 모든 하위 주제와 메뉴를 함께 숨길 수 있다', () {
    final config = MenuConfigLoader.parse({
      'languages': [
        {
          'id': 'hidden',
          'label': '숨긴 언어',
          'hidden': true,
          'topics': [
            {
              'id': 'hidden-topic',
              'label': '숨긴 주제',
              'hidden': true,
              'items': [
                {
                  'id': 'hidden-menu',
                  'title': '숨긴 메뉴',
                  'url': 'https://hidden.example',
                  'hidden': true,
                },
              ],
            },
          ],
        },
        {
          'id': 'visible',
          'label': '표시 언어',
          'items': [
            {'id': 'home', 'title': '홈', 'url': 'https://example.com'},
          ],
        },
      ],
    });

    expect(config.languages.map((language) => language.id), ['visible']);
  });

  test('WebView 데이터 정책과 로그인 유지 하위 도메인을 파싱한다', () {
    final config = MenuConfigLoader.parse({
      'webViewData': {
        'idlePolicy': 'allSiteData',
        'preserveDomains': ['https://Catholic.or.kr/path'],
      },
      'items': [
        {'id': 'home', 'title': '홈', 'url': 'https://example.com'},
      ],
    });

    expect(
      config.webViewDataPolicy.idlePolicy,
      IdleWebDataPolicy.allSiteData,
    );
    expect(config.webViewDataPolicy.preserves('www.catholic.or.kr'), isTrue);
    expect(config.webViewDataPolicy.preserves('notcatholic.or.kr'), isFalse);
  });

  test('기본 메뉴 설정은 한국어와 English 메뉴를 제공한다', () {
    final decoded = jsonDecode(
      File('assets/config/menu.defaults.json').readAsStringSync(),
    );
    final config = MenuConfigLoader.parse(decoded);

    expect(config.defaultLanguageId, 'ko');
    expect(
      config.languages.map((language) => language.id),
      containsAll(['ko', 'en']),
    );
    expect(config.languages.length, greaterThanOrEqualTo(2));
    expect(config.language('ko').icon, 'assets/icons/languages/kr.png');
    expect(
      config.language('en').icon,
      'assets/icons/languages/en-us-gb.png',
    );
    expect(config.language('ko').items.first.title, 'WYD 서울 2027');
    expect(
      config.language('en').items.firstWhere((item) => item.id == 'aos').title,
      'Archdiocese of Seoul',
    );
  });

  test('기존 items 오버라이드는 다국어 기본값에서도 단일 메뉴로 유지된다', () {
    final merged = MenuConfigMerger.merge(
      {
        'schemaVersion': 2,
        'languages': [
          {
            'id': 'ko',
            'label': '한국어',
            'items': [
              {'id': 'home', 'title': '홈', 'url': 'https://default.example'},
            ],
          },
        ],
      },
      {
        'schemaVersion': 1,
        'items': {
          'overrides': {
            'home': {'url': 'https://custom.example'},
          },
        },
      },
    ).json;

    expect(merged, isNot(contains('languages')));
    final config = MenuConfigLoader.parse(merged);
    expect(config.languages.single.id, 'default');
    expect(config.items.single.url, 'https://custom.example');
  });

  testWidgets('언어 선택 화면은 큰 버튼으로 언어를 표시한다', (tester) async {
    var selectedLanguage = -1;
    var selectedTopic = -1;
    var returnCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LanguageSelection(
          title: '언어를 선택하세요',
          subtitle: 'Please select your language',
          languages: const [
            MenuLanguage(
              id: 'ko',
              label: '한국어',
              icon: 'assets/icons/languages/kr.png',
              items: [
                MenuItem(id: 'home', title: '홈', url: 'https://example.com'),
              ],
            ),
          ],
          onSelected: (language, topic) {
            selectedLanguage = language;
            selectedTopic = topic;
          },
          onReturnToIdle: () => returnCount += 1,
        ),
      ),
    );

    final button = find.byKey(const ValueKey('language-ko'));
    expect(button, findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.getSize(button), const Size(360, 176));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('selected-language-ko')), findsOneWidget);
    expect(selectedLanguage, -1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(selectedLanguage, 0);
    expect(selectedTopic, 0);

    await tester.tap(find.byKey(const ValueKey('return-to-idle')));
    expect(returnCount, 1);
  });

  testWidgets('언어를 선택하면 버튼이 상단으로 이동하고 주제 버튼을 표시한다', (tester) async {
    var selectedLanguage = -1;
    var selectedTopic = -1;
    const parishItems = [
      MenuItem(id: 'home', title: '홈', url: 'https://parish.example'),
    ];
    const pilgrimageItems = [
      MenuItem(id: 'map', title: '지도', url: 'https://map.example'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: LanguageSelection(
          title: '언어를 선택하세요',
          subtitle: '',
          skipSingleTopic: false,
          languages: const [
            MenuLanguage(
              id: 'ko',
              label: '한국어',
              items: parishItems,
              topics: [
                MenuTopic(id: 'parish', label: '본당', items: parishItems),
                MenuTopic(
                  id: 'pilgrimage',
                  label: '순례',
                  items: pilgrimageItems,
                ),
              ],
            ),
          ],
          onSelected: (language, topic) {
            selectedLanguage = language;
            selectedTopic = topic;
          },
          onReturnToIdle: () {},
        ),
      ),
    );

    final languageButton = find.byKey(const ValueKey('language-ko'));
    final initialTop = tester.getTopLeft(languageButton).dy;
    await tester.tap(languageButton);
    await tester.pumpAndSettle();
    final selectedLanguageButton =
        find.byKey(const ValueKey('selected-language-ko'));
    expect(selectedLanguageButton, findsOneWidget);
    expect(tester.getTopLeft(selectedLanguageButton).dy, lessThan(initialTop));
    expect(find.byKey(const ValueKey('topic-parish')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-pilgrimage')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('return-to-idle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('language-step')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-parish')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('language-ko')));
    await tester.pumpAndSettle();

    final pilgrimage = find.byKey(const ValueKey('topic-pilgrimage'));
    await tester.ensureVisible(pilgrimage);
    await tester.tap(pilgrimage);
    expect(selectedLanguage, 0);
    expect(selectedTopic, 1);
  });

  testWidgets('언어 선택 화면에서 입력이 없으면 화면 보호기로 돌아간다', (tester) async {
    const idle = IdleConfig(
      enabled: true,
      timeoutSec: 1,
      startOnLaunch: false,
      modes: [IdleMode.image],
      image: 'assets/icons/app_icon.png',
    );
    final controller = IdleGateController();

    await tester.pumpWidget(
      MaterialApp(
        home: IdleGate(
          config: idle,
          controller: controller,
          child: LanguageSelection(
            title: '언어를 선택하세요',
            subtitle: '',
            languages: const [
              MenuLanguage(
                id: 'ko',
                label: '한국어',
                items: [
                  MenuItem(
                    id: 'home',
                    title: '홈',
                    url: 'https://example.com',
                  ),
                ],
              ),
            ],
            onSelected: (_, __) {},
            onReturnToIdle: controller.enterIdle,
          ),
        ),
      ),
    );

    expect(find.byType(LanguageSelection), findsOneWidget);
    expect(find.byType(IdleOverlay), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IdleOverlay), findsOneWidget);
  });

  testWidgets('슬라이드쇼는 방향키와 스와이프로 이전·다음 항목을 이동한다', (tester) async {
    const first = 'assets/icons/languages/kr.png';
    const second = 'assets/icons/languages/en-us-gb.png';
    const config = IdleConfig(
      enabled: true,
      modes: [IdleMode.slideshow],
      slideshow: SlideshowConfig(
        intervalSec: 60,
        transition: SlideshowTransition.none,
        images: [first, second],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IdleOverlay(config: config, onDismiss: () {}),
      ),
    );
    expect(find.byKey(const ValueKey(first)), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.byKey(const ValueKey(second)), findsOneWidget);

    await tester.dragFrom(const Offset(500, 300), const Offset(160, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey(first)), findsOneWidget);
  });

  testWidgets('WebView 로딩 오버레이는 메뉴와 시간 초과 작업을 표시한다', (tester) async {
    var cancelCount = 0;
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebViewLoadingOverlay(
            title: '굿뉴스',
            timedOut: true,
            onCancel: () => cancelCount += 1,
            onRetry: () => retryCount += 1,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('굿뉴스'), findsOneWidget);
    expect(find.text('페이지 응답이 늦어지고 있습니다.'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.tap(find.text('다시 시도'));
    expect(cancelCount, 1);
    expect(retryCount, 1);
  });

  test('WebView는 페이지가 표시 가능한 커밋 시점에 초기 화면을 전환한다', () {
    final source = File('lib/widget/kiosk_webview.dart').readAsStringSync();
    expect(source, contains('onPageCommitVisible:'));
    expect(source, contains('_reportInitialLoadReady();'));
  });

  testWidgets('웹 확대 컨트롤은 배율과 조절 버튼을 표시하고 더블클릭으로 초기화한다', (tester) async {
    var zoomInCount = 0;
    var zoomOutCount = 0;
    var resetCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebZoomControls(
            scale: 1.25,
            canZoomOut: true,
            canZoomIn: true,
            onZoomOut: () => zoomOutCount += 1,
            onZoomIn: () => zoomInCount += 1,
            onReset: () => resetCount += 1,
          ),
        ),
      ),
    );

    expect(find.text('125%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('web-zoom-out')));
    await tester.tap(find.byKey(const ValueKey('web-zoom-in')));
    await tester.tap(find.byKey(const ValueKey('web-zoom-reset')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('web-zoom-reset')));
    await tester.pumpAndSettle();

    expect(zoomOutCount, 1);
    expect(zoomInCount, 1);
    expect(resetCount, 1);
  });

  testWidgets('툴바 제목은 최대 두 줄로 줄바꿈하고 이후 내용을 생략한다', (tester) async {
    const title = '표시 공간보다 긴 메뉴 항목 제목입니다';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenu(
            items: const [
              MenuItem(
                id: 'long-title',
                title: title,
                url: 'https://example.com',
                icon: 'icon:home',
              ),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            orientation: NavigationOrientation.bottom,
            buttonWidth: 120,
          ),
        ),
      ),
    );

    final titleWidget = tester.widget<Text>(find.text(title));
    expect(titleWidget.maxLines, 2);
    expect(titleWidget.softWrap, isTrue);
    expect(titleWidget.overflow, TextOverflow.ellipsis);
  });

  test('semantic versions and overnight install windows are handled', () {
    expect(
      SemanticVersion.parse('1.3.0').compareTo(SemanticVersion.parse('1.2.9')),
      greaterThan(0),
    );
    expect(
      SemanticVersion.parse('1.3.0-beta.1')
          .compareTo(SemanticVersion.parse('1.3.0')),
      lessThan(0),
    );
    const window = UpdateInstallWindow(start: '22:00', end: '05:00');
    expect(window.contains(DateTime(2026, 8, 13, 2)), isTrue);
    expect(window.contains(DateTime(2026, 8, 13, 12)), isFalse);
  });

  test('update policy retention settings round-trip and copy', () {
    final policy = UpdatePolicy.fromJson({
      'enabled': true,
      'checkIntervalHours': 12,
      'installWhenIdle': false,
      'installWindow': {'start': '23:00', 'end': '04:00'},
      'retainVersions': 4,
      'logRetentionDays': 60,
    });

    expect(policy.retainVersions, 4);
    expect(policy.logRetentionDays, 60);
    expect(policy.copyWith(enabled: false).toJson(), {
      'schemaVersion': 1,
      'enabled': false,
      'channel': 'stable',
      'checkIntervalHours': 12,
      'installWhenIdle': false,
      'installWindow': {'start': '23:00', 'end': '04:00'},
      'retainVersions': 4,
      'logRetentionDays': 60,
    });
  });

  test('update manifest parses compatibility and signer requirements', () {
    final manifest = UpdateManifest.fromJson({
      'schemaVersion': 1,
      'version': '1.2.4',
      'channel': 'stable',
      'minimumUpdaterVersion': '1.1.0',
      'configSchemaVersion': 1,
      'package': {
        'file': 'simple-kiosk-windows-1.2.4.zip',
        'sha256': 'a' * 64,
        'authenticodeRequired': true,
        'signerThumbprint': 'b' * 40,
      },
    });

    expect(manifest.minimumUpdaterVersion, '1.1.0');
    expect(manifest.configSchemaVersion, 1);
    expect(manifest.authenticodeRequired, isTrue);
    expect(manifest.signerThumbprint, 'B' * 40);
  });

  test('signed update manifest requires a signer thumbprint', () {
    expect(
      () => UpdateManifest.fromJson({
        'version': '1.2.4',
        'channel': 'stable',
        'package': {
          'file': 'simple-kiosk-windows-1.2.4.zip',
          'sha256': 'a' * 64,
          'authenticodeRequired': true,
        },
      }),
      throwsFormatException,
    );
  });

  test('업데이터 버전만 설치 호환성을 제한하고 대상 설정 스키마는 차단하지 않는다', () {
    UpdateManifest manifest({
      String minimumUpdaterVersion = '1.1.0',
      int configSchemaVersion = 1,
    }) =>
        UpdateManifest(
          version: '1.2.4',
          channel: 'stable',
          minimumUpdaterVersion: minimumUpdaterVersion,
          configSchemaVersion: configSchemaVersion,
          packageFile: 'package.zip',
          sha256: 'a' * 64,
        );

    expect(
      () => UpdateService.validateCompatibility(
        manifest(minimumUpdaterVersion: '9.0.0'),
      ),
      throwsStateError,
    );
    expect(
      () => UpdateService.validateCompatibility(
        manifest(configSchemaVersion: 999),
      ),
      returnsNormally,
    );
  });

  test('슬라이드쇼 대기화면 설정을 파싱한다', () {
    final config = IdleConfig.fromJson({
      'enabled': true,
      'timeoutSec': 30,
      'startOnLaunch': false,
      'mode': 'slideshow',
      'slideshow': {
        'intervalSec': 5,
        'transition': 'fade',
        'images': ['assets/idle/slide1.jpg'],
      },
    });

    expect(config.enabled, isTrue);
    expect(config.isUsable, isTrue);
    expect(config.mode, IdleMode.slideshow);
    expect(config.slideshow.intervalSec, 5);
    expect(config.slideshow.images, ['assets/idle/slide1.jpg']);
  });

  test('콘텐츠가 없는 슬라이드쇼는 사용할 수 없다', () {
    final config = IdleConfig.fromJson({
      'enabled': true,
      'mode': 'slideshow',
      'slideshow': {'images': <String>[]},
    });

    expect(config.isUsable, isFalse);
  });

  test('포토갤러리 대기화면 설정을 파싱한다', () {
    final config = IdleConfig.fromJson({
      'enabled': true,
      'mode': 'gallery',
      'gallery': {
        'url': 'http://example.com/gallery',
        'intervalSec': 9,
        'lookbackDays': 30,
        'minPosts': 2,
        'refreshIntervalMin': 5,
        'shuffle': true,
        'maxPosts': 3,
        'maxImages': 25,
        'transition': 'fade',
      },
    });

    expect(config.mode, IdleMode.gallery);
    expect(config.isUsable, isTrue);
    expect(config.gallery.intervalSec, 9);
    expect(config.gallery.lookbackDays, 30);
    expect(config.gallery.minPosts, 2);
    expect(config.gallery.refreshIntervalMin, 5);
    expect(config.gallery.shuffle, isTrue);
    expect(config.gallery.maxPosts, 3);
    expect(config.gallery.maxImages, 25);
  });

  test('slideshow folder gallery modes and sources can be combined', () {
    final config = IdleConfig.fromJson({
      'enabled': true,
      'modes': ['slideshow', 'folder', 'gallery'],
      'slideshow': {
        'images': ['assets/idle/one.jpg'],
      },
      'folder': {
        'paths': ['assets/idle/a/', 'assets/idle/b/'],
      },
      'gallery': {
        'urls': [
          'https://example.com/gallery-a',
          'https://example.com/gallery-b',
        ],
      },
    });

    expect(config.modes, [
      IdleMode.slideshow,
      IdleMode.folder,
      IdleMode.gallery,
    ]);
    expect(config.folder.effectivePaths, [
      'assets/idle/a/',
      'assets/idle/b/',
    ]);
    expect(config.gallery.effectiveUrls, [
      'https://example.com/gallery-a',
      'https://example.com/gallery-b',
    ]);
    expect(config.isUsable, isTrue);
  });

  test('url idle mode cannot be combined with another mode', () {
    expect(
      () => IdleConfig.fromJson({
        'enabled': true,
        'modes': ['url', 'gallery'],
        'url': 'https://example.com',
      }),
      throwsFormatException,
    );
  });

  test('gallery falls back to minPosts when date has no matches', () async {
    const listHtml = '''
      <div class="card">
        <a class="img-card" href="/post/1"><img src="/thumb-1.jpg"></a>
        <a class="bo_tit"><span class="ks4">Newest</span></a>
        <span class="gall_date">작성일 2026-08-12</span>
      </div>
      <div class="card">
        <a class="img-card" href="/post/2"><img src="/thumb-2.jpg"></a>
        <a class="bo_tit"><span class="ks4">Second</span></a>
        <span class="gall_date">작성일 2026-08-11</span>
      </div>
      <div class="card">
        <a class="img-card" href="/post/3"><img src="/thumb-3.jpg"></a>
        <a class="bo_tit"><span class="ks4">Third</span></a>
        <span class="gall_date">작성일 2026-08-10</span>
      </div>
    ''';
    final client = MockClient((request) async {
      if (request.url.path == '/gallery') {
        return http.Response.bytes(utf8.encode(listHtml), 200);
      }
      final id = request.url.pathSegments.last;
      return http.Response(
        '<div id="bo_v_con"><img src="/image-$id.jpg"></div>',
        200,
      );
    });
    final loader = GalleryFeedLoader(
      client: client,
      now: () => DateTime(2026, 8, 20, 12),
    );

    final items = await loader.load(
      const GalleryConfig(
        url: 'http://example.com/gallery',
        lookbackDays: 1,
        minPosts: 2,
        maxPosts: 3,
        maxImages: 10,
      ),
    );

    expect(items.map((item) => item.title), ['Newest', 'Second']);
    expect(items.map((item) => item.postUrl), [
      'http://example.com/post/1',
      'http://example.com/post/2',
    ]);
    loader.close();
  });

  test('gallery refresh preserves the currently displayed slide', () {
    const first = GalleryFeedItem(
      title: 'First',
      imageUrl: 'https://example.com/first.jpg',
      postUrl: 'https://example.com/post/1',
    );
    const current = GalleryFeedItem(
      title: 'Current',
      imageUrl: 'https://example.com/current.jpg',
      postUrl: 'https://example.com/post/2',
    );
    const added = GalleryFeedItem(
      title: 'Added',
      imageUrl: 'https://example.com/added.jpg',
      postUrl: 'https://example.com/post/3',
    );

    expect(
      galleryIndexAfterRefresh(
        const [first, current],
        1,
        const [added, first, current],
      ),
      2,
    );
  });

  test('gallery parses the exact post timestamp', () {
    expect(
      parsePostPublishedAt(
        '<strong class="if_date">작성일 26-08-12 18:24</strong>',
      ),
      DateTime(2026, 8, 12, 18, 24),
    );
  });

  test('gallery random order is prepared without losing existing order', () {
    const first = GalleryFeedItem(
      title: 'First',
      imageUrl: 'https://example.com/first.jpg',
      postUrl: 'https://example.com/post/1',
    );
    const second = GalleryFeedItem(
      title: 'Second',
      imageUrl: 'https://example.com/second.jpg',
      postUrl: 'https://example.com/post/2',
    );
    const added = GalleryFeedItem(
      title: 'Added',
      imageUrl: 'https://example.com/added.jpg',
      postUrl: 'https://example.com/post/3',
    );

    final order = buildGalleryPlaybackOrder(
      const [first, second, added],
      shuffle: true,
      previousOrder: const [
        'https://example.com/second.jpg',
        'https://example.com/first.jpg',
      ],
    );

    expect(order.toSet(), {first, second, added});
    expect(order.indexOf(second), lessThan(order.indexOf(first)));
    expect(
      galleryInitialIndex(order, 'https://example.com/first.jpg'),
      order.indexOf(first),
    );
  });

  test('갤러리 게시물 원본 사진과 제목을 추출한다', () async {
    const listHtml = '''
      <div class="card">
        <a class="img-card" href="/bbs/post?id=7">
          <img src="/thumb.jpg">
        </a>
        <a class="bo_tit"><span class="ks4"> 여름 캠프 </span></a>
      </div>
    ''';
    const postHtml = '''
      <div id="bo_v_con">
        <a class="view_image"
           href="/bbs/view_image.php?fn=http%3A%2F%2Fexample.com%2Foriginal-1.jpg">
          <img src="/thumb-1.jpg">
        </a>
        <a class="view_image"
           href="/bbs/view_image.php?fn=http%3A%2F%2Fexample.com%2Foriginal-2.jpg">
          <img src="/thumb-2.jpg">
        </a>
      </div>
    ''';
    final client = MockClient((request) async {
      if (request.url.path == '/gallery') {
        return http.Response.bytes(
          utf8.encode(listHtml),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      if (request.url.path == '/bbs/post') {
        return http.Response.bytes(
          utf8.encode(postHtml),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        url: 'http://example.com/gallery',
        maxPosts: 1,
        maxImages: 10,
      ),
    );

    expect(items, hasLength(2));
    expect(items.first.title, '여름 캠프');
    expect(items.first.imageUrl, 'http://example.com/original-1.jpg');
    expect(items.last.imageUrl, 'http://example.com/original-2.jpg');
    loader.close();
  });

  test('multiple gallery boards are loaded into one feed', () async {
    String listHtml(String id, String title) => '''
      <div class="card">
        <a class="img-card" href="/post-$id"><img src="/thumb-$id.jpg"></a>
        <a class="bo_tit"><span class="ks4">$title</span></a>
        <span class="gall_date">작성일 2026-08-12</span>
      </div>
    ''';
    final client = MockClient((request) async {
      if (request.url.path == '/gallery-a') {
        return http.Response.bytes(
            utf8.encode(listHtml('a', 'Gallery A')), 200);
      }
      if (request.url.path == '/gallery-b') {
        return http.Response.bytes(
            utf8.encode(listHtml('b', 'Gallery B')), 200);
      }
      if (request.url.path == '/post-a' || request.url.path == '/post-b') {
        final id = request.url.path.endsWith('a') ? 'a' : 'b';
        return http.Response(
          '<div id="bo_v_con"><img src="/image-$id.jpg"></div>',
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        urls: [
          'http://example.com/gallery-a',
          'http://example.com/gallery-b',
        ],
        maxPosts: 1,
        maxImages: 2,
      ),
    );

    expect(items.map((item) => item.title), ['Gallery A', 'Gallery B']);
    loader.close();
  });

  test('툴바는 기본적으로 숨김이며 자동 숨김 시간을 파싱한다', () {
    expect(LayoutConfig.defaults.toolbarInitiallyHidden, isTrue);
    expect(LayoutConfig.defaults.toolbarAutoHideSec, 10);
    expect(LayoutConfig.defaults.keyboardMode, KeyboardMode.windows);
    expect(LayoutConfig.defaults.showSelectedTopic, isTrue);
    expect(LayoutConfig.defaults.windowsKioskLockdown, isTrue);
    expect(LayoutConfig.defaults.windowsAlwaysOnTop, isFalse);

    final config = LayoutConfig.fromJson({
      'toolbarInitiallyHidden': false,
      'toolbarAutoHideSec': 25,
      'barColor': '#123456',
      'keyboardMode': 'builtin',
      'showSelectedTopic': false,
      'windowsKioskLockdown': false,
      'windowsAlwaysOnTop': true,
    });
    expect(config.toolbarInitiallyHidden, isFalse);
    expect(config.toolbarAutoHideSec, 25);
    expect(config.barColor, const Color(0xFF123456));
    expect(config.keyboardMode, KeyboardMode.builtIn);
    expect(config.showSelectedTopic, isFalse);
    expect(config.windowsKioskLockdown, isFalse);
    expect(config.windowsAlwaysOnTop, isTrue);
    expect(
      () => LayoutConfig.fromJson({'keyboardMode': 'unknown'}),
      throwsFormatException,
    );
  });

  test('Windows 키오스크 잠금은 앱 전환과 셸 단축키를 차단한다', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('simple_kiosk/windows_kiosk_mode'));
    expect(source, contains('VK_LWIN'));
    expect(source, contains('VK_RWIN'));
    expect(source, contains('VK_TAB'));
    expect(source, contains('VK_ESCAPE'));
    expect(source, contains('VK_LAUNCH_APP1'));
    expect(source, contains('ArmEmergencyExit'));
    expect(source, contains('compare_exchange_strong'));
    expect(source, contains('g_emergency_exit_sequence'));
    expect(source, contains('FlutterViewTouchProc'));
    expect(source, contains('WM_POINTERDOWN'));
    expect(source, contains('g_active_touch_points'));
    expect(source, contains('8000'));
    expect(source, contains('RecoverRenderingSurface'));
    expect(source, contains('kSurfaceWatchdogTimerId'));
    expect(source, contains('TerminateProcess'));

    final windowSource =
        File('windows/runner/win32_window.cpp').readAsStringSync();
    expect(windowSource, contains('BLACK_BRUSH'));
  });

  test('Windows 키보드 토글은 실제 창 상태를 확인해 반복 동작한다', () async {
    const channel = MethodChannel('simple_kiosk/system_keyboard');
    final calls = <String>[];
    var nativeVisible = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isVisible':
          return nativeVisible;
        case 'show':
          nativeVisible = true;
          return true;
        case 'hide':
          nativeVisible = false;
          return true;
      }
      return null;
    });
    addTearDown(() async {
      await SystemKeyboard.hide();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    SystemKeyboard.configure(KeyboardMode.windows);
    await SystemKeyboard.toggle();
    expect(KeyboardController.instance.visible.value, isTrue);
    await SystemKeyboard.toggle();
    expect(KeyboardController.instance.visible.value, isFalse);
    await SystemKeyboard.toggle();
    expect(KeyboardController.instance.visible.value, isTrue);
    expect(calls, [
      'isVisible',
      'show',
      'isVisible',
      'hide',
      'isVisible',
      'show',
    ]);
  });

  test('Windows 시작프로그램 상태와 시작 모드를 파싱한다', () {
    final status = WindowsStartupStatus.fromMap({
      'supported': true,
      'registered': true,
      'targetMatches': true,
      'mode': 'hidden',
      'shortcutPath': r'C:\Startup\여의도성당Signage.lnk',
    });

    expect(status.supported, isTrue);
    expect(status.registered, isTrue);
    expect(status.targetMatches, isTrue);
    expect(status.mode, StartupLaunchMode.hidden);
  });

  testWidgets('접힌 툴바 오버레이에 필수 컨트롤을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CollapsedToolbarOverlay(
                historyController: null,
                onShowToolbar: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.keyboard), findsOneWidget);
  });

  testWidgets('접힌 툴바를 드래그하면 가까운 모서리에 정렬한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CollapsedToolbarOverlay(
                    historyController: null,
                    onShowToolbar: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final restoreIcon = find.byIcon(Icons.visibility_outlined);
    final initial = tester.getCenter(restoreIcon);
    expect(initial.dx, greaterThan(400));
    expect(initial.dy, greaterThan(300));

    await tester.drag(restoreIcon, const Offset(-500, -400));
    await tester.pumpAndSettle();

    final moved = tester.getCenter(restoreIcon);
    expect(moved.dx, lessThan(400));
    expect(moved.dy, lessThan(300));
  });

  testWidgets('툴바 표시 상태가 바뀌어도 WebView 자식을 재생성하지 않는다', (tester) async {
    final probeKey = GlobalKey<_LifecycleProbeState>();

    Widget buildHost(bool hidden) => MaterialApp(
          home: Scaffold(
            body: ToolbarHost(
              hidden: hidden,
              position: NavPosition.right,
              sideWidth: 220,
              toolbarHeight: 96,
              webView: _LifecycleProbe(key: probeKey),
              toolbar: const SizedBox(width: 220),
              overlay: const SizedBox.shrink(),
            ),
          ),
        );

    await tester.pumpWidget(buildHost(false));
    final originalState = probeKey.currentState;
    expect(originalState, isNotNull);

    await tester.pumpWidget(buildHost(true));
    expect(probeKey.currentState, same(originalState));
    expect(originalState!.disposeCount, 0);

    await tester.pumpWidget(buildHost(false));
    expect(probeKey.currentState, same(originalState));
    expect(originalState.disposeCount, 0);
  });

  testWidgets('표시된 툴바는 입력이 없으면 자동 숨김을 요청한다', (tester) async {
    var hideCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolbarHost(
            hidden: false,
            toolbarHeight: 96,
            autoHideDuration: const Duration(seconds: 2),
            onAutoHide: () => hideCount += 1,
            webView: const ColoredBox(color: Colors.white),
            toolbar: const SizedBox(height: 96),
            overlay: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(hideCount, 0);

    await tester.tapAt(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(hideCount, 0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(hideCount, 1);
  });

  testWidgets('메뉴바 우측 화면 보호기 버튼이 즉시 진입을 요청한다', (tester) async {
    var enterCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenu(
            items: const [],
            selectedIndex: 0,
            onSelected: (_) {},
            orientation: NavigationOrientation.bottom,
            onEnterIdle: () => enterCount += 1,
          ),
        ),
      ),
    );

    final button = find.byTooltip('화면 보호기 시작');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(enterCount, 1);
  });

  testWidgets('현재 주제는 버튼이 아닌 작은 라벨로 툴바 시작 위치에 표시된다', (tester) async {
    const items = [
      MenuItem(id: 'home', title: '홈', url: 'https://example.com'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 220,
              height: 500,
              child: NavigationMenu(
                items: items,
                selectedIndex: 0,
                onSelected: (_) {},
                orientation: NavigationOrientation.side,
                selectedTopicLabel: '여의도동 성당',
              ),
            ),
          ),
        ),
      ),
    );

    final sideLabel = find.byKey(const ValueKey('selected-topic-label'));
    expect(sideLabel, findsOneWidget);
    expect(
      find.ancestor(of: sideLabel, matching: find.byType(FilledButton)),
      findsNothing,
    );
    expect(tester.getTopLeft(sideLabel).dy,
        lessThan(tester.getTopLeft(find.text('홈')).dy));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 96,
            child: NavigationMenu(
              items: items,
              selectedIndex: 0,
              onSelected: (_) {},
              orientation: NavigationOrientation.bottom,
              selectedTopicLabel: '여의도동 성당',
            ),
          ),
        ),
      ),
    );

    final horizontalLabel = find.byKey(const ValueKey('selected-topic-label'));
    expect(
      tester.getTopLeft(horizontalLabel).dx,
      lessThan(tester.getTopLeft(find.text('홈')).dx),
    );
    expect(tester.getSize(horizontalLabel).width, lessThanOrEqualTo(150));
  });

  testWidgets('시작 화면 보호기는 첫 프레임부터 표시하고 진입 콜백은 한 번만 호출한다', (tester) async {
    var enterCount = 0;
    const config = IdleConfig(
      enabled: true,
      startOnLaunch: true,
      modes: [IdleMode.image],
      image: 'assets/icons/app_icon.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: IdleGate(
          config: config,
          onEnterIdle: () => enterCount += 1,
          child: const ColoredBox(
            key: ValueKey('normal-screen'),
            color: Colors.red,
          ),
        ),
      ),
    );

    expect(find.byType(IdleOverlay), findsOneWidget);
    expect(enterCount, 1);
    await tester.pump();
    expect(enterCount, 1);
  });

  testWidgets('화면 보호기와 툴바 감추기를 순서대로 더블클릭한다', (tester) async {
    var enterCount = 0;
    var prepareCount = 0;
    var completeCount = 0;
    var toolbarHideCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenu(
            items: const [],
            selectedIndex: 0,
            onSelected: (_) {},
            orientation: NavigationOrientation.bottom,
            onEnterIdle: () => enterCount += 1,
            onHide: () => toolbarHideCount += 1,
            onPrepareHideKiosk: () => prepareCount += 1,
            onHideKiosk: () => completeCount += 1,
          ),
        ),
      ),
    );

    final idleButton = find.byTooltip('화면 보호기 시작');
    final hideButton = find.byTooltip('툴바 감추기');
    expect(idleButton, findsOneWidget);
    expect(hideButton, findsOneWidget);

    await tester.tap(idleButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(idleButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(prepareCount, 1);
    expect(completeCount, 0);
    expect(enterCount, 0);

    await tester.tap(hideButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(hideButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(completeCount, 1);
    expect(toolbarHideCount, 0);

    await tester.tap(idleButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(enterCount, 1);
  });

  testWidgets('오른쪽 툴바에서 감추기를 포함한 모든 기능 아이콘을 표시한다', (tester) async {
    var hideCount = 0;
    var languageCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 220,
              height: 600,
              child: NavigationMenu(
                items: const [],
                selectedIndex: 0,
                onSelected: (_) {},
                orientation: NavigationOrientation.side,
                sideWidth: 220,
                showKeyboardToggle: true,
                onSelectLanguage: () => languageCount += 1,
                onOpenAdmin: () {},
                onEnterIdle: () {},
                onHideKiosk: () {},
                onHide: () => hideCount += 1,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.keyboard), findsOneWidget);
    expect(find.byIcon(Icons.translate), findsOneWidget);
    final languageButton = find.byTooltip('언어 선택');
    expect(languageButton, findsOneWidget);
    await tester.tap(languageButton);
    expect(languageCount, 1);
    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    expect(find.byIcon(Icons.wallpaper_outlined), findsOneWidget);
    final hideButton = find.byTooltip('툴바 감추기');
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(hideButton, findsOneWidget);
    await tester.tap(hideButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(hideCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('세로 툴바는 메뉴 버튼을 축소하고 부족할 때만 스크롤바를 표시한다', (tester) async {
    final manyItems = List.generate(
      10,
      (index) => MenuItem(
        id: 'menu$index',
        title: '메뉴 $index',
        url: 'https://example.com/$index',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 220,
              height: 500,
              child: NavigationMenu(
                items: manyItems,
                selectedIndex: 0,
                onSelected: (_) {},
                orientation: NavigationOrientation.side,
                sideWidth: 220,
                showHistoryButtons: true,
                showKeyboardToggle: true,
                onOpenAdmin: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 500,
            child: NavigationMenu(
              items: manyItems.take(2).toList(),
              selectedIndex: 0,
              onSelected: (_) {},
              orientation: NavigationOrientation.side,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('F1, F12, F9 기능키를 전역 단축키로 처리한다', (tester) async {
    var manualCount = 0;
    var versionCount = 0;
    var updateCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KioskShortcuts(
          onShowManual: () => manualCount += 1,
          onShowVersion: () => versionCount += 1,
          onCheckUpdate: () => updateCount += 1,
          child: const Scaffold(body: Text('Kiosk')),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f12);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f9);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f9);
    await tester.pump();

    expect(manualCount, 1);
    expect(versionCount, 1);
    expect(updateCount, 1);
  });
}

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({super.key});

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.white);
}
