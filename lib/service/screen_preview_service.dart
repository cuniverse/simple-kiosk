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

  const ScreenPreviewFrame({
    required this.jpegBytes,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.windowState = ScreenPreviewWindowState.visible,
  });
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
  })  : _frameCapturer = frameCapturer ?? _captureWindowsFrame,
        _clock = clock ?? DateTime.now;

  final ScreenFrameCapturer _frameCapturer;
  final ScreenPreviewClock _clock;
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
