import 'dart:async';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_identity.dart';
import '../model/layout_config.dart';
import 'windows_kiosk_mode.dart';

class KioskTrayController with TrayListener, WindowListener {
  KioskTrayController({
    required this.onOpenSettings,
    required this.onOpenManual,
    required this.onOpenWebAdmin,
    required this.onRestart,
    required bool shortcutLockdownEnabled,
    required WindowsKioskShortcutSettings shortcutSettings,
    required bool disableEdgeSwipe,
    required bool alwaysOnTopEnabled,
    required bool preventScreenSaver,
    required bool preventDisplaySleep,
  })  : _shortcutLockdownEnabled = shortcutLockdownEnabled,
        _shortcutSettings = shortcutSettings,
        _disableEdgeSwipe = disableEdgeSwipe,
        _alwaysOnTopEnabled = alwaysOnTopEnabled,
        _preventScreenSaver = preventScreenSaver,
        _preventDisplaySleep = preventDisplaySleep;

  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenManual;
  final Future<void> Function() onOpenWebAdmin;
  final Future<void> Function() onRestart;

  bool _initialized = false;
  bool _allowExit = false;
  bool _shortcutLockdownEnabled;
  WindowsKioskShortcutSettings _shortcutSettings;
  bool _disableEdgeSwipe;
  bool _alwaysOnTopEnabled;
  bool _preventScreenSaver;
  bool _preventDisplaySleep;
  String? _versionLabel;
  bool _webAdminAvailable = false;
  String _reverseForwardingStatus = '확인 중';
  Uri? _reverseForwardingUri;
  String? _webAdminMenuSignature;
  Future<void> _menuUpdateQueue = Future<void>.value();

  bool get supported => Platform.isWindows;

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    final executableRoot = File(Platform.resolvedExecutable).parent.path;
    final iconPath = '$executableRoot${Platform.pathSeparator}data'
        '${Platform.pathSeparator}flutter_assets'
        '${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}icons'
        '${Platform.pathSeparator}simple_kiosk.ico';

    if (!await File(iconPath).exists()) {
      throw FileSystemException('트레이 아이콘 파일을 찾을 수 없습니다.', iconPath);
    }

    var listenersAdded = false;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final versionLabel = '$appDisplayName v${packageInfo.version}';
      _versionLabel = versionLabel;
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip(versionLabel);
      await _applyContextMenu();
      trayManager.addListener(this);
      windowManager.addListener(this);
      listenersAdded = true;
      await windowManager.setPreventClose(true);
      _initialized = true;
      await _applyContextMenu();
      await WindowsKioskMode.configure(
        shortcutLockdownEnabled: _shortcutLockdownEnabled,
        shortcutSettings: _shortcutSettings,
        disableEdgeSwipe: _disableEdgeSwipe,
        alwaysOnTopEnabled: _alwaysOnTopEnabled,
        preventScreenSaver: _preventScreenSaver,
        preventDisplaySleep: _preventDisplaySleep,
      );
    } catch (_) {
      if (listenersAdded) {
        trayManager.removeListener(this);
        windowManager.removeListener(this);
      }
      await windowManager.setPreventClose(false);
      await trayManager.destroy();
      rethrow;
    }
  }

  Future<void> showWindow() async {
    if (!supported) return;
    await WindowsKioskMode.activate();
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await WindowsKioskMode.recoverRenderingSurface();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!supported) return;
    await WindowsKioskMode.deactivate();
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> toggleWindow() async {
    if (await windowManager.isVisible()) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  Future<void> exitApplication() async {
    if (!supported || _allowExit) return;
    _allowExit = true;
    await WindowsKioskMode.deactivate();
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _initialized = false;
  }

  Future<void> configureKioskMode({
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
    await WindowsKioskMode.configure(
      shortcutLockdownEnabled: shortcutLockdownEnabled,
      shortcutSettings: shortcutSettings,
      disableEdgeSwipe: disableEdgeSwipe,
      alwaysOnTopEnabled: alwaysOnTopEnabled,
      preventScreenSaver: preventScreenSaver,
      preventDisplaySleep: preventDisplaySleep,
    );
  }

  void updateWebAdminState({
    required bool available,
    required String reverseForwardingStatus,
    Uri? reverseForwardingUri,
  }) {
    final signature =
        '$available|$reverseForwardingStatus|${reverseForwardingUri ?? ''}';
    if (_webAdminMenuSignature == signature) return;
    _webAdminMenuSignature = signature;
    _webAdminAvailable = available;
    _reverseForwardingStatus = reverseForwardingStatus;
    _reverseForwardingUri = reverseForwardingUri;
    if (!_initialized) return;
    _menuUpdateQueue =
        _menuUpdateQueue.catchError((_) {}).then((_) => _applyContextMenu());
  }

  Future<void> _applyContextMenu() async {
    final versionLabel = _versionLabel;
    if (versionLabel == null) return;
    final reverseForwardingConnected = _reverseForwardingUri != null;
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(label: versionLabel, disabled: true),
          MenuItem.separator(),
          MenuItem(key: 'show', label: '사이니지 보이기'),
          MenuItem(key: 'hide', label: '사이니지 감추기'),
          MenuItem(key: 'restart', label: '사이니지 재시작'),
          MenuItem.separator(),
          MenuItem(
            key: 'web-admin',
            label: '웹관리자 열기',
            disabled: !_webAdminAvailable,
          ),
          MenuItem(
            label: '리버스 포워딩: $_reverseForwardingStatus',
            icon: reverseForwardingConnected
                ? 'status-connected'
                : 'status-disconnected',
            disabled: !reverseForwardingConnected,
          ),
          if (_reverseForwardingUri case final uri?)
            MenuItem(label: '주소: $uri', disabled: true),
          MenuItem.separator(),
          MenuItem(key: 'settings', label: '설정'),
          MenuItem(key: 'manual', label: '사용자 매뉴얼'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '완전 종료'),
        ],
      ),
    );
  }

  @override
  void onWindowClose() {
    if (_allowExit) return;
    unawaited(hideWindow());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showContextMenu());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_showContextMenu());
  }

  Future<void> _showContextMenu() {
    // Windows requires the menu owner to be the foreground window so an
    // outside click dismisses the native TrackPopupMenu.
    // ignore: deprecated_member_use
    return trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showWindow());
        return;
      case 'hide':
        unawaited(hideWindow());
        return;
      case 'restart':
        unawaited(onRestart());
        return;
      case 'settings':
        unawaited(_showThen(onOpenSettings));
        return;
      case 'web-admin':
        unawaited(onOpenWebAdmin());
        return;
      case 'manual':
        unawaited(_showThen(onOpenManual));
        return;
      case 'exit':
        unawaited(exitApplication());
        return;
    }
  }

  Future<void> _showThen(Future<void> Function() action) async {
    await showWindow();
    await action();
  }
}
