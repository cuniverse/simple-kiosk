import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';
import 'package:simple_kiosk/service/windows_touch_input.dart';

void main() {
  test('drag uses touch and updates final coordinates before release', () {
    var initializations = 0;
    final frames = <(int, int, int)>[];
    final input = WindowsTouchInput(
      initialize: (count, feedback) {
        expect(count, 1);
        expect(feedback, 3);
        initializations++;
        return 1;
      },
      inject: (count, contacts) {
        expect(count, 1);
        final contact = contacts.ref;
        expect(contact.pointerInfo.pointerType, PT_TOUCH);
        expect(contact.pointerInfo.pointerId, 1);
        expect(contact.pressure, inInclusiveRange(0, 1024));
        expect(contact.rcContact.right - contact.rcContact.left, 4);
        frames.add((
          contact.pointerInfo.pointerFlags,
          contact.pointerInfo.ptPixelLocation.x,
          contact.pointerInfo.ptPixelLocation.y
        ));
        return 1;
      },
    );
    input.send(-900, 100, 'down');
    input.send(-900, 200, 'move');
    input.send(-800, 250, 'up');
    expect(frames.map((frame) => frame.$1), [
      POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT,
      POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT,
      POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT,
      POINTER_FLAG_UP,
    ]);
    expect((frames[2].$2, frames[2].$3), (-800, 250));
    expect((frames[3].$2, frames[3].$3), (-800, 250));
    input.send(0, 0, 'cancel');
    expect(frames.length, 4);
    input.send(10, 10, 'down');
    input.send(10, 10, 'up');
    expect(initializations, 1);
  });

  test('cancel after a failed move uses the last accepted touch location', () {
    final frames = <(int, int, int)>[];
    var failMove = false;
    final input = WindowsTouchInput(
        initialize: (_, __) => 1,
        lastError: () => ERROR_ACCESS_DENIED,
        inject: (_, contacts) {
          final info = contacts.ref.pointerInfo;
          if (failMove && (info.pointerFlags & POINTER_FLAG_UPDATE) != 0) {
            return 0;
          }
          frames.add((
            info.pointerFlags,
            info.ptPixelLocation.x,
            info.ptPixelLocation.y
          ));
          return 1;
        });
    input.send(100, 200, 'down');
    failMove = true;
    expect(() => input.send(900, 900, 'move'),
        throwsA(isA<WindowsTouchInputException>()));
    input.send(900, 900, 'cancel');
    expect(frames.last, (POINTER_FLAG_UP | POINTER_FLAG_CANCELED, 100, 200));
    expect(() => input.send(100, 200, 'move'),
        throwsA(isA<WindowsTouchInputException>()));
    input.send(10, 10, 'down');
    input.send(10, 10, 'cancel');
  });

  test('ERROR_NOT_READY retries the same frame and preserves touch release',
      () {
    var attempts = 0;
    var delays = 0;
    final accepted = <int>[];
    final input = WindowsTouchInput(
        initialize: (_, __) => 1,
        lastError: () => ERROR_NOT_READY,
        waitBeforeRetry: () => delays++,
        inject: (_, contacts) {
          attempts++;
          if (attempts.isOdd) return 0;
          accepted.add(contacts.ref.pointerInfo.pointerFlags);
          return 1;
        });
    input.send(10, 10, 'down');
    input.send(10, 10, 'up');
    expect(accepted.length, 3);
    expect(accepted.last, POINTER_FLAG_UP);
    expect(delays, 3);
    expect(attempts, 6);
  });

  test('initialization failure sends no contact and permits retry', () {
    var initialized = false;
    var frames = 0;
    final input = WindowsTouchInput(
        initialize: (_, __) => initialized ? 1 : 0,
        lastError: () => ERROR_ACCESS_DENIED,
        inject: (_, __) {
          frames++;
          return 1;
        });
    expect(() => input.send(10, 10, 'down'),
        throwsA(isA<WindowsTouchInputException>()));
    expect(frames, 0);
    initialized = true;
    input.send(10, 10, 'down');
    input.send(10, 10, 'cancel');
    expect(frames, 2);
  });
}
