import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

/// 앱 진입점.
///
/// - 가로 방향 사이니지를 가정하므로 가로 방향을 우선 권장한다.
/// - Android 등 모바일은 immersive(시스템 UI 숨김) 키오스크 모드로 진입한다.
/// - Windows/macOS/Linux 데스크톱은 [window_manager] 로 borderless fullscreen 표시.
/// - 개발 중 일반 창 모드는 환경변수 `SIMPLE_KIOSK_WINDOWED=1` 로 전환.
/// - 키오스크 운영 시에는 별도 디바이스 설정(잠금/킥아웃 등)을 함께 적용한다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 가로 방향 우선 (필요 시 운영 환경에서 조정).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  // 모바일: 시스템 UI(상태바/네비게이션 바)를 숨겨 키오스크 모드.
  // immersiveSticky: 가장자리 스와이프 시 일시적으로 보였다가 자동 복귀.
  // 데스크톱 플랫폼에서는 no-op.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 데스크톱: borderless fullscreen.
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    final windowed = Platform.environment['SIMPLE_KIOSK_WINDOWED'] == '1';
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'Simple Kiosk',
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (windowed) {
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
