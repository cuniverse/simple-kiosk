import 'package:video_player/video_player.dart';

/// 웹용 stub. dart:io / video_player_win 을 import하지 않는다.
VideoPlayerController createAssetController(String assetPath) =>
    VideoPlayerController.asset(assetPath);

VideoPlayerController createFileController(String path) {
  throw StateError('웹에서는 파일시스템 경로를 사용할 수 없습니다: $path');
}

VideoPlayerController createNetworkController(String url) =>
    VideoPlayerController.networkUrl(Uri.parse(url));
