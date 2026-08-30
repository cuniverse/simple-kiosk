import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../model/layout_config.dart';

/// Windows 사이니지 창의 최상위 상태와 시스템 단축키 차단을 함께 관리한다.
class WindowsKioskMode {
  WindowsKioskMode._();

  static const MethodChannel _channel =
      MethodChannel('simple_kiosk/windows_kiosk_mode');
  static const MethodChannel _webViewManagerChannel =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');

  static bool _shortcutLockdownEnabled = true;
  static WindowsKioskShortcutSettings _shortcutSettings =
      WindowsKioskShortcutSettings.defaults;
  static bool _disableEdgeSwipe = true;
  static bool _alwaysOnTopEnabled = false;
  static bool _preventScreenSaver = true;
  static bool _preventDisplaySleep = true;

  static Future<void> configure({
    required bool shortcutLockdownEnabled,
    required WindowsKioskShortcutSettings shortcutSettings,
    required bool disableEdgeSwipe,
    required bool alwaysOnTopEnabled,
    required bool preventScreenSaver,
    required bool preventDisplaySleep,
  }) async {
    _shortcutLockdownEnabled = shortcutLockdownEnabled;
    _shortcutSettings = shortcutSettings;
    _disableEdgeSwipe = disableEdgeSwipe;
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

  /// WebView2 composition controller는 부모 Flutter 창과 별도 가시성 상태를
  /// 가지므로, 앱 창을 감출 때 명시적으로 함께 숨겨야 입력 HWND가 남지 않는다.
  static Future<void> setWebViewsVisible(bool visible) async {
    if (!Platform.isWindows) return;
    try {
      await _webViewManagerChannel.invokeMethod<void>(
        'setAllWebViewsVisible',
        {'visible': visible},
      );
    } on MissingPluginException {
      // 이전 Windows 플러그인 실행기와의 호환성을 유지한다.
    }
  }

  /// 메인 Flutter HWND뿐 아니라 WebView2 등 자식 프로세스가 만든 모든
  /// 최상위 창까지 Windows의 SW_HIDE로 숨긴다.
  static Future<void> hideProcessWindows() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<bool>('hideProcessWindows');
    } on MissingPluginException {
      // 이전 Windows 실행기에서는 메인 창 숨김 경로를 계속 사용한다.
    }
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
        'disableEdgeSwipe': _disableEdgeSwipe,
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
