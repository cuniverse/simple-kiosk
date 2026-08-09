import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/idle_config.dart';
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
}
