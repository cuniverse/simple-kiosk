import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

/// 앱 진입점.
///
/// - 가로 방향 사이니지를 가정하므로 가로 방향을 우선 권장한다.
/// - 키오스크 운영 시에는 별도 디바이스 설정(잠금/킥아웃 등)을 함께 적용한다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 가로 방향 우선 (필요 시 운영 환경에서 조정).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  runApp(const KioskApp());
}
