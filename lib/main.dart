import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'app_identity.dart';
import 'service/app_logger.dart';
import 'service/windows_kiosk_mode.dart';

/// 앱 진입점.
///
/// - 가로 방향 사이니지를 가정하므로 가로 방향을 우선 권장한다.
/// - Android 등 모바일은 immersive(시스템 UI 숨김) 사이니지 모드로 진입한다.
/// - Windows/macOS/Linux 데스크톱은 [window_manager] 로 borderless fullscreen 표시.
/// - 개발 중 일반 창 모드는 환경변수 `SIMPLE_KIOSK_WINDOWED=1` 로 전환.
/// - 사이니지 운영 시에는 별도 디바이스 설정(잠금/킥아웃 등)을 함께 적용한다.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--restart-delay')) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  WidgetsFlutterBinding.ensureInitialized();
  final startupMode = _startupMode(arguments);
  await AppLogger.initialize();
  AppLogger.info(LogCategory.app, 'Application starting ($startupMode)');
  final previousFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLogger.error(LogCategory.app, details.exception, details.stack);
    previousFlutterErrorHandler?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(LogCategory.app, error, stackTrace);
    return false;
  };

  // 가로 방향 우선 (필요 시 운영 환경에서 조정).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  // 모바일: 시스템 UI(상태바/네비게이션 바)를 숨겨 사이니지 모드.
  // immersiveSticky: 가장자리 스와이프 시 일시적으로 보였다가 자동 복귀.
  // 데스크톱 플랫폼에서는 no-op.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final desktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  final windowed = Platform.environment['SIMPLE_KIOSK_WINDOWED'] == '1';

  // 데스크톱 창은 먼저 숨김 상태로 구성하되, 전체화면 전환과 표시는 Flutter
  // 첫 프레임 이후에 수행한다. 첫 프레임과 네이티브 resize가 겹치면 Windows
  // 렌더 표면이 검게 고정될 수 있다.
  if (desktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: appDisplayName,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options);
  }

  runApp(const KioskApp());

  if (desktop) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _applyInitialWindowState(
          startupMode: startupMode,
          windowed: windowed,
        ),
      );
    });
  }
}

Future<void> _applyInitialWindowState({
  required String startupMode,
  required bool windowed,
}) async {
  try {
    if (!windowed) await windowManager.setFullScreen(true);

    // 전체화면 resize가 완료된 뒤 실제 표면 resize를 한 번 발생시키고 나서
    // 창을 공개한다. Windows 이외 플랫폼에서는 no-op이다.
    await WindowsKioskMode.recoverRenderingSurface();

    if (startupMode == 'hidden') {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
      return;
    }

    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
    AppLogger.info(LogCategory.app, 'Initial window surface ready');
  } catch (error, stackTrace) {
    AppLogger.error(LogCategory.app, error, stackTrace);
    // 표면 복구가 실패하더라도 사용자가 트레이에서 복구할 수 있도록 창 표시는
    // 마지막으로 시도한다.
    if (startupMode != 'hidden') {
      await windowManager.show();
      await windowManager.focus();
    }
  }
}

String _startupMode(List<String> arguments) {
  final index = arguments.indexOf('--startup-mode');
  if (index >= 0 && index + 1 < arguments.length) {
    return arguments[index + 1].toLowerCase() == 'hidden'
        ? 'hidden'
        : 'signage';
  }
  return 'signage';
}
