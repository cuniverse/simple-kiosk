import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simple_kiosk/model/idle_config.dart';
import 'package:simple_kiosk/model/layout_config.dart';
import 'package:simple_kiosk/model/update_manifest.dart';
import 'package:simple_kiosk/model/update_policy.dart';
import 'package:simple_kiosk/service/gallery_feed_loader.dart';
import 'package:simple_kiosk/service/menu_config_merger.dart';
import 'package:simple_kiosk/widget/idle_overlay.dart';
import 'package:simple_kiosk/widget/navigation_menu.dart';

void main() {
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

    final config = LayoutConfig.fromJson({
      'toolbarInitiallyHidden': false,
      'toolbarAutoHideSec': 25,
    });
    expect(config.toolbarInitiallyHidden, isFalse);
    expect(config.toolbarAutoHideSec, 25);
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
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
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

    final restoreIcon = find.byIcon(Icons.keyboard_arrow_up);
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
            body: BottomToolbarHost(
              hidden: hidden,
              toolbarHeight: 96,
              webView: _LifecycleProbe(key: probeKey),
              toolbar: const SizedBox(height: 96),
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
          body: BottomToolbarHost(
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
