import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as image;
import 'package:win32/win32.dart';

class ScreenPreviewFrame {
  final Uint8List jpegBytes;
  final int width;
  final int height;
  final DateTime capturedAt;
  final ScreenPreviewWindowState windowState;
  final ScreenPreviewTarget? target;

  String get id => capturedAt.microsecondsSinceEpoch.toString();

  const ScreenPreviewFrame({
    required this.jpegBytes,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.windowState = ScreenPreviewWindowState.visible,
    this.target,
  });
}

/// 캡처 당시의 모니터 물리 좌표. 클라이언트가 임의로 지정할 수 없다.
class ScreenPreviewTarget {
  final int window;
  final int left;
  final int top;
  final int width;
  final int height;

  const ScreenPreviewTarget({
    required this.window,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

typedef ScreenPreviewClicker = Future<void> Function(
  ScreenPreviewTarget target,
  int x,
  int y,
);

typedef ScreenPreviewPointerSender = void Function(
  ScreenPreviewTarget target,
  int x,
  int y,
  String phase,
);

class _PreviewDrag {
  final String owner;
  final String id;
  final ScreenPreviewTarget target;
  final DateTime startedAt;
  int sequence;
  int x;
  int y;
  _PreviewDrag(this.owner, this.id, this.target, this.startedAt, this.sequence,
      this.x, this.y);
}

enum ScreenPreviewWindowState { visible, hidden, minimized }

class ScreenPreviewCaptureOptions {
  final int maximumWidth;
  final int jpegQuality;

  const ScreenPreviewCaptureOptions({
    required this.maximumWidth,
    required this.jpegQuality,
  });
}

class ScreenPreviewException implements Exception {
  final String code;
  final String message;
  final ScreenPreviewWindowState? windowState;

  const ScreenPreviewException(this.code, this.message, {this.windowState});

  @override
  String toString() => message;
}

typedef ScreenFrameCapturer = Future<ScreenPreviewFrame> Function(
  ScreenPreviewCaptureOptions options,
);
typedef ScreenPreviewClock = DateTime Function();

/// Captures the Windows desktop monitor that contains the signage window and
/// returns a low-bandwidth JPEG frame. This keeps showing the real desktop when
/// the signage window is hidden. Concurrent viewers share capture work.
class ScreenPreviewService {
  ScreenPreviewService({
    ScreenFrameCapturer? frameCapturer,
    ScreenPreviewClock? clock,
    ScreenPreviewClicker? clicker,
    ScreenPreviewPointerSender? pointerSender,
  })  : _frameCapturer = frameCapturer ?? _captureWindowsFrame,
        _clicker = clicker ?? _clickWindowsScreen,
        _pointerSender = pointerSender ?? _pointerWindowsScreen,
        _clock = clock ?? DateTime.now;

  final ScreenFrameCapturer _frameCapturer;
  final ScreenPreviewClock _clock;
  final ScreenPreviewClicker _clicker;
  final ScreenPreviewPointerSender _pointerSender;
  _PreviewDrag? _drag;
  Timer? _dragTimeout;
  final Map<String, ({ScreenPreviewTarget target, DateTime capturedAt})>
      _clickTargets = {};
  bool _clickBusy = false;
  ScreenPreviewFrame? _cachedFrame;
  Future<ScreenPreviewFrame>? _inFlight;

  Future<ScreenPreviewFrame> capture({
    required int maxFramesPerSecond,
    int maximumWidth = 1280,
    int jpegQuality = 45,
  }) {
    if (maxFramesPerSecond < 1 || maxFramesPerSecond > 5) {
      throw ArgumentError.value(
        maxFramesPerSecond,
        'maxFramesPerSecond',
        '1~5 범위여야 합니다.',
      );
    }
    if (maximumWidth < 640 || maximumWidth > 1920) {
      throw ArgumentError.value(
          maximumWidth, 'maximumWidth', '640~1920 범위여야 합니다.');
    }
    if (jpegQuality < 20 || jpegQuality > 80) {
      throw ArgumentError.value(jpegQuality, 'jpegQuality', '20~80 범위여야 합니다.');
    }
    final cached = _cachedFrame;
    final minimumInterval = Duration(
      microseconds: Duration.microsecondsPerSecond ~/ maxFramesPerSecond,
    );
    if (cached != null &&
        _clock().difference(cached.capturedAt) < minimumInterval) {
      return Future.value(cached);
    }
    final running = _inFlight;
    if (running != null) return running;

    late final Future<ScreenPreviewFrame> operation;
    operation = _frameCapturer(
      ScreenPreviewCaptureOptions(
        maximumWidth: maximumWidth,
        jpegQuality: jpegQuality,
      ),
    ).then((frame) {
      _cachedFrame = frame;
      if (frame.target != null &&
          frame.windowState == ScreenPreviewWindowState.visible) {
        _clickTargets[frame.id] = (
          target: frame.target!,
          capturedAt: frame.capturedAt,
        );
        while (_clickTargets.length > 32) {
          _clickTargets.remove(_clickTargets.keys.first);
        }
      }
      return frame;
    }).onError((error, stackTrace) {
      final cached = _cachedFrame;
      if (cached != null &&
          error is ScreenPreviewException &&
          (error.code == 'frame-not-ready' || error.code == 'capture-failed')) {
        return ScreenPreviewFrame(
          jpegBytes: cached.jpegBytes,
          width: cached.width,
          height: cached.height,
          capturedAt: _clock(),
          windowState: error.windowState ?? cached.windowState,
        );
      }
      Error.throwWithStackTrace(
        error ?? StateError('화면 캡처에 실패했습니다.'),
        stackTrace,
      );
    }).whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<void> click(
      {required String frameId, required double x, required double y}) async {
    if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
      throw const ScreenPreviewException(
          'invalid-coordinates', '클릭 좌표가 올바르지 않습니다.');
    }
    final frame = _clickTargets[frameId];
    if (frame == null ||
        _clock().difference(frame.capturedAt) > const Duration(seconds: 5)) {
      throw const ScreenPreviewException(
          'stale-frame', '미리보기를 갱신한 뒤 다시 클릭해 주세요.');
    }
    if (_clickBusy || _drag != null) {
      throw const ScreenPreviewException('click-busy', '이전 클릭을 처리 중입니다.');
    }
    _clickBusy = true;
    try {
      final target = frame.target;
      await _clicker(
          target,
          target.left + (x * target.width).floor().clamp(0, target.width - 1),
          target.top + (y * target.height).floor().clamp(0, target.height - 1));
      _cachedFrame = null;
    } finally {
      _clickBusy = false;
    }
  }

  void pointer(
      {required String owner,
      required String gestureId,
      required int sequence,
      required String phase,
      required String frameId,
      required double x,
      required double y}) {
    if (!['down', 'move', 'up', 'cancel'].contains(phase) ||
        gestureId.isEmpty ||
        gestureId.length > 80 ||
        sequence < 0 ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1) {
      throw const ScreenPreviewException(
          'invalid-pointer', '드래그 입력이 올바르지 않습니다.');
    }
    if (phase == 'down') {
      if (_clickBusy || _drag != null) {
        throw const ScreenPreviewException('click-busy', '다른 입력을 처리 중입니다.');
      }
      final frame = _clickTargets[frameId];
      if (frame == null ||
          _clock().difference(frame.capturedAt) > const Duration(seconds: 5)) {
        throw const ScreenPreviewException(
            'stale-frame', '미리보기를 갱신한 뒤 다시 시도해 주세요.');
      }
      final target = frame.target;
      _drag = _PreviewDrag(
          owner,
          gestureId,
          target,
          _clock(),
          sequence,
          target.left + (x * target.width).floor().clamp(0, target.width - 1),
          target.top + (y * target.height).floor().clamp(0, target.height - 1));
    } else {
      final drag = _drag;
      if (drag == null || drag.owner != owner || drag.id != gestureId) {
        if (phase == 'cancel') return;
        throw const ScreenPreviewException(
            'drag-ended', '드래그가 종료되었습니다. 다시 눌러 주세요.');
      }
      if (sequence <= drag.sequence) {
        throw const ScreenPreviewException('out-of-order', '이전 드래그 입력입니다.');
      }
      drag.sequence = sequence;
      drag.x = drag.target.left +
          (x * drag.target.width).floor().clamp(0, drag.target.width - 1);
      drag.y = drag.target.top +
          (y * drag.target.height).floor().clamp(0, drag.target.height - 1);
    }
    final drag = _drag!;
    try {
      if (_clock().difference(drag.startedAt) > const Duration(seconds: 60)) {
        throw const ScreenPreviewException('drag-ended', '드래그 제한 시간이 지났습니다.');
      }
      _pointerSender(drag.target, drag.x, drag.y, phase);
      _cachedFrame = null;
      _dragTimeout?.cancel();
      if (phase == 'up' || phase == 'cancel') {
        _drag = null;
      } else {
        _dragTimeout = Timer(const Duration(seconds: 3), () {
          try {
            cancelPointer();
          } catch (_) {/* 다음 입력 요청에 영향을 주지 않는다. */}
        });
      }
    } catch (_) {
      try {
        cancelPointer();
      } catch (_) {/* 원래 입력 오류를 반환한다. */}
      rethrow;
    }
  }

  void cancelPointer({String? owner}) {
    final drag = _drag;
    if (drag == null || (owner != null && drag.owner != owner)) return;
    _dragTimeout?.cancel();
    _drag = null;
    _pointerSender(drag.target, drag.x, drag.y, 'cancel');
  }

  static Future<ScreenPreviewFrame> _captureWindowsFrame(
    ScreenPreviewCaptureOptions options,
  ) {
    if (!Platform.isWindows) {
      throw const ScreenPreviewException(
        'unsupported',
        '화면 미리보기는 Windows에서만 지원합니다.',
      );
    }
    return Isolate.run(
      () => _captureWindowsFrameSync(options.maximumWidth, options.jpegQuality),
    );
  }
}

ScreenPreviewFrame _captureWindowsFrameSync(int maximumWidth, int jpegQuality) {
  final rect = calloc<RECT>();
  final monitorInfo = calloc<MONITORINFO>();
  final bitmapInfo = calloc<BITMAPINFO>();
  int screenDc = 0;
  int memoryDc = 0;
  int bitmap = 0;
  int previousObject = 0;
  try {
    final window = _findCurrentProcessTopLevelWindow(rect);
    if (window == 0) {
      throw const ScreenPreviewException(
        'window-not-found',
        '사이니지 창을 찾을 수 없습니다.',
      );
    }
    final windowState = IsIconic(window) != 0
        ? ScreenPreviewWindowState.minimized
        : IsWindowVisible(window) == 0
            ? ScreenPreviewWindowState.hidden
            : ScreenPreviewWindowState.visible;
    final monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    monitorInfo.ref.cbSize = sizeOf<MONITORINFO>();
    if (monitor == 0 || GetMonitorInfo(monitor, monitorInfo) == 0) {
      throw const ScreenPreviewException(
        'capture-failed',
        '사이니지가 표시되는 모니터를 확인할 수 없습니다.',
      );
    }
    final sourceLeft = monitorInfo.ref.rcMonitor.left;
    final sourceTop = monitorInfo.ref.rcMonitor.top;
    final sourceWidth = monitorInfo.ref.rcMonitor.right - sourceLeft;
    final sourceHeight = monitorInfo.ref.rcMonitor.bottom - sourceTop;
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw const ScreenPreviewException(
        'capture-failed',
        '사이니지 화면 크기가 올바르지 않습니다.',
      );
    }

    screenDc = GetDC(0);
    if (screenDc == 0) {
      throw const ScreenPreviewException(
        'capture-failed',
        'Windows 화면 캡처를 시작할 수 없습니다.',
      );
    }
    memoryDc = CreateCompatibleDC(screenDc);
    bitmap = CreateCompatibleBitmap(screenDc, sourceWidth, sourceHeight);
    if (memoryDc == 0 || bitmap == 0) {
      throw const ScreenPreviewException(
        'capture-failed',
        'Windows 화면 버퍼를 만들 수 없습니다.',
      );
    }
    previousObject = SelectObject(memoryDc, bitmap);
    final captured = BitBlt(
      memoryDc,
      0,
      0,
      sourceWidth,
      sourceHeight,
      screenDc,
      sourceLeft,
      sourceTop,
      SRCCOPY | CAPTUREBLT,
    );
    if (previousObject == 0 || previousObject == -1 || captured == 0) {
      throw ScreenPreviewException(
        'capture-failed',
        'Windows 화면을 캡처하지 못했습니다.',
        windowState: windowState,
      );
    }

    // GetDIBits 계약상 대상 비트맵은 DC에 선택되어 있으면 안 된다.
    // BitBlt가 끝난 즉시 원래 객체를 복원한 뒤 픽셀을 읽는다.
    final selectedBitmap = SelectObject(memoryDc, previousObject);
    if (selectedBitmap == 0 || selectedBitmap == -1) {
      throw ScreenPreviewException(
        'capture-failed',
        'Windows 화면 버퍼를 읽기 상태로 전환하지 못했습니다.',
        windowState: windowState,
      );
    }
    previousObject = 0;

    bitmapInfo.ref.bmiHeader
      ..biSize = sizeOf<BITMAPINFOHEADER>()
      ..biWidth = sourceWidth
      ..biHeight = -sourceHeight
      ..biPlanes = 1
      ..biBitCount = 32
      ..biCompression = BI_RGB
      ..biSizeImage = sourceWidth * sourceHeight * 4;
    final pixelCount = sourceWidth * sourceHeight * 4;
    final pixels = calloc<Uint8>(pixelCount);
    try {
      if (GetDIBits(
            memoryDc,
            bitmap,
            0,
            sourceHeight,
            pixels,
            bitmapInfo,
            DIB_RGB_COLORS,
          ) ==
          0) {
        throw const ScreenPreviewException(
          'capture-failed',
          '캡처한 화면 데이터를 읽지 못했습니다.',
        );
      }
      final source = image.Image.fromBytes(
        width: sourceWidth,
        height: sourceHeight,
        bytes: Uint8List.fromList(pixels.asTypedList(pixelCount)).buffer,
        order: image.ChannelOrder.bgra,
      );
      if (windowState == ScreenPreviewWindowState.visible &&
          _isNearlyBlackFrame(pixels.asTypedList(pixelCount))) {
        throw ScreenPreviewException(
          'frame-not-ready',
          '사이니지 첫 화면을 준비하고 있습니다.',
          windowState: windowState,
        );
      }
      final preview = sourceWidth > maximumWidth
          ? image.copyResize(
              source,
              width: maximumWidth,
              interpolation: image.Interpolation.linear,
            )
          : source;
      return ScreenPreviewFrame(
        jpegBytes: image.encodeJpg(preview, quality: jpegQuality),
        width: preview.width,
        height: preview.height,
        capturedAt: DateTime.now(),
        windowState: windowState,
        target: ScreenPreviewTarget(
          window: window,
          left: sourceLeft,
          top: sourceTop,
          width: sourceWidth,
          height: sourceHeight,
        ),
      );
    } finally {
      calloc.free(pixels);
    }
  } finally {
    if (previousObject != 0 && memoryDc != 0) {
      SelectObject(memoryDc, previousObject);
    }
    if (bitmap != 0) DeleteObject(bitmap);
    if (memoryDc != 0) DeleteDC(memoryDc);
    if (screenDc != 0) ReleaseDC(0, screenDc);
    calloc.free(bitmapInfo);
    calloc.free(monitorInfo);
    calloc.free(rect);
  }
}

Future<void> _clickWindowsScreen(
    ScreenPreviewTarget target, int x, int y) async {
  _pointerWindowsScreen(target, x, y, 'click');
}

void _pointerWindowsScreen(
    ScreenPreviewTarget target, int x, int y, String phase) {
  if (!Platform.isWindows) {
    throw const ScreenPreviewException(
        'unsupported', '원격 클릭은 Windows에서만 지원합니다.');
  }
  final monitorInfo = calloc<MONITORINFO>();
  final point = calloc<POINT>();
  final processId = calloc<Uint32>();
  final inputs = calloc<INPUT>(3);
  try {
    if (phase == 'cancel') {
      inputs[0].type = INPUT_MOUSE;
      inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;
      if (SendInput(1, inputs, sizeOf<INPUT>()) != 1) {
        throw const ScreenPreviewException(
            'input-failed', '마우스 누름을 해제하지 못했습니다.');
      }
      return;
    }
    GetWindowThreadProcessId(target.window, processId);
    if (processId.value != GetCurrentProcessId() ||
        IsWindowVisible(target.window) == 0 ||
        IsIconic(target.window) != 0) {
      throw const ScreenPreviewException(
          'signage-not-visible', '사이니지가 표시 중일 때만 클릭할 수 있습니다.');
    }
    monitorInfo.ref.cbSize = sizeOf<MONITORINFO>();
    final monitor = MonitorFromWindow(target.window, MONITOR_DEFAULTTONEAREST);
    if (monitor == 0 ||
        GetMonitorInfo(monitor, monitorInfo) == 0 ||
        monitorInfo.ref.rcMonitor.left != target.left ||
        monitorInfo.ref.rcMonitor.top != target.top ||
        monitorInfo.ref.rcMonitor.right != target.left + target.width ||
        monitorInfo.ref.rcMonitor.bottom != target.top + target.height) {
      throw const ScreenPreviewException(
          'stale-frame', '모니터 배치가 바뀌었습니다. 미리보기를 갱신해 주세요.');
    }
    point.ref
      ..x = x
      ..y = y;
    final hit = WindowFromPoint(point.ref);
    if (hit == 0 || GetAncestor(hit, GA_ROOT) != target.window) {
      throw const ScreenPreviewException(
          'outside-signage', '사이니지가 표시된 영역만 클릭할 수 있습니다.');
    }
    final desktopWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final desktopHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (desktopWidth <= 0 || desktopHeight <= 0) {
      throw const ScreenPreviewException('input-failed', '화면 좌표를 확인하지 못했습니다.');
    }
    // 픽셀 중앙을 가리켜 다중 모니터의 음수 좌표와 배율에도 맞춘다.
    final dx = (((x - GetSystemMetrics(SM_XVIRTUALSCREEN)) + 0.5) *
            65536 /
            desktopWidth)
        .floor()
        .clamp(0, 65535);
    final dy = (((y - GetSystemMetrics(SM_YVIRTUALSCREEN)) + 0.5) *
            65536 /
            desktopHeight)
        .floor()
        .clamp(0, 65535);
    final count = phase == 'click' ? 3 : 1;
    for (var i = 0; i < count; i++) {
      inputs[i].type = INPUT_MOUSE;
      inputs[i].mi
        ..dx = dx
        ..dy = dy
        ..dwFlags = MOUSEEVENTF_ABSOLUTE |
            MOUSEEVENTF_VIRTUALDESK |
            MOUSEEVENTF_MOVE |
            (phase == 'down' || (phase == 'click' && i == 1)
                ? MOUSEEVENTF_LEFTDOWN
                : phase == 'up' || (phase == 'click' && i == 2)
                    ? MOUSEEVENTF_LEFTUP
                    : 0);
    }
    if (SendInput(count, inputs, sizeOf<INPUT>()) != count) {
      // 부분 전송으로 마우스 버튼이 눌린 채 남지 않게 해제한다.
      inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;
      SendInput(1, inputs, sizeOf<INPUT>());
      throw const ScreenPreviewException(
          'input-failed', 'Windows에 클릭을 전달하지 못했습니다.');
    }
  } finally {
    calloc.free(inputs);
    calloc.free(processId);
    calloc.free(point);
    calloc.free(monitorInfo);
  }
}

bool _isNearlyBlackFrame(Uint8List pixels) {
  if (pixels.length < 4) return true;
  final pixelCount = pixels.length ~/ 4;
  final sampleStride = (pixelCount ~/ 4096).clamp(1, pixelCount);
  var samples = 0;
  var nonBlack = 0;
  for (var pixel = 0; pixel < pixelCount; pixel += sampleStride) {
    final offset = pixel * 4;
    samples++;
    if (pixels[offset] > 4 ||
        pixels[offset + 1] > 4 ||
        pixels[offset + 2] > 4) {
      nonBlack++;
    }
  }
  return nonBlack * 1000 <= samples;
}

int _findCurrentProcessTopLevelWindow(Pointer<RECT> rect) {
  final processId = GetCurrentProcessId();
  final windowProcessId = calloc<Uint32>();
  var current = 0;
  var bestVisibleWindow = 0;
  var bestVisibleArea = 0;
  var bestFallbackWindow = 0;
  var bestFallbackArea = 0;
  try {
    while (true) {
      current = FindWindowEx(0, current, nullptr, nullptr);
      if (current == 0) break;
      GetWindowThreadProcessId(current, windowProcessId);
      if (windowProcessId.value != processId ||
          GetWindowRect(current, rect) == 0) {
        continue;
      }
      final width = rect.ref.right - rect.ref.left;
      final height = rect.ref.bottom - rect.ref.top;
      final area = width > 0 && height > 0 ? width * height : 0;
      if (area > bestFallbackArea) {
        bestFallbackWindow = current;
        bestFallbackArea = area;
      }
      if (IsWindowVisible(current) != 0 &&
          IsIconic(current) == 0 &&
          area > bestVisibleArea) {
        bestVisibleWindow = current;
        bestVisibleArea = area;
      }
    }
    return bestVisibleWindow != 0 ? bestVisibleWindow : bestFallbackWindow;
  } finally {
    calloc.free(windowProcessId);
  }
}
