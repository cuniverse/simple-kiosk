import 'dart:io' show File;

import 'package:video_player/video_player.dart';
// video_player_win을 import만 해두면 Windows에서 표준 VideoPlayerController API가
// 자동으로 Windows 구현으로 라우팅된다(플러그인 platform interface 방식).
// ignore: unused_import
import 'package:video_player_win/video_player_win.dart';

/// io 플랫폼(Android/iOS/macOS/Linux/Windows) 전용 구현.
///
/// 호출 측 코드는 표준 [VideoPlayerController] API 그대로 사용한다.
/// Windows의 경우 위 import 한 줄이 platform interface 등록을 보장한다.

VideoPlayerController createAssetController(String assetPath) {
  return VideoPlayerController.asset(assetPath);
}

VideoPlayerController createFileController(String path) {
  return VideoPlayerController.file(File(path));
}

VideoPlayerController createNetworkController(String url) {
  return VideoPlayerController.networkUrl(Uri.parse(url));
}