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

  // 데스크톱: borderless fullscreen.
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    final windowed = Platform.environment['SIMPLE_KIOSK_WINDOWED'] == '1';
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: appDisplayName,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (startupMode == 'hidden') {
        if (!windowed) await windowManager.setFullScreen(true);
        await windowManager.setSkipTaskbar(true);
        await windowManager.hide();
      } else if (windowed) {
        await windowManager.show();
        await windowManager.focus();
      } else {
        await windowManager.setFullScreen(true);
        await windowManager.show();
        await windowManager.focus();
      }
    });
  }

  runApp(const KioskApp());
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
