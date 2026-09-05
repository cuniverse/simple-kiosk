import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/screen_preview_service.dart';

void main() {
  testWidgets('드래그 입력 순서·소유권을 확인하고 연결이 끊기면 누름을 해제한다', (tester) async {
    final events = <(String, int, int)>[];
    final service = ScreenPreviewService(
      frameCapturer: (_) async => ScreenPreviewFrame(
        jpegBytes: Uint8List(0),
        width: 640,
        height: 360,
        capturedAt: DateTime.now(),
        target: const ScreenPreviewTarget(
            window: 1, left: -1920, top: 0, width: 1920, height: 1080),
      ),
      pointerSender: (_, x, y, phase) => events.add((phase, x, y)),
    );
    final frame = await service.capture(maxFramesPerSecond: 2);
    void send(String phase, int sequence,
            {String owner = 'admin',
            String id = 'drag-1',
            double x = 0.5,
            double y = 0.5}) =>
        service.pointer(
            owner: owner,
            gestureId: id,
            sequence: sequence,
            phase: phase,
            frameId: frame.id,
            x: x,
            y: y);
    send('down', 1);
    expect(events, [('down', -960, 540)]);
    expect(() => send('move', 2, owner: 'other'),
        throwsA(isA<ScreenPreviewException>()));
    send('cancel', 2, owner: 'other');
    expect(() => send('down', 1, id: 'other'),
        throwsA(isA<ScreenPreviewException>()));
    send('move', 2, x: 1, y: 1);
    expect(() => send('move', 2), throwsA(isA<ScreenPreviewException>()));
    send('up', 3, x: 0.75, y: 0.25);
    expect(
        events, [('down', -960, 540), ('move', -1, 1079), ('up', -480, 270)]);
    send('down', 1, id: 'drag-2');
    await tester.pump(const Duration(seconds: 2));
    send('move', 2, id: 'drag-2');
    await tester.pump(const Duration(seconds: 2));
    expect(events.last.$1, 'move');
    await tester.pump(const Duration(seconds: 1));
    expect(events.last.$1, 'cancel');
    expect(() => send('move', 3, id: 'drag-2'),
        throwsA(isA<ScreenPreviewException>()));
    // 정상 종료한 드래그의 타이머는 새 입력을 해제하면 안 된다.
    send('down', 1, id: 'drag-3');
    send('up', 2, id: 'drag-3');
    await tester.pump(const Duration(seconds: 3));
    expect(events.last.$1, 'up');
  });

  test('드래그 이동 실패 시 마우스를 해제하고 다음 입력을 허용한다', () async {
    final events = <String>[];
    final service = ScreenPreviewService(
      frameCapturer: (_) async => ScreenPreviewFrame(
        jpegBytes: Uint8List(0),
        width: 640,
        height: 360,
        capturedAt: DateTime.now(),
        target: const ScreenPreviewTarget(
            window: 1, left: 0, top: 0, width: 1920, height: 1080),
      ),
      pointerSender: (_, x, y, phase) {
        events.add(phase);
        if (phase == 'move') {
          throw const ScreenPreviewException('outside-signage', '창 이동');
        }
      },
    );
    final frame = await service.capture(maxFramesPerSecond: 2);
    void send(String phase, int sequence) => service.pointer(
        owner: 'admin',
        gestureId: 'drag',
        sequence: sequence,
        phase: phase,
        frameId: frame.id,
        x: 0.5,
        y: 0.5);
    send('down', 1);
    expect(() => send('move', 2), throwsA(isA<ScreenPreviewException>()));
    expect(events, ['down', 'move', 'cancel']);
    send('down', 1);
    service.cancelPointer(owner: 'admin');
    expect(events.last, 'cancel');
  });

  test('미리보기 좌표를 음수 위치의 실제 모니터에 매핑하고 오래된 프레임은 거부한다', () async {
    var now = DateTime.utc(2026, 9, 5);
    final clicks = <(int, int)>[];
    const target = ScreenPreviewTarget(
        window: 1, left: -1920, top: -200, width: 1920, height: 1080);
    final service = ScreenPreviewService(
      clock: () => now,
      frameCapturer: (_) async => ScreenPreviewFrame(
        jpegBytes: Uint8List(0),
        width: 640,
        height: 360,
        capturedAt: now,
        target: target,
      ),
      clicker: (_, x, y) async => clicks.add((x, y)),
    );
    final first = await service.capture(maxFramesPerSecond: 2);
    now = now.add(const Duration(seconds: 1));
    await service.capture(maxFramesPerSecond: 2);
    // 다음 프레임이 캡처되어도 브라우저에 아직 표시된 프레임을 사용할 수 있다.
    await service.click(frameId: first.id, x: 0.5, y: 0.5);
    await service.click(frameId: first.id, x: 1, y: 1);
    await service.click(frameId: first.id, x: 0, y: 0);
    expect(clicks, [(-960, 340), (-1, 879), (-1920, -200)]);
    for (final x in [-0.1, 1.1, double.nan, double.infinity]) {
      await expectLater(service.click(frameId: first.id, x: x, y: 0),
          throwsA(isA<ScreenPreviewException>()));
    }
    await expectLater(service.click(frameId: 'unknown', x: 0, y: 0),
        throwsA(isA<ScreenPreviewException>()));
    now = now.add(const Duration(seconds: 5));
    await expectLater(service.click(frameId: first.id, x: 0, y: 0),
        throwsA(isA<ScreenPreviewException>()));
    expect(clicks.length, 3);
  });

  test('숨김·최소화 화면은 클릭할 수 없다', () async {
    for (final state in [
      ScreenPreviewWindowState.hidden,
      ScreenPreviewWindowState.minimized
    ]) {
      final service = ScreenPreviewService(
        frameCapturer: (_) async => ScreenPreviewFrame(
          jpegBytes: Uint8List(0),
          width: 640,
          height: 360,
          capturedAt: DateTime.now(),
          windowState: state,
          target: const ScreenPreviewTarget(
              window: 1, left: 0, top: 0, width: 1920, height: 1080),
        ),
        clicker: (_, x, y) async => fail('숨김 화면에 입력을 전달하면 안 됨'),
      );
      final frame = await service.capture(maxFramesPerSecond: 2);
      await expectLater(service.click(frameId: frame.id, x: 0.5, y: 0.5),
          throwsA(isA<ScreenPreviewException>()));
    }
  });

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
    expect(hidden.target, isNull);
    expect(attempts, 2);
  });
}
