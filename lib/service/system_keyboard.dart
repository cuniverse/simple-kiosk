import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/layout_config.dart';
import 'app_logger.dart';
import 'keyboard_controller.dart';

/// 가상 키보드 호출 API.
///
/// Windows에서는 기본적으로 Windows 화면 키보드를 호출하고, 설정에 따라
/// 기존 Flutter 내장 키보드로 전환한다.
class SystemKeyboard {
  static const _channel = MethodChannel('simple_kiosk/system_keyboard');
  static KeyboardMode _mode = KeyboardMode.windows;
  static Timer? _visibilityPoller;
  static int _visibilityMisses = 0;
  static Timer? _flutterFocusHideTimer;
  static bool _focusTrackingStarted = false;
  static bool _flutterEditableFocused = false;
  static int _showGeneration = 0;

  /// 앱 루트가 내장 키보드 오버레이를 그려야 하는지 나타낸다.
  static final ValueNotifier<bool> builtInEnabled =
      ValueNotifier<bool>(!Platform.isWindows);

  static KeyboardMode get mode => _mode;
  static int get showGeneration => _showGeneration;

  static void configure(KeyboardMode mode) {
    _mode = mode;
    builtInEnabled.value = !Platform.isWindows || mode == KeyboardMode.builtIn;
    _startFlutterFocusTracking();
    _stopVisibilityPolling();
    KeyboardController.instance.hide();
  }

  static Future<void> show() async {
    _showGeneration += 1;
    if (builtInEnabled.value) {
      KeyboardController.instance.show();
      return;
    }
    try {
      final shown = await _channel.invokeMethod<bool>('show') ?? false;
      if (!shown) throw StateError('Windows 화면 키보드를 실행하지 못했습니다.');
      KeyboardController.instance.show();
      _startVisibilityPolling();
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.app, error, stackTrace);
      // Windows 구성 문제로 시스템 키보드를 실행할 수 없어도 입력은 가능해야 한다.
      builtInEnabled.value = true;
      KeyboardController.instance.show();
    }
  }

  static Future<void> hide() async {
    _stopVisibilityPolling();
    if (Platform.isWindows && _mode == KeyboardMode.windows) {
      try {
        await _channel.invokeMethod<bool>('hide');
      } catch (error, stackTrace) {
        AppLogger.error(LogCategory.app, error, stackTrace);
      }
    }
    KeyboardController.instance.hide();
  }

  /// 포커스 해제 뒤 대기하는 동안 새 표시 요청이 없었던 경우에만 감춘다.
  static Future<void> hideIfShowGeneration(int expectedGeneration) async {
    if (_showGeneration == expectedGeneration) await hide();
  }

  /// 실제 Windows 키보드 창 상태를 확인한 뒤 표시/감춤을 전환한다.
  static Future<void> toggle() async {
    if (builtInEnabled.value) {
      if (KeyboardController.instance.visible.value) {
        await hide();
      } else {
        await show();
      }
      return;
    }

    if (await _readNativeVisibility()) {
      await hide();
    } else {
      await show();
    }
  }

  static Future<bool> _readNativeVisibility() async {
    if (!Platform.isWindows || _mode != KeyboardMode.windows) return false;
    try {
      return await _channel.invokeMethod<bool>('isVisible') ?? false;
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.app, error, stackTrace);
      return KeyboardController.instance.visible.value;
    }
  }

  static void _startVisibilityPolling() {
    _stopVisibilityPolling();
    _visibilityMisses = 0;
    _visibilityPoller = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) async {
        final visible = await _readNativeVisibility();
        if (visible) {
          _visibilityMisses = 0;
          KeyboardController.instance.show();
        } else {
          _visibilityMisses += 1;
          // osk.exe 창 생성에는 시간이 걸릴 수 있으므로 시작 직후에는 여유를 둔다.
          if (_visibilityMisses < 4) return;
          KeyboardController.instance.hide();
          timer.cancel();
          if (identical(_visibilityPoller, timer)) _visibilityPoller = null;
        }
      },
    );
  }

  static void _stopVisibilityPolling() {
    _visibilityPoller?.cancel();
    _visibilityPoller = null;
    _visibilityMisses = 0;
  }

  /// Flutter TextField/TextFormField의 포커스를 감지해 키보드를 자동 호출한다.
  /// WebView 입력 요소는 KioskWebView의 JavaScript 포커스 훅이 별도로 처리한다.
  static void _startFlutterFocusTracking() {
    if (_focusTrackingStarted) return;
    _focusTrackingStarted = true;
    FocusManager.instance.addListener(_handleFlutterFocusChange);
  }

  static void _handleFlutterFocusChange() {
    final context = FocusManager.instance.primaryFocus?.context;
    var editableFocused = false;
    if (context != null) {
      editableFocused = context.widget is EditableText;
      if (!editableFocused) {
        context.visitAncestorElements((element) {
          if (element.widget is EditableText) {
            editableFocused = true;
            return false;
          }
          return true;
        });
      }
    }

    _flutterFocusHideTimer?.cancel();
    _flutterFocusHideTimer = null;
    if (editableFocused) {
      _flutterEditableFocused = true;
      unawaited(show());
    } else if (_flutterEditableFocused) {
      _flutterEditableFocused = false;
      final showGeneration = _showGeneration;
      _flutterFocusHideTimer = Timer(
        const Duration(milliseconds: 200),
        () => unawaited(hideIfShowGeneration(showGeneration)),
      );
    }
  }
}
