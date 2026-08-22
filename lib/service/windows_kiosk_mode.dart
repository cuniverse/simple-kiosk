import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../model/layout_config.dart';

/// Windows 사이니지 창의 최상위 상태와 시스템 단축키 차단을 함께 관리한다.
class WindowsKioskMode {
  WindowsKioskMode._();

  static const MethodChannel _channel =
      MethodChannel('simple_kiosk/windows_kiosk_mode');

  static bool _shortcutLockdownEnabled = true;
  static WindowsKioskShortcutSettings _shortcutSettings =
      WindowsKioskShortcutSettings.defaults;
  static bool _alwaysOnTopEnabled = false;
  static bool _preventScreenSaver = true;
  static bool _preventDisplaySleep = true;

  static Future<void> configure({
    required bool shortcutLockdownEnabled,
    required WindowsKioskShortcutSettings shortcutSettings,
    required bool alwaysOnTopEnabled,
    required bool preventScreenSaver,
    required bool preventDisplaySleep,
  }) async {
    _shortcutLockdownEnabled = shortcutLockdownEnabled;
    _shortcutSettings = shortcutSettings;
    _alwaysOnTopEnabled = alwaysOnTopEnabled;
    _preventScreenSaver = preventScreenSaver;
    _preventDisplaySleep = preventDisplaySleep;
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
    await _setNativeState(active: true);
  }

  /// 사이니지를 감추거나 종료할 때 Windows를 정상적으로 사용할 수 있게 해제한다.
  static Future<void> deactivate() async {
    if (!Platform.isWindows) return;
    await _setNativeState(active: false);
    await windowManager.setAlwaysOnTop(false);
  }

  /// Windows 렌더 표면을 실제 크기 변경으로 다시 동기화한다.
  ///
  /// 전체화면 전환, 숨김 복원, 디스플레이 절전 복귀 과정에서 Flutter 프레임은
  /// 생성되지만 화면이 검게 남는 경우를 복구한다.
  static Future<void> recoverRenderingSurface() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('recoverSurface');
    } on MissingPluginException {
      // Windows 이외 테스트 환경이나 이전 네이티브 실행기에서는 무시한다.
    }
  }

  static Future<void> _setNativeState({required bool active}) async {
    try {
      await _channel.invokeMethod<bool>('setEnabled', {
        // 이전 Windows runner와 함께 실행되는 복구 상황에서도 단축키 잠금은 유지한다.
        'enabled': active && _shortcutLockdownEnabled,
        'active': active,
        'shortcutLockdownEnabled': _shortcutLockdownEnabled,
        'blockWindowsKey': _shortcutSettings.windowsKey,
        'blockAltTab': _shortcutSettings.altTab,
        'blockAltEscape': _shortcutSettings.altEscape,
        'blockAltF4': _shortcutSettings.altF4,
        'blockAltSpace': _shortcutSettings.altSpace,
        'blockCtrlEscape': _shortcutSettings.ctrlEscape,
        'blockCtrlShiftEscape': _shortcutSettings.ctrlShiftEscape,
        'blockLaunchApp1': _shortcutSettings.launchApp1,
        'blockLaunchApp2': _shortcutSettings.launchApp2,
        'blockLaunchMail': _shortcutSettings.launchMail,
        'blockBrowserHome': _shortcutSettings.browserHome,
        'blockBrowserSearch': _shortcutSettings.browserSearch,
        'blockBrowserFavorites': _shortcutSettings.browserFavorites,
        'preventScreenSaver': _preventScreenSaver,
        'preventDisplaySleep': _preventDisplaySleep,
      });
    } on MissingPluginException {
      // Windows 이외의 테스트 환경이나 이전 네이티브 실행기에서는 무시한다.
    }
  }
}
