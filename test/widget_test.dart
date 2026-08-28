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
import 'package:simple_kiosk/service/font_resource_service.dart';
import 'package:simple_kiosk/service/admin_pin_store.dart';
import 'package:simple_kiosk/widget/admin_pin_keypad.dart';
import 'package:simple_kiosk/service/menu_config_merger.dart';
import 'package:simple_kiosk/service/menu_config_loader.dart';
import 'package:simple_kiosk/service/menu_config_migrator.dart';
import 'package:simple_kiosk/service/keyboard_controller.dart';
import 'package:simple_kiosk/service/media_scanner.dart';
import 'package:simple_kiosk/service/system_keyboard.dart';
import 'package:simple_kiosk/service/touch_input_guard.dart';
import 'package:simple_kiosk/service/update_service.dart';
import 'package:simple_kiosk/service/windows_startup_service.dart';
import 'package:simple_kiosk/widget/idle_gate.dart';
import 'package:simple_kiosk/widget/idle_overlay.dart';
import 'package:simple_kiosk/widget/kiosk_shortcuts.dart';
import 'package:simple_kiosk/widget/kiosk_webview.dart';
import 'package:simple_kiosk/widget/language_selection.dart';
import 'package:simple_kiosk/widget/navigation_menu.dart';
import 'package:simple_kiosk/widget/version_overlay.dart';
import 'package:simple_kiosk/widget/webview_loading_overlay.dart';

void main() {
  test('터치 입력 폭주는 합치고 메뉴별 재로드에는 냉각 시간을 둔다', () {
    final guard = TouchInputGuard<String>();
    final startedAt = DateTime.utc(2026, 8, 28);

    expect(guard.acceptSelection('home', startedAt), isTrue);
    expect(
      guard.acceptSelection(
        'another',
        startedAt.add(const Duration(milliseconds: 50)),
      ),
      isFalse,
    );
    expect(
      guard.acceptSelection(
        'another',
        startedAt.add(const Duration(milliseconds: 120)),
      ),
      isTrue,
    );
    expect(
      guard.acceptSelection(
        'another',
        startedAt.add(const Duration(milliseconds: 170)),
      ),
      isTrue,
    );

    expect(guard.acceptReload('home', startedAt), isTrue);
    expect(
      guard.acceptReload('home', startedAt.add(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      guard.acceptReload('home', startedAt.add(const Duration(seconds: 2))),
      isTrue,
    );
    expect(guard.acceptReload('another', startedAt), isTrue);
  });

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
    expect(page, contains('function buildConfigOverride(base,effective)'));
    expect(page, contains('JSON.stringify(override)'));
    expect(page, contains('전체 기본값 복원'));
    expect(page, contains('이 섹션 기본값 복원'));
    expect(page, contains('이 값 복원'));
    expect(page, contains('이 메뉴 복원'));
    expect(page, contains("function visibilityField(target,onRestore)"));
    expect(page, contains("['false','표시'],['true','숨김']"));
    expect(page, contains('주제 선택 후 첫 메뉴'));
    expect(page, contains('주제 추가'));
    expect(page, contains("webViewData.idlePolicy"));
    expect(page, contains('layout.menuFontFamily'));
    expect(page, contains('언어 선택 전체 글꼴'));
    expect(page, contains("restoreProperty('fontFamily')"));
    expect(page, contains('선택 아이콘 (선택 사항)'));
    expect(page, contains("restoreProperty('selectedIcon')"));
    expect(page, contains('Local Storage'));
    expect(page, contains('id="reauthOverlay"'));
    expect(page, contains('현재 화면과 저장하지 않은 설정은 그대로 유지됩니다.'));
    expect(page, contains('function requireReauthentication'));
    expect(page, contains('await requireReauthentication()'));
    expect(page,
        contains('sessionStorage.getItem(\'simpleKioskAdminExpiresAt\')'));
    expect(page, isNot(contains('logout(false)')));
    expect(page, contains('/api/session/refresh'));
    expect(page, contains('원격 WEB 관리자 연결'));
    expect(page, contains('webAdminSshForwardingEnabled'));
    expect(page, contains('signage.cuniverse.net'));
    expect(page, contains('webAdminSshForwardingState'));
    expect(page, contains(r"setInterval(()=>{if(token&&!$('adminTabApi')"));
    expect(
        page, contains("['pointerdown','keydown','input','change','wheel']"));
  });

  test('웹 관리자에 exdata 전용 탐색기형 파일 관리 화면이 포함된다', () {
    final page = File('assets/admin/index.html').readAsStringSync();

    expect(page, contains('data-admin-tab="files"'));
    expect(page, contains('id="adminTabFiles"'));
    expect(page, contains('id="fileAddress"'));
    expect(page, contains('id="fileUploadInput"'));
    expect(page, contains('fileUploadChunkBytes=512*1024'));
    expect(page, contains('uploadId='));
    expect(page, contains('/api/files/list?path='));
    expect(page, contains('/api/files/upload?path='));
    expect(page, contains('/api/files/download?path='));
    expect(page, contains('/api/files/directory'));
    expect(page, contains('/api/files/move'));
    expect(page, contains('/api/files/change-check'));
    expect(page, contains('alert(e.message)'));
    expect(page, contains("addEventListener('drop'"));
    expect(page, contains('selectedFilePaths=new Set()'));
    expect(page, contains('event.shiftKey'));
    expect(page, contains('event.ctrlKey||event.metaKey'));
    expect(page, contains("e.key.toLowerCase()==='a'"));
    expect(page, contains(r'선택한 ${entries.length}개 항목'));
  });

  test('웹 관리자에서 로그인 없이 GitHub 이슈 중계 서버에 등록한다', () {
    final page = File('assets/admin/index.html').readAsStringSync();

    expect(page, contains('id="issueTitle"'));
    expect(page, contains('id="issueDescription"'));
    expect(page, contains('id="submitGitHubIssue"'));
    expect(page, contains('id="copyIssueReport"'));
    expect(page, contains("fetch('/api/github-issues'"));
    expect(page, contains('async function buildIssueReport()'));
    expect(page, contains('async function submitGitHubIssue()'));
    expect(page, contains("get('tab')"));
    expect(page, contains('selectAdminTab(requestedAdminTab)'));
    expect(page, contains(r"$('issueTitle').focus()"));
    expect(page, contains('system.operatingSystemVersion'));
    expect(page, isNot(contains('githubToken')));
    expect(page, isNot(contains('/issues/new')));
  });

  test('GitHub App 기반 PHP 이슈 중계기와 Nginx 설정을 제공한다', () {
    final relay = File(
      'deploy/github-issue-relay/public/index.php',
    ).readAsStringSync();
    final config = File(
      'deploy/github-issue-relay/config.example.php',
    ).readAsStringSync();
    final nginx = File(
      'deploy/github-issue-relay/nginx.conf.example',
    ).readAsStringSync();

    expect(relay, contains('openssl_sign'));
    expect(relay, contains('/app/installations/'));
    expect(relay, contains('/issues'));
    expect(relay, isNot(contains("'Issues'")));
    expect(config, contains('github_app_client_id'));
    expect(config, contains('github_private_key_file'));
    expect(config, isNot(contains('github_pat_')));
    expect(nginx, contains('location = /api/github-issues'));
    expect(nginx, contains('limit_req zone='));
    expect(nginx, contains('unix:/run/php/php-fpm.sock'));
    expect(nginx, isNot(contains(RegExp(r'php\d+\.\d+-fpm\.sock'))));
  });

  test('웹 관리자는 레이아웃과 UI 모양을 분리하고 사용자 테마를 관리한다', () {
    final page = File('assets/admin/index.html').readAsStringSync();

    expect(page, contains('data-section="appearance"'));
    expect(page, contains('UI 모양·테마'));
    expect(page, contains('id=\'themeWarning\''));
    expect(page, contains('/api/themes'));
    expect(page, contains('saveCurrentTheme'));
    expect(page, contains('appearanceChangedFromSaved'));
    expect(page, contains('사용자 테마 삭제'));
  });

  test('웹 관리자는 갤러리 주소별 게시물 조회 조건을 편집한다', () {
    final page = File('assets/admin/index.html').readAsStringSync();

    expect(page, contains('normalizeGallerySources'));
    expect(page, contains('갤러리 주소별 게시물 설정'));
    expect(page, contains("sourceField('게시물 조회 기간(일)'"));
    expect(page, contains("sourceField('최소 게시물 수'"));
    expect(page, contains("sourceField('최대 게시물 수'"));
    expect(page, contains("add=node('button','','주소 추가')"));
  });

  test('exdata 상대경로를 데이터 루트 파일로 해석하고 대기화면에서 표시한다', () {
    final loader = File(
      'lib/service/menu_config_loader.dart',
    ).readAsStringSync();
    final idleOverlay = File(
      'lib/widget/idle_overlay.dart',
    ).readAsStringSync();
    final navigation =
        File('lib/widget/navigation_menu.dart').readAsStringSync();
    final language =
        File('lib/widget/language_selection.dart').readAsStringSync();

    expect(loader, contains("value.startsWith('exdata/')"));
    expect(idleOverlay, contains('_MixedMediaKind.fileImage'));
    expect(idleOverlay, contains('PlatformFileImage(key: key'));
    expect(navigation, contains('if (_isAbsoluteFilePath(path))'));
    expect(navigation, contains('return PlatformFileImage('));
    expect(language, contains('if (_isAbsoluteFilePath(value))'));
  });

  test('고대비 기본 UI 값은 프리로드 고대비 테마와 정확히 일치한다', () {
    final defaults = jsonDecode(
      File('assets/config/menu.defaults.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final theme = jsonDecode(
      File('assets/themes/high-contrast.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final layout = defaults['layout'] as Map<String, dynamic>;
    final values = theme['values'] as Map<String, dynamic>;

    for (final entry in values.entries) {
      expect(layout[entry.key], entry.value, reason: entry.key);
    }
  });

  test('제거 시 사용자 데이터 삭제를 선택하면 exdata도 삭제한다', () {
    final installer = File('scripts/simple-kiosk.iss').readAsStringSync();
    expect(
      installer,
      contains("DelTree(AddBackslash(InstallRoot) + 'exdata'"),
    );
  });

  test('Windows 릴리스 외부 필수 파일 다운로드는 검증하며 재시도한다', () {
    final script = File('scripts/package-windows.ps1').readAsStringSync();
    expect(script, contains('Invoke-MicrosoftDownloadWithRetry'));
    expect(script, contains(r'$MaxAttempts = 3'));
    expect(script,
        contains(r'Assert-MicrosoftAuthenticodeSignature $temporaryFile'));
    expect(script, contains(r'Move-Item -LiteralPath $temporaryFile'));
  });

  test('Windows Setup은 제한된 방화벽 규칙을 선택 설치하고 제거한다', () {
    final installer = File('scripts/simple-kiosk.iss').readAsStringSync();
    final firewall = File(
      'scripts/configure-firewall.ps1',
    ).readAsStringSync();
    final packager = File(
      'scripts/package-windows.ps1',
    ).readAsStringSync();

    expect(installer, contains('Name: "firewall"'));
    expect(installer, contains("ConfigureFirewall('Install')"));
    expect(installer, contains("ConfigureFirewall('Remove')"));
    expect(installer, contains("ShellExec("));
    expect(installer, contains("'runas'"));
    expect(installer, contains('WizardSilent'));
    expect(installer, contains('firewall-managed'));
    expect(firewall, contains('function Remove-ManagedFirewallRules'));
    expect(firewall, contains('catch {'));
    expect(firewall, contains("'state\\firewall-managed'"));
    expect(firewall, contains('-Profile Domain, Private'));
    expect(firewall, contains('-RemoteAddress LocalSubnet'));
    expect(firewall, contains('-Protocol TCP'));
    expect(firewall, contains('-Protocol UDP'));
    expect(firewall, isNot(contains('-Profile Any')));
    expect(packager, contains("Copy-Item 'scripts\\configure-firewall.ps1'"));
  });

  test('Windows 트레이는 웹관리자와 리버스 포워딩 상태를 표시한다', () {
    final tray = File(
      'lib/service/kiosk_tray_controller.dart',
    ).readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final nativeTray = File(
      'packages/tray_manager-0.5.3/windows/tray_manager_plugin.cpp',
    ).readAsStringSync();

    expect(tray, contains("key: 'web-admin'"));
    expect(tray, contains("key: 'restart'"));
    expect(tray, contains("label: '사이니지 재시작'"));
    expect(tray, contains("label: '웹관리자 열기'"));
    expect(tray, contains(r'리버스 포워딩: $_reverseForwardingStatus'));
    expect(tray, contains("? 'status-connected'"));
    expect(tray, contains(": 'status-disconnected'"));
    expect(tray, contains('disabled: !reverseForwardingConnected'));
    expect(app, contains("forwardingActive ? '연결됨' : '연결 안 됨'"));
    expect(nativeTray, contains('CreateStatusBitmap'));
    expect(nativeTray, contains('MIIM_BITMAP'));
    expect(nativeTray, contains('status-connected'));
    expect(nativeTray, contains('status-disconnected'));
    expect(tray, contains(r"MenuItem(label: '주소: $uri'"));
    expect(app, contains('tunnel.forwardingVerified'));
    expect(app, contains('LaunchMode.externalApplication'));
    expect(
      tray,
      contains('popUpContextMenu(bringAppToFront: true)'),
    );
  });

  test('재생 불가능한 단일 폴더 동영상은 반복 재시도하지 않는다', () {
    final idleOverlay = File('lib/widget/idle_overlay.dart').readAsStringSync();
    expect(
      idleOverlay,
      contains('단일 항목은 반복 재시도하지 않는다.'),
    );
    expect(
      idleOverlay,
      contains("_error = '동영상을 재생할 수 없습니다:"),
    );
  });

  test('WebView 오류 화면은 종료 이벤트에 취소되지 않고 자동 재시도한다', () {
    final webView = File('lib/widget/kiosk_webview.dart').readAsStringSync();
    expect(
        webView,
        contains(
            'static const Duration _autoRetryDelay = Duration(seconds: 5)'));
    expect(webView, contains('final failed = _errorMessage != null;'));
    expect(webView, contains('if (failed) return;'));
    expect(webView, contains('if (widget.active) _scheduleAutoRetry();'));
    expect(
        webView, contains('if (_errorMessage != null) _scheduleAutoRetry();'));
    expect(webView, contains('// 보이지 않는 메뉴가 백그라운드에서 계속 새로고침되지 않게 한다.'));
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

  test('웹 관리자 링크는 PIN 입력창이 아니라 인증 후 설정창 하단에 표시한다', () {
    final source =
        File('lib/widget/update_admin_dialog.dart').readAsStringSync();
    final pinDialogEnd = source.indexOf('final validPin');
    final adminPanelStart = source.indexOf('class _UpdateAdminPanelState');
    const link = "ValueKey('open-web-admin')";

    expect(pinDialogEnd, greaterThan(0));
    expect(adminPanelStart, greaterThan(pinDialogEnd));
    expect(source.substring(0, pinDialogEnd), isNot(contains(link)));
    expect(source.substring(adminPanelStart), contains(link));
    expect(source.substring(adminPanelStart), contains('actions: ['));
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

  test('메뉴 선택 아이콘을 선택적으로 파싱한다', () {
    final selected = MenuItem.fromJson({
      'id': 'home',
      'title': '홈',
      'url': 'https://example.com',
      'icon': 'icon:home',
      'selectedIcon': 'icon:favorite',
    });
    final fallback = MenuItem.fromJson({
      'id': 'notice',
      'title': '공지',
      'url': 'https://example.com/notice',
      'icon': 'icon:notice',
    });

    expect(selected.icon, 'icon:home');
    expect(selected.selectedIcon, 'icon:favorite');
    expect(fallback.selectedIcon, isNull);
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
      'languageSelection': {
        'skipSingleTopic': false,
        'fontFamily': 'NanumSquare',
      },
      'languages': [
        {
          'id': 'ko',
          'label': '한국어',
          'fontFamily': 'Catholic',
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
                {
                  'id': 'map',
                  'title': '지도',
                  'url': 'https://map.example',
                  'fontFamily': 'NanumBrush',
                },
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
    expect(config.languageSelectionFontFamily, 'NanumSquare');
    expect(language.fontFamily, 'Catholic');
    expect(language.defaultItem.fontFamily, 'NanumBrush');
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
    final parishItems =
        config.language('ko').topic('ycatholic').items.map((item) => item.id);
    expect(
      parishItems,
      containsAll(['annual-events', 'sacraments', 'mass-times']),
    );
    const vaticanUrls = {
      'ko': 'https://www.vaticannews.va/ko.html',
      'en': 'https://www.vaticannews.va/en.html',
      'es': 'https://www.vaticannews.va/es.html',
      'fr': 'https://www.vaticannews.va/fr.html',
      'pt': 'https://www.vaticannews.va/pt.html',
      'it': 'https://www.vaticannews.va/it.html',
    };
    final rawLanguages = Map.fromEntries(
      (decoded['languages'] as List).cast<Map<String, dynamic>>().map(
            (language) => MapEntry(language['id'] as String, language),
          ),
    );
    for (final entry in vaticanUrls.entries) {
      final language = rawLanguages[entry.key]!;
      final item = (language['topics'] as List)
          .cast<Map<String, dynamic>>()
          .expand(
            (topic) => (topic['items'] as List).cast<Map<String, dynamic>>(),
          )
          .firstWhere((item) => item['id'] == 'vatican-news');
      expect(item['url'], entry.value);
      expect(item['icon'], 'assets/icons/vatican-news-white.png');
      expect(item['selectedIcon'], 'assets/icons/vatican-news.png');
    }
    for (final path in [
      'assets/icons/aos-toolbar.png',
      'assets/icons/goodnews-white.png',
      'assets/icons/goodnews.png',
      'assets/icons/vatican-news-black.png',
      'assets/icons/vatican-news-white.png',
      'assets/icons/vatican-news.png',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(File('assets/icons/goodnews-wite.png').existsSync(), isFalse);
    expect(config.layout.fontFamily, 'Pretendard');
    expect(config.layout.menuFontFamily, 'Pretendard');
    final highContrast = jsonDecode(
      File('assets/themes/high-contrast.json').readAsStringSync(),
    )['values'] as Map<String, dynamic>;
    expect(config.layout.sideWidth, highContrast['sideWidth']);
    expect(config.layout.barHeight, highContrast['barHeight']);
    expect(config.layout.buttonGap, highContrast['buttonGap']);
    expect(config.layout.barColor, const Color(0xFF000000));
    expect(config.layout.buttonColor, const Color(0xFF171717));
    expect(config.layout.selectedButtonColor, const Color(0xFFFACC15));
    expect(
        config.layout.selectedButtonForegroundColor, const Color(0xFF000000));
    expect(config.languageSelectionFontFamily, 'Pretendard');
    expect(config.language('ko').fontFamily, 'NanumSquare');
    expect(
      config.languages.expand((language) => language.effectiveTopics).expand(
            (topic) => topic.items,
          ),
      everyElement(predicate<MenuItem>((item) => item.fontFamily != null)),
    );
    expect(
      config
          .language('ko')
          .effectiveTopics
          .expand((topic) => topic.items)
          .firstWhere((item) => item.title == '주보')
          .fontFamily,
      'NanumBrush',
    );
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
          fontFamily: 'NanumSquare',
          languages: const [
            MenuLanguage(
              id: 'ko',
              label: '한국어',
              fontFamily: 'Catholic',
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
          versionLabel: '1.2.32',
        ),
      ),
    );

    final button = find.byKey(const ValueKey('language-ko'));
    expect(button, findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.getSize(button), const Size(400, 190));
    expect(tester.widget<Text>(find.text('언어를 선택하세요')).style?.fontFamily,
        'NanumSquare');
    expect(tester.widget<Text>(find.text('한국어')).style?.fontFamily, 'Catholic');
    final version = find.byKey(const ValueKey('version-overlay'));
    expect(version, findsOneWidget);
    expect(find.text('v1.2.32'), findsOneWidget);
    expect(tester.getBottomRight(version).dx, greaterThan(770));
    expect(tester.getBottomRight(version).dy, greaterThan(570));
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
    expect(
      tester.getSize(selectedLanguageButton),
      tester.getSize(find.byKey(const ValueKey('topic-parish'))),
    );

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

  test('터치 폭주 시 이전 WebView와 과도한 타이머·확대 갱신을 정리한다', () {
    final appSource = File('lib/app.dart').readAsStringSync();
    final idleSource = File('lib/widget/idle_gate.dart').readAsStringSync();
    final webViewSource =
        File('lib/widget/kiosk_webview.dart').readAsStringSync();

    expect(appSource, contains('_discardPendingMount'));
    expect(appSource, contains('_touchInputGuard.acceptSelection'));
    expect(idleSource, contains('_activityTimerResetInterval'));
    expect(webViewSource, contains('_zoomUpdateInterval'));
    expect(webViewSource, contains('Heartbeat timeout'));
    expect(webViewSource, contains('Navigation response timeout'));
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
                fontFamily: 'NanumBrush',
              ),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            orientation: NavigationOrientation.bottom,
            buttonWidth: 120,
            fontFamily: 'NanumGothic',
          ),
        ),
      ),
    );

    final titleWidget = tester.widget<Text>(find.text(title));
    expect(titleWidget.maxLines, 2);
    expect(titleWidget.softWrap, isTrue);
    expect(titleWidget.overflow, TextOverflow.ellipsis);
    expect(titleWidget.style?.fontFamily, 'NanumBrush');
  });

  testWidgets('툴바 전체 글꼴은 개별 설정이 없는 메뉴에 적용된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenu(
            items: const [
              MenuItem(id: 'home', title: '홈', url: 'https://example.com'),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            orientation: NavigationOrientation.bottom,
            fontFamily: 'NanumGothic',
          ),
        ),
      ),
    );

    expect(
        tester.widget<Text>(find.text('홈')).style?.fontFamily, 'NanumGothic');
  });

  testWidgets('네비게이션 버튼은 카드 테두리와 선택 표시 막대를 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationMenu(
            items: const [
              MenuItem(id: 'home', title: '홈', url: 'https://example.com'),
              MenuItem(
                  id: 'news', title: '소식', url: 'https://example.com/news'),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            orientation: NavigationOrientation.bottom,
          ),
        ),
      ),
    );

    final selectedButton = find.ancestor(
      of: find.text('홈'),
      matching: find.byType(ElevatedButton),
    );
    final unselectedButton = find.ancestor(
      of: find.text('소식'),
      matching: find.byType(ElevatedButton),
    );
    final selectedShape = tester
        .widget<ElevatedButton>(selectedButton)
        .style
        ?.shape
        ?.resolve({}) as RoundedRectangleBorder?;
    final unselectedShape = tester
        .widget<ElevatedButton>(unselectedButton)
        .style
        ?.shape
        ?.resolve({}) as RoundedRectangleBorder?;

    expect(selectedShape?.borderRadius, BorderRadius.circular(18));
    expect(selectedShape?.side.width, 1.5);
    expect(unselectedShape?.side.width, 1);
    expect(
      find.byKey(const ValueKey('selected-navigation-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('선택된 메뉴만 selectedIcon을 사용하고 해제되면 기본 icon으로 돌아간다', (tester) async {
    const items = [
      MenuItem(
        id: 'home',
        title: '홈',
        url: 'https://example.com',
        icon: 'icon:home',
        selectedIcon: 'icon:favorite',
      ),
      MenuItem(
        id: 'notice',
        title: '공지',
        url: 'https://example.com/notice',
        icon: 'icon:notice',
        selectedIcon: 'icon:star',
      ),
    ];

    Widget buildMenu(int selectedIndex) => MaterialApp(
          home: Scaffold(
            body: NavigationMenu(
              items: items,
              selectedIndex: selectedIndex,
              onSelected: (_) {},
              orientation: NavigationOrientation.bottom,
            ),
          ),
        );

    await tester.pumpWidget(buildMenu(0));
    expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
    expect(find.byIcon(Icons.home_filled), findsNothing);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.byIcon(Icons.star_outline), findsNothing);

    await tester.pumpWidget(buildMenu(1));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_outline), findsNothing);
    expect(find.byIcon(Icons.home_filled), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    expect(find.byIcon(Icons.star_outline), findsOneWidget);
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

  test('슬라이드쇼는 폴더와 같은 동영상 확장자를 판별한다', () {
    for (final extension in MediaScanner.videoExtensions) {
      expect(
        MediaScanner.isVideoPath('assets/idle/movie$extension'),
        isTrue,
      );
    }
    expect(
      MediaScanner.isVideoPath(
        'https://example.com/event.MP4?token=abc#playback',
      ),
      isTrue,
    );
    expect(MediaScanner.isVideoPath('exdata/slides/movie.mp4.jpg'), isFalse);
    expect(MediaScanner.isVideoPath('assets/idle/slide.webp'), isFalse);
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
          {
            'url': 'https://example.com/gallery-a',
            'lookbackDays': 30,
            'minPosts': 2,
            'maxPosts': 5,
          },
          {
            'url': 'https://example.com/gallery-b',
            'lookbackDays': 7,
            'minPosts': 1,
            'maxPosts': 2,
          },
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
    expect(config.gallery.effectiveSources[0].lookbackDays, 30);
    expect(config.gallery.effectiveSources[0].minPosts, 2);
    expect(config.gallery.effectiveSources[0].maxPosts, 5);
    expect(config.gallery.effectiveSources[1].lookbackDays, 7);
    expect(config.gallery.effectiveSources[1].minPosts, 1);
    expect(config.gallery.effectiveSources[1].maxPosts, 2);
    expect(config.isUsable, isTrue);
  });

  test('legacy gallery URL strings inherit the common post settings', () {
    final config = GalleryConfig.fromJson({
      'urls': [
        'https://example.com/gallery-a',
        'https://example.com/gallery-b',
      ],
      'lookbackDays': 14,
      'minPosts': 2,
      'maxPosts': 6,
    });

    expect(config.effectiveSources, hasLength(2));
    expect(config.effectiveSources.every((source) => source.lookbackDays == 14),
        isTrue);
    expect(config.effectiveSources.every((source) => source.minPosts == 2),
        isTrue);
    expect(config.effectiveSources.every((source) => source.maxPosts == 6),
        isTrue);
  });

  test('gallery source minimum posts cannot exceed its maximum', () {
    expect(
      () => GalleryConfig.fromJson({
        'urls': [
          {
            'url': 'https://example.com/gallery',
            'lookbackDays': 7,
            'minPosts': 4,
            'maxPosts': 3,
          },
        ],
      }),
      throwsFormatException,
    );
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

  test('gallery parses both card and gall_li board layouts', () async {
    const cardListHtml = '''
      <div class="card">
        <a class="img-card" href="/bbs/board.php?bo_table=gallery&amp;wr_id=7">
          <img src="/gallery-thumb.jpg">
        </a>
        <a class="bo_tit"
           href="/bbs/board.php?bo_table=gallery&amp;wr_id=7">
          <span class="ks4">Gallery post</span>
        </a>
        <span class="gall_date">2026-08-27</span>
      </div>
    ''';
    const gallLiListHtml = '''
      <ul id="gall_ul">
        <li class="gall_li col-gn-4">
          <div class="gall_box">
            <div class="gall_img">
              <a href="/bbs/board.php?bo_table=signage1&amp;wr_id=1">
                <img src="/signage-thumb.png">
              </a>
            </div>
            <div class="gall_text_href">
              <a class="bo_tit"
                 href="/bbs/board.php?bo_table=signage1&amp;wr_id=1">
                Signage post
                <span class="new_icon">N<span class="sound_only">new</span></span>
              </a>
            </div>
            <span class="gall_date">17:56</span>
          </div>
        </li>
      </ul>
    ''';
    final client = MockClient((request) async {
      if (request.url.queryParameters['bo_table'] == 'gallery' &&
          !request.url.queryParameters.containsKey('wr_id')) {
        return http.Response(cardListHtml, 200);
      }
      if (request.url.queryParameters['bo_table'] == 'signage1' &&
          !request.url.queryParameters.containsKey('wr_id')) {
        return http.Response(gallLiListHtml, 200);
      }
      final board = request.url.queryParameters['bo_table'];
      final extension = board == 'signage1' ? 'png' : 'jpg';
      return http.Response(
        '<div id="bo_v_con"><img src="/$board-original.$extension"></div>',
        200,
      );
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        urls: [
          'http://example.com/bbs/board.php?bo_table=gallery',
          'http://example.com/bbs/board.php?bo_table=signage1',
        ],
        maxPosts: 1,
        maxImages: 2,
      ),
    );

    expect(items.map((item) => item.title), [
      'Gallery post',
      'Signage post',
    ]);
    expect(items.map((item) => item.imageUrl), [
      'http://example.com/gallery-original.jpg',
      'http://example.com/signage1-original.png',
    ]);
    loader.close();
  });

  test('gallery parser supports the movie board card layout', () async {
    const listHtml = '''
      <div class="card">
        <a class="img-card"
           href="/bbs/board.php?bo_table=movie&amp;wr_id=18">
          <img src="/data/editor/movie-thumb.jpg">
        </a>
        <a class="bo_cate_link">[2020년대]</a>
        <a class="bo_tit"
           href="/bbs/board.php?bo_table=movie&amp;wr_id=18">
          <span class="ks4">여의도동성당 50년사</span>
        </a>
        <!-- movie 스킨은 목록 작성일을 주석 처리한다. -->
      </div>
    ''';
    const postHtml = '''
      <strong class="if_date">작성일 25-06-23 12:00</strong>
      <div id="bo_v_con">
        <img src="http://www.example.com/data/editor/movie-original.jpg">
      </div>
    ''';
    final client = MockClient((request) async {
      if (!request.url.queryParameters.containsKey('wr_id')) {
        return http.Response.bytes(
          utf8.encode(listHtml),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response.bytes(
        utf8.encode(postHtml),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        url: 'http://example.com/bbs/board.php?bo_table=movie',
        minPosts: 1,
        maxPosts: 1,
        maxImages: 1,
      ),
    );

    expect(items.single.title, '여의도동성당 50년사');
    expect(
      items.single.imageUrl,
      'http://www.example.com/data/editor/movie-original.jpg',
    );
    loader.close();
  });

  test('gallery extracts supported YouTube URL formats without duplicates', () {
    final ids = parsePostYoutubeVideoIds('''
      <div id="bo_v_con">
        <iframe src="https://www.youtube.com/embed/uYY2QToeaqc?si=test"></iframe>
        <a href="https://youtu.be/uYY2QToeaqc">duplicate</a>
        <a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ">watch</a>
        <a href="https://www.youtube.com/shorts/aqz-KE-bpKQ">short</a>
      </div>
    ''');

    expect(ids, ['uYY2QToeaqc', 'dQw4w9WgXcQ', 'aqz-KE-bpKQ']);
    expect(
      parseYoutubeVideoId(
        'https://youtu.be/uYY2QToeaqc?si=pFeRxJCuSY6nQA0',
      ),
      'uYY2QToeaqc',
    );
  });

  test('gallery uses an embedded YouTube video instead of its poster image',
      () async {
    const listHtml = '''
      <div class="card">
        <a class="img-card" href="/post/6"><img src="/poster.jpg"></a>
        <a class="bo_tit"><span class="ks4">Anniversary movie</span></a>
      </div>
    ''';
    const postHtml = '''
      <div id="bo_v_con">
        <iframe src="https://www.youtube.com/embed/uYY2QToeaqc"></iframe>
        <img src="/poster-original.jpg">
      </div>
    ''';
    final client = MockClient((request) async {
      return http.Response(
          request.url.path == '/gallery' ? listHtml : postHtml, 200);
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        url: 'http://example.com/gallery',
        maxPosts: 1,
        maxImages: 5,
      ),
    );

    expect(items, hasLength(1));
    expect(items.single.isYoutube, isTrue);
    expect(items.single.youtubeVideoId, 'uYY2QToeaqc');
    expect(
      items.single.imageUrl,
      'https://i.ytimg.com/vi/uYY2QToeaqc/hqdefault.jpg',
    );
    loader.close();
  });

  test('YouTube idle player requests audible autoplay and reports completion',
      () {
    final html = buildYoutubePlayerHtml('uYY2QToeaqc', loop: false);

    expect(html, contains('autoplay:1'));
    expect(html, contains('mute:0'));
    expect(html, contains('event.target.unMute()'));
    expect(html, contains('event.target.setVolume(100)'));
    expect(html, contains("notify('playing')"));
    expect(html, contains("notify('ended')"));
  });

  test('슬라이드와 웹 화면의 YouTube 주소는 전용 플레이어로 연결한다', () {
    final source = File('lib/widget/idle_overlay.dart').readAsStringSync();

    expect(source, contains('parseYoutubeVideoId(path)'));
    expect(source, contains('parseYoutubeVideoId(widget.url)'));
    expect(source, contains("key: ValueKey('idle-url-youtube:"));
    expect(buildYoutubePlayerHtml('uYY2QToeaqc', loop: true),
        contains('if(true)'));
  });

  test('gallery ignores posts whose normalized title starts with hash',
      () async {
    const listHtml = '''
      <div class="card">
        <a class="img-card" href="/post/hidden"><img src="/hidden.jpg"></a>
        <a class="bo_tit"><span class="ks4">   # Hidden post </span></a>
      </div>
      <li class="gall_li">
        <div class="gall_img">
          <a href="/post/visible"><img src="/visible.jpg"></a>
        </div>
        <a class="bo_tit" href="/post/visible">Visible post</a>
      </li>
    ''';
    final client = MockClient((request) async {
      if (request.url.path == '/gallery') {
        return http.Response(listHtml, 200);
      }
      return http.Response(
        '<div id="bo_v_con"><img src="/original.jpg"></div>',
        200,
      );
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        url: 'http://example.com/gallery',
        maxPosts: 2,
        maxImages: 2,
      ),
    );

    expect(items, hasLength(1));
    expect(items.single.title, 'Visible post');
    expect(items.single.postUrl, 'http://example.com/post/visible');
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

  test('each gallery board applies its own maximum post count', () async {
    String listHtml(String board) => List.generate(
          2,
          (index) => '''
      <div class="card">
        <a class="img-card" href="/$board-post-$index"><img src="/$board-thumb-$index.jpg"></a>
        <a class="bo_tit"><span class="ks4">$board ${index + 1}</span></a>
      </div>
    ''',
        ).join();
    final client = MockClient((request) async {
      if (request.url.path == '/gallery-a') {
        return http.Response(listHtml('A'), 200);
      }
      if (request.url.path == '/gallery-b') {
        return http.Response(listHtml('B'), 200);
      }
      if (request.url.path.contains('-post-')) {
        return http.Response(
          '<div id="bo_v_con"><img src="${request.url.path}.jpg"></div>',
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final loader = GalleryFeedLoader(client: client);

    final items = await loader.load(
      const GalleryConfig(
        sources: [
          GallerySourceConfig(
            url: 'http://example.com/gallery-a',
            minPosts: 1,
            maxPosts: 1,
          ),
          GallerySourceConfig(
            url: 'http://example.com/gallery-b',
            minPosts: 1,
            maxPosts: 2,
          ),
        ],
        maxImages: 3,
      ),
    );

    expect(items.map((item) => item.title), ['A 1', 'B 1', 'B 2']);
    loader.close();
  });

  test('툴바는 기본적으로 숨김이며 자동 숨김 시간을 파싱한다', () {
    expect(LayoutConfig.defaults.toolbarInitiallyHidden, isTrue);
    expect(LayoutConfig.defaults.toolbarAutoHideSec, 10);
    expect(LayoutConfig.defaults.keyboardMode, KeyboardMode.windows);
    expect(LayoutConfig.defaults.showSelectedTopic, isTrue);
    expect(
      LayoutConfig.defaults.selectedTopicLabelColor,
      const Color(0xFFF8FAFC),
    );
    expect(LayoutConfig.defaults.windowsKioskLockdown, isTrue);
    expect(LayoutConfig.defaults.windowsDisableEdgeSwipe, isTrue);
    expect(LayoutConfig.defaults.windowsKioskShortcuts.windowsKey, isTrue);
    expect(LayoutConfig.defaults.windowsKioskShortcuts.altTab, isTrue);
    expect(LayoutConfig.defaults.windowsAlwaysOnTop, isFalse);
    expect(LayoutConfig.defaults.windowsPreventScreenSaver, isTrue);
    expect(LayoutConfig.defaults.windowsPreventDisplaySleep, isTrue);
    expect(LayoutConfig.defaults.fontFamily, 'Pretendard');
    expect(LayoutConfig.defaults.sideWidth, 230);
    expect(LayoutConfig.defaults.barHeight, 102);
    expect(LayoutConfig.defaults.buttonGap, 10);
    expect(LayoutConfig.defaults.barColor, const Color(0xFF000000));
    expect(LayoutConfig.defaults.buttonColor, const Color(0xFF171717));
    expect(LayoutConfig.defaults.selectedButtonColor, const Color(0xFFFACC15));

    final config = LayoutConfig.fromJson({
      'fontFamily': ' Pretendard ',
      'menuFontFamily': ' NanumGothic ',
      'toolbarInitiallyHidden': false,
      'toolbarAutoHideSec': 25,
      'barColor': '#123456',
      'keyboardMode': 'builtin',
      'showSelectedTopic': false,
      'selectedTopicLabelColor': '#abcdef',
      'windowsKioskLockdown': false,
      'windowsDisableEdgeSwipe': false,
      'windowsKioskShortcuts': {
        'windowsKey': false,
        'altTab': false,
        'ctrlShiftEscape': false,
        'browserFavorites': false,
      },
      'windowsAlwaysOnTop': true,
      'windowsPreventScreenSaver': false,
      'windowsPreventDisplaySleep': false,
    });
    expect(config.toolbarInitiallyHidden, isFalse);
    expect(config.fontFamily, 'Pretendard');
    expect(config.menuFontFamily, 'NanumGothic');
    expect(config.toolbarAutoHideSec, 25);
    expect(config.barColor, const Color(0xFF123456));
    expect(config.keyboardMode, KeyboardMode.builtIn);
    expect(config.showSelectedTopic, isFalse);
    expect(config.selectedTopicLabelColor, const Color(0xFFABCDEF));
    expect(config.windowsKioskLockdown, isFalse);
    expect(config.windowsDisableEdgeSwipe, isFalse);
    expect(config.windowsKioskShortcuts.windowsKey, isFalse);
    expect(config.windowsKioskShortcuts.altTab, isFalse);
    expect(config.windowsKioskShortcuts.altF4, isTrue);
    expect(config.windowsKioskShortcuts.ctrlShiftEscape, isFalse);
    expect(config.windowsKioskShortcuts.browserFavorites, isFalse);
    expect(config.windowsAlwaysOnTop, isTrue);
    expect(config.windowsPreventScreenSaver, isFalse);
    expect(config.windowsPreventDisplaySleep, isFalse);
    expect(
      () => LayoutConfig.fromJson({'keyboardMode': 'unknown'}),
      throwsFormatException,
    );
  });

  test('패키지 글꼴 파일과 라이선스를 모두 포함한다', () {
    expect(
        FontResourceService.packagedFamilies,
        containsAll(const [
          'Pretendard',
          'NanumSquare',
          'NanumGothic',
          'NanumBrush',
          'KoPubDotum',
          'Catholic',
        ]));
    for (final path in const [
      'assets/fonts/pretendard/Pretendard-Regular.otf',
      'assets/fonts/nanum-square/NanumSquareR.otf',
      'assets/fonts/nanum-gothic/NanumGothic.otf',
      'assets/fonts/nanum-brush/NanumBrush.otf',
      'assets/fonts/kopub-dotum/KoPub Dotum Medium.ttf',
      'assets/fonts/catholic/Catholic.ttf',
      'assets/fonts/licenses/Pretendard-OFL-1.1.txt',
      'assets/fonts/licenses/Nanum-OFL-1.1.txt',
      'assets/fonts/licenses/KoPub-Dotum-LICENSE.txt',
      'assets/fonts/licenses/Catholic-LICENSE.txt',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('Windows 키오스크 잠금은 앱 전환과 셸 단축키를 차단한다', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('simple_kiosk/windows_kiosk_mode'));
    expect(source, contains('VK_LWIN'));
    expect(source, contains('VK_RWIN'));
    expect(source, contains('VK_TAB'));
    expect(source, contains('VK_ESCAPE'));
    expect(source, contains('VK_LAUNCH_APP1'));
    expect(source, contains('blockWindowsKey'));
    expect(source, contains('blockAltTab'));
    expect(source, contains('blockCtrlShiftEscape'));
    expect(source, contains('g_block_browser_favorites'));
    expect(source, contains('ArmEmergencyExit'));
    expect(source, contains('compare_exchange_strong'));
    expect(source, contains('g_emergency_exit_sequence'));
    expect(source, contains('FlutterViewTouchProc'));
    expect(source, contains('WM_POINTERDOWN'));
    expect(source, contains('WM_POINTERLEAVE'));
    expect(source, contains('POINTER_FLAG_INCONTACT'));
    expect(source, contains('kEdgeGestureDisableTouchWhenFullscreen'));
    expect(source, contains('SHGetPropertyStoreForWindow'));
    expect(source, contains('SetFullscreenEdgeGesturesDisabled'));
    expect(source, contains('g_active_touch_points'));
    expect(source, contains('8000'));
    expect(source, contains('RecoverRenderingSurface'));
    expect(source, contains('kSurfaceWatchdogTimerId'));
    expect(source, contains('TerminateProcess'));
    expect(source, contains('SetThreadExecutionState'));
    expect(source, contains('ES_DISPLAY_REQUIRED'));
    expect(source, contains('SC_SCREENSAVE'));
    expect(source, contains('preventDisplaySleep'));

    final windowSource =
        File('windows/runner/win32_window.cpp').readAsStringSync();
    expect(windowSource, contains('BLACK_BRUSH'));
  });

  test('Windows 시작과 숨김 복원은 렌더 표면을 실제 resize로 복구한다', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final nativeSource =
        File('windows/runner/flutter_window.cpp').readAsStringSync();
    final traySource =
        File('lib/service/kiosk_tray_controller.dart').readAsStringSync();

    expect(mainSource, contains('addPostFrameCallback'));
    expect(mainSource, contains('recoverRenderingSurface'));
    expect(nativeSource, contains('call.method_name() == "recoverSurface"'));
    expect(nativeSource, contains('width - 1'));
    expect(nativeSource, isNot(contains('this->Show();')));
    expect(traySource, contains('recoverRenderingSurface'));
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

  testWidgets('버전 오버레이는 툴바 방향에 맞춰 배치되고 입력을 통과시킨다', (tester) async {
    Future<Offset> pumpHost(NavPosition position) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolbarHost(
              hidden: false,
              position: position,
              sideWidth: 220,
              toolbarHeight: 96,
              webView: const ColoredBox(color: Colors.white),
              toolbar:
                  position == NavPosition.left || position == NavPosition.right
                      ? const SizedBox(width: 220)
                      : const SizedBox(height: 96),
              overlay: const SizedBox.shrink(),
              versionLabel: '1.2.32',
            ),
          ),
        ),
      );
      final version = find.byKey(const ValueKey('version-overlay'));
      expect(version, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VersionOverlay),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
      return tester.getBottomRight(version);
    }

    final bottomPosition = await pumpHost(NavPosition.bottom);
    expect(bottomPosition.dx, greaterThan(770));
    expect(bottomPosition.dy, lessThan(504));

    final topPosition = await pumpHost(NavPosition.top);
    expect(topPosition.dx, greaterThan(770));
    expect(topPosition.dy, greaterThan(570));
  });

  testWidgets('사이드 툴바 버전은 하단 기능 버튼 아래에 표시된다', (tester) async {
    Future<double> pumpMenu(String? versionLabel) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: NavigationMenu(
                items: const [],
                selectedIndex: 0,
                onSelected: (_) {},
                orientation: NavigationOrientation.side,
                sideWidth: 220,
                onHide: () {},
                versionLabel: versionLabel,
              ),
            ),
          ),
        ),
      );
      return tester.getBottomLeft(find.byTooltip('툴바 감추기')).dy;
    }

    final originalActionBottom = await pumpMenu(null);
    final actionBottom = await pumpMenu('1.2.32');

    final action = find.byTooltip('툴바 감추기');
    final version = find.byType(VersionOverlay);
    expect(action, findsOneWidget);
    expect(version, findsOneWidget);
    expect(tester.getTopLeft(version).dy,
        greaterThan(tester.getBottomLeft(action).dy));
    expect(originalActionBottom - actionBottom, lessThanOrEqualTo(10));
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

  testWidgets('툴바 시작 위치의 뒤로가기는 언어 선택으로 이동하고 주제 라벨은 읽기 전용이다', (tester) async {
    var languageSelectionCount = 0;
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
                showHistoryButtons: true,
                showKeyboardToggle: true,
                selectedTopicLabel: '여의도동 성당',
                selectedTopicLabelColor: const Color(0xFFABCDEF),
                onSelectLanguage: () => languageSelectionCount += 1,
              ),
            ),
          ),
        ),
      ),
    );

    final sideBackButton =
        find.byKey(const ValueKey('language-selection-back-button'));
    final sideLabel = find.byKey(const ValueKey('selected-topic-label'));
    expect(sideBackButton, findsOneWidget);
    expect(find.text('언어 선택으로 돌아가기'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(sideLabel, findsOneWidget);
    expect(
      find.ancestor(of: sideLabel, matching: find.byType(FilledButton)),
      findsNothing,
    );
    expect(
      tester.widget<Text>(sideLabel).style?.color,
      const Color(0xFFABCDEF),
    );
    expect(
      tester.getTopLeft(sideBackButton).dy,
      lessThan(tester.getTopLeft(sideLabel).dy),
    );
    expect(
      tester.getTopLeft(sideLabel).dy,
      lessThan(tester.getTopLeft(find.text('홈')).dy),
    );
    expect(
      tester.getTopLeft(find.text('홈')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('뒤로')).dy),
    );
    expect(
      tester.getCenter(find.byTooltip('뒤로')).dy,
      tester.getCenter(find.byTooltip('키보드 열기')).dy,
    );
    await tester.tap(sideLabel);
    await tester.pump();
    expect(languageSelectionCount, 0);
    await tester.tap(sideBackButton);
    await tester.pump();
    expect(languageSelectionCount, 1);

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
              showHistoryButtons: true,
              showKeyboardToggle: true,
              selectedTopicLabel: '여의도동 성당',
              onSelectLanguage: () => languageSelectionCount += 1,
            ),
          ),
        ),
      ),
    );

    final horizontalBackButton =
        find.byKey(const ValueKey('language-selection-back-button'));
    final horizontalLabel = find.byKey(const ValueKey('selected-topic-label'));
    expect(find.text('언어 선택'), findsOneWidget);
    expect(
      tester.getTopLeft(horizontalBackButton).dx,
      lessThan(tester.getTopLeft(horizontalLabel).dx),
    );
    expect(
      tester.getTopLeft(horizontalLabel).dx,
      lessThan(tester.getTopLeft(find.text('홈')).dx),
    );
    expect(
      tester.getTopLeft(find.text('홈')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('뒤로')).dx),
    );
    expect(
      tester.getTopLeft(find.byTooltip('앞으로')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('키보드 열기')).dx),
    );
    expect(tester.getSize(horizontalLabel).width, lessThanOrEqualTo(150));
    await tester.tap(horizontalLabel);
    await tester.pump();
    expect(languageSelectionCount, 1);
    await tester.tap(horizontalBackButton);
    await tester.pump();
    expect(languageSelectionCount, 2);
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
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    final languageButton = find.byTooltip('언어 선택으로 돌아가기');
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

  testWidgets('기능 버튼은 표시 개수와 툴바 크기에 맞춰 동일 크기로 정렬된다', (tester) async {
    Future<void> pumpSide(double width, {bool history = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: width,
                  height: 600,
                  child: NavigationMenu(
                    items: const [],
                    selectedIndex: 0,
                    onSelected: (_) {},
                    orientation: NavigationOrientation.side,
                    sideWidth: width,
                    showHistoryButtons: history,
                    showKeyboardToggle: true,
                    onOpenAdmin: () {},
                    onEnterIdle: () {},
                    onHide: () {},
                  ),
                ),
              ),
            ),
          ),
        );

    Finder button(String tooltip) => find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(ElevatedButton),
        );

    await pumpSide(220);
    final keyboard = button('키보드 열기');
    final settings = button('설정');
    final idle = button('화면 보호기 시작');
    final hide = button('툴바 감추기');
    final wideSize = tester.getSize(keyboard);

    expect(wideSize.width, inInclusiveRange(40, 60));
    expect(tester.getSize(settings), wideSize);
    expect(tester.getSize(idle), wideSize);
    expect(tester.getSize(hide), wideSize);
    expect(tester.getCenter(keyboard).dy, tester.getCenter(settings).dy);
    expect(tester.getCenter(keyboard).dy, tester.getCenter(idle).dy);
    expect(tester.getCenter(keyboard).dy, tester.getCenter(hide).dy);
    expect(wideSize.width, lessThan(56));

    await pumpSide(220, history: true);
    final historyBack = button('뒤로');
    final historyForward = button('앞으로');
    final keyboardWithHistory = button('키보드 열기');
    final settingsWithHistory = button('설정');
    final idleWithHistory = button('화면 보호기 시작');
    final hideWithHistory = button('툴바 감추기');
    expect(
      tester.getTopLeft(historyBack).dx,
      lessThan(tester.getTopLeft(historyForward).dx),
    );
    expect(
      tester.getTopLeft(historyForward).dx,
      lessThan(tester.getTopLeft(keyboardWithHistory).dx),
    );
    expect(
      tester.getCenter(historyBack).dy,
      tester.getCenter(keyboardWithHistory).dy,
    );
    expect(
      tester.getCenter(settingsWithHistory).dy,
      greaterThan(tester.getCenter(keyboardWithHistory).dy),
    );
    expect(
      tester.getCenter(settingsWithHistory).dy,
      tester.getCenter(idleWithHistory).dy,
    );
    expect(
      tester.getCenter(settingsWithHistory).dy,
      tester.getCenter(hideWithHistory).dy,
    );
    expect(tester.getSize(historyBack).width, inInclusiveRange(56, 60));

    await pumpSide(110);
    final narrowSize = tester.getSize(button('키보드 열기'));
    expect(narrowSize.width, inInclusiveRange(40, 60));
    expect(narrowSize.width, lessThan(wideSize.width));

    Future<void> pumpHorizontal(double width) => tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 600)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: width,
                    height: 96,
                    child: NavigationMenu(
                      items: const [],
                      selectedIndex: 0,
                      onSelected: (_) {},
                      orientation: NavigationOrientation.bottom,
                      showKeyboardToggle: true,
                      onOpenAdmin: () {},
                      onEnterIdle: () {},
                      onHide: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    await pumpHorizontal(360);
    final compactHorizontalSize = tester.getSize(button('키보드 열기'));
    expect(compactHorizontalSize.width, 40);
    expect(tester.getSize(button('설정')), compactHorizontalSize);
    expect(tester.getSize(button('화면 보호기 시작')), compactHorizontalSize);
    expect(tester.getSize(button('툴바 감추기')), compactHorizontalSize);

    await pumpHorizontal(760);
    final wideHorizontalSize = tester.getSize(button('키보드 열기'));
    expect(wideHorizontalSize.width, greaterThan(compactHorizontalSize.width));
    expect(wideHorizontalSize.width, lessThanOrEqualTo(60));
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
