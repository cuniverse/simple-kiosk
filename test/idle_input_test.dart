import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/idle_config.dart';
import 'package:simple_kiosk/widget/idle_gate.dart';
import 'package:simple_kiosk/widget/idle_overlay.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final mode in [IdleMode.slideshow, IdleMode.gallery]) {
      testWidgets('$mode wakes on $kind input', (tester) async {
        var wakeCount = 0;
        await tester.pumpWidget(MaterialApp(
          home: IdleGate(
            config: IdleConfig.fromJson({
              'enabled': true,
              'startOnLaunch': true,
              'modes': [mode.name],
              'slideshow': {
                'images': ['assets/icons/app_icon.png'],
              },
              'gallery': {'url': 'https://example.com/gallery'},
            }),
            onWake: () => wakeCount++,
            child: const Center(child: Text('Awake')),
          ),
        ));
        expect(find.byType(IdleOverlay), findsOneWidget);
        await tester.tapAt(const Offset(400, 300), kind: kind);
        await tester.pump();
        expect(wakeCount, 1);
        expect(find.byType(IdleOverlay), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
