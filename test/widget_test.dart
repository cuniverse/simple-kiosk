import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/idle_config.dart';
import 'package:simple_kiosk/model/layout_config.dart';
import 'package:simple_kiosk/widget/navigation_menu.dart';

void main() {
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
