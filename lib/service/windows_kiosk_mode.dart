import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 사이니지 창의 최상위 상태와 시스템 단축키 차단을 함께 관리한다.
class WindowsKioskMode {
  WindowsKioskMode._();

  static const MethodChannel _channel =
      MethodChannel('simple_kiosk/windows_kiosk_mode');

  static bool _shortcutLockdownEnabled = true;
  static bool _alwaysOnTopEnabled = false;

  static Future<void> configure({
    required bool shortcutLockdownEnabled,
    required bool alwaysOnTopEnabled,
  }) async {
    _shortcutLockdownEnabled = shortcutLockdownEnabled;
    _alwaysOnTopEnabled = alwaysOnTopEnabled;
    if (!Platform.isWindows) return;
    if (await windowManager.isVisible()) {
      await activate();
    } else {
      await deactivate();
    }
  }

  /// 사이니지를 표시할 때 최상위 창을 유지하고 설정된 키 차단을 활성화한다.
  static Future<void> activate() async {
    if (!Platform.isWindows) return;
    await windowManager.setAlwaysOnTop(_alwaysOnTopEnabled);
    await _setNativeEnabled(_shortcutLockdownEnabled);
  }

  /// 사이니지를 감추거나 종료할 때 Windows를 정상적으로 사용할 수 있게 해제한다.
  static Future<void> deactivate() async {
    if (!Platform.isWindows) return;
    await _setNativeEnabled(false);
    await windowManager.setAlwaysOnTop(false);
  }

  static Future<void> _setNativeEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // Windows 이외의 테스트 환경이나 이전 네이티브 실행기에서는 무시한다.
    }
  }
}
