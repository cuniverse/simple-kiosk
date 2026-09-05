import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

typedef TouchInitializer = int Function(int maxCount, int feedback);
typedef TouchInjector = int Function(
    int count, Pointer<POINTER_TOUCH_INFO> contacts);

class WindowsTouchInputException implements Exception {
  final String message;
  const WindowsTouchInputException(this.message);
}

/// One injected finger, using physical desktop coordinates.
/// https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-injecttouchinput
class WindowsTouchInput {
  WindowsTouchInput(
      {TouchInitializer? initialize,
      TouchInjector? inject,
      int Function()? lastError,
      void Function()? waitBeforeRetry})
      : _initialize = initialize ?? _nativeInitialize,
        _inject = inject ?? _nativeInject,
        _lastError = lastError ?? GetLastError,
        _waitBeforeRetry = waitBeforeRetry ?? (() => Sleep(1));

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _nativeInitialize =
      _user32.lookupFunction<Int32 Function(Uint32, Uint32), TouchInitializer>(
          'InitializeTouchInjection');
  static final _nativeInject = _user32.lookupFunction<
      Int32 Function(Uint32, Pointer<POINTER_TOUCH_INFO>),
      TouchInjector>('InjectTouchInput');
  final TouchInitializer _initialize;
  final TouchInjector _inject;
  final int Function() _lastError;
  final void Function() _waitBeforeRetry;
  bool _initialized = false;
  bool _active = false;
  int _x = 0;
  int _y = 0;

  void send(int x, int y, String phase) {
    if (phase == 'cancel') {
      if (!_active) return;
      try {
        _emit(_x, _y, POINTER_FLAG_UP | POINTER_FLAG_CANCELED);
      } finally {
        _active = false;
      }
      return;
    }
    if (!['down', 'move', 'up'].contains(phase)) {
      throw ArgumentError.value(phase, 'phase');
    }
    if (!_initialized) {
      // TOUCH_FEEDBACK_NONE = 3; only one contact is needed.
      if (_initialize(1, 3) == 0) {
        throw WindowsTouchInputException(
            'Windows 터치 입력을 초기화하지 못했습니다. (${_lastError()})');
      }
      _initialized = true;
    }
    if (phase == 'down') {
      if (_active) throw const WindowsTouchInputException('이전 터치 입력이 진행 중입니다.');
      _emit(x, y,
          POINTER_FLAG_DOWN | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT);
      _active = true;
    } else {
      if (!_active) {
        throw const WindowsTouchInputException('터치 입력이 이미 종료되었습니다.');
      }
      // UP must use the coordinates of the preceding UPDATE, including when
      // the browser coalesced the last move into its pointer-up request.
      _emit(x, y,
          POINTER_FLAG_UPDATE | POINTER_FLAG_INRANGE | POINTER_FLAG_INCONTACT);
      _x = x;
      _y = y;
      if (phase == 'up') {
        _emit(x, y, POINTER_FLAG_UP);
        _active = false;
      }
    }
    _x = x;
    _y = y;
  }

  void _emit(int x, int y, int flags) {
    final contact = calloc<POINTER_TOUCH_INFO>();
    try {
      contact.ref.pointerInfo
        ..pointerType = PT_TOUCH
        ..pointerId = 1
        ..pointerFlags = flags;
      contact.ref.pointerInfo.ptPixelLocation
        ..x = x
        ..y = y;
      contact.ref
        ..touchMask = 0x1 | 0x4 // TOUCH_MASK_CONTACTAREA | TOUCH_MASK_PRESSURE
        ..pressure = 512;
      contact.ref.rcContact
        ..left = x - 2
        ..top = y - 2
        ..right = x + 2
        ..bottom = y + 2;
      for (var attempt = 0;; attempt++) {
        if (_inject(1, contact) != 0) return;
        final error = _lastError();
        // Windows may reject two frames less than 0.1 ms apart. Retry the
        // same frame instead of losing the final release or changing flags.
        if (error != ERROR_NOT_READY || attempt >= 3) {
          throw WindowsTouchInputException(
              'Windows에 터치 입력을 전달하지 못했습니다. ($error)');
        }
        _waitBeforeRetry();
      }
    } finally {
      calloc.free(contact);
    }
  }
}
