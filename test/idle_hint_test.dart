import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/idle_config.dart';
import 'package:simple_kiosk/widget/idle_overlay.dart';

void main() {
  test(
      'hint settings accept color picker formats and reject invalid dimensions',
      () {
    final defaults = IdleConfig.fromJson({});
    expect(defaults.hintFontSize, 40);
    expect(defaults.hintBackgroundColor, const Color(0xFFFACC15));
    final custom = IdleConfig.fromJson({
      'hintBackgroundColor': '#fc0',
      'hintTextColor': '#80171717',
      'hintFontSize': 56,
      'hintPaddingVertical': 0,
    });
    expect(custom.hintBackgroundColor, const Color(0xFFFFCC00));
    expect(custom.hintTextColor, const Color(0x80171717));
    for (final invalid in [
      {'hintFontSize': 0},
      {'hintFontSize': double.nan},
      {'hintPaddingHorizontal': -1},
      {'hintPaddingVertical': 121},
      {'hintBackgroundColor': '#invalid'},
    ]) {
      expect(() => IdleConfig.fromJson(invalid), throwsFormatException);
    }
  });

  testWidgets(
      'hint applies changed size and colors and still dismisses on touch',
      (tester) async {
    var dismissed = 0;
    Future<void> show(Map<String, dynamic> values) =>
        tester.pumpWidget(MaterialApp(
          home: IdleOverlay(
              config: IdleConfig.fromJson(values),
              onDismiss: () => dismissed++),
        ));
    await show({});
    final initialTextSize = tester.getSize(find.text('화면을 터치해 주세요'));
    await show({
      'hintFontSize': 56,
      'hintPaddingHorizontal': 60,
      'hintPaddingVertical': 32,
      'hintBackgroundColor': '#FFD54F',
      'hintTextColor': '#112233'
    });
    final text = tester.widget<Text>(find.text('화면을 터치해 주세요'));
    expect(text.style!.fontSize, 56);
    expect(text.style!.color, const Color(0xFF112233));
    expect(tester.getSize(find.text('화면을 터치해 주세요')).height,
        greaterThan(initialTextSize.height));
    final badge = tester
        .widgetList<Container>(find.byType(Container))
        .singleWhere((widget) => widget.decoration is BoxDecoration);
    expect((badge.decoration as BoxDecoration).color, const Color(0xFFFFD54F));
    expect(badge.padding,
        const EdgeInsets.symmetric(horizontal: 60, vertical: 32));
    await tester.tapAt(tester.getCenter(find.text('화면을 터치해 주세요')));
    expect(dismissed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('large hint fits a narrow screen without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: IdleOverlay(
      config: IdleConfig.fromJson(
          {'hintFontSize': 96, 'hintPaddingHorizontal': 120}),
      onDismiss: () {},
    )));
    final fitted = tester.getRect(find.byType(FittedBox));
    expect(fitted.left, greaterThanOrEqualTo(24));
    expect(fitted.right, lessThanOrEqualTo(296));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
