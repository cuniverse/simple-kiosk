import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/screen_preview_service.dart';

void main() {
  test('설정 FPS 간격 안에서는 가장 최근 화면을 재사용한다', () async {
    var now = DateTime.utc(2026, 8, 29, 12);
    var captures = 0;
    final service = ScreenPreviewService(
      clock: () => now,
      frameCapturer: (_) async {
        captures++;
        return ScreenPreviewFrame(
          jpegBytes: Uint8List.fromList([captures]),
          width: 960,
          height: 540,
          capturedAt: now,
        );
      },
    );

    final first = await service.capture(maxFramesPerSecond: 2);
    now = now.add(const Duration(milliseconds: 499));
    final cached = await service.capture(maxFramesPerSecond: 2);
    now = now.add(const Duration(milliseconds: 1));
    final next = await service.capture(maxFramesPerSecond: 2);

    expect(captures, 2);
    expect(identical(first, cached), isTrue);
    expect(next.jpegBytes, [2]);
  });

  test('동시에 들어온 요청은 하나의 캡처 작업을 공유한다', () async {
    final completer = Completer<ScreenPreviewFrame>();
    var captures = 0;
    final service = ScreenPreviewService(frameCapturer: (_) {
      captures++;
      return completer.future;
    });

    final first = service.capture(maxFramesPerSecond: 5);
    final second = service.capture(maxFramesPerSecond: 5);
    completer.complete(
      ScreenPreviewFrame(
        jpegBytes: Uint8List.fromList([1]),
        width: 1,
        height: 1,
        capturedAt: DateTime.now(),
      ),
    );

    expect(identical(await first, await second), isTrue);
    expect(captures, 1);
  });

  test('FPS는 1~5 범위만 허용한다', () {
    final service = ScreenPreviewService(
        frameCapturer: (_) async => throw StateError('호출되면 안 됨'));

    expect(
      () => service.capture(maxFramesPerSecond: 0),
      throwsArgumentError,
    );
    expect(
      () => service.capture(maxFramesPerSecond: 6),
      throwsArgumentError,
    );
  });

  test('숨김 캡처가 준비되지 않으면 마지막 정상 화면과 숨김 상태를 유지한다', () async {
    var attempts = 0;
    final service = ScreenPreviewService(frameCapturer: (_) async {
      attempts++;
      if (attempts == 1) {
        return ScreenPreviewFrame(
          jpegBytes: Uint8List.fromList([1, 2, 3]),
          width: 1280,
          height: 720,
          capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );
      }
      throw const ScreenPreviewException(
        'frame-not-ready',
        '준비 중',
        windowState: ScreenPreviewWindowState.hidden,
      );
    });

    await service.capture(maxFramesPerSecond: 2);
    final hidden = await service.capture(maxFramesPerSecond: 2);

    expect(hidden.jpegBytes, [1, 2, 3]);
    expect(hidden.windowState, ScreenPreviewWindowState.hidden);
    expect(attempts, 2);
  });
}
