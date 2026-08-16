import 'dart:async';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app_identity.dart';

class KioskTrayController with TrayListener, WindowListener {
  KioskTrayController({
    required this.onOpenSettings,
    required this.onOpenManual,
  });

  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenManual;

  bool _initialized = false;
  bool _allowExit = false;

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
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip(versionLabel);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(label: versionLabel, disabled: true),
            MenuItem.separator(),
            MenuItem(key: 'show', label: '사이니지 보이기'),
            MenuItem(key: 'hide', label: '사이니지 감추기'),
            MenuItem.separator(),
            MenuItem(key: 'settings', label: '설정'),
            MenuItem(key: 'manual', label: '사용자 매뉴얼'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: '완전 종료'),
          ],
        ),
      );
      trayManager.addListener(this);
      windowManager.addListener(this);
      listenersAdded = true;
      await windowManager.setPreventClose(true);
      _initialized = true;
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
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hideWindow() async {
    if (!supported) return;
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

  @override
  void onWindowClose() {
    if (_allowExit) return;
    unawaited(hideWindow());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(toggleWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
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
      case 'settings':
        unawaited(_showThen(onOpenSettings));
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
