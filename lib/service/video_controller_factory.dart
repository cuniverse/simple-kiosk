import 'package:video_player/video_player.dart';

import 'video_controller_factory_stub.dart'
    if (dart.library.io) 'video_controller_factory_io.dart';

/// 플랫폼에 맞는 [VideoPlayerController] 를 생성한다.
///
/// - 웹: 표준 `video_player` 의 web 구현 사용 (asset/network).
/// - 데스크톱(Windows) + 모바일/macOS: io 구현(`video_controller_factory_io.dart`).
///
/// 파일시스템 경로는 웹에서 의미가 없으므로 [StateError] 를 던진다.
class VideoControllerFactory {
  static VideoPlayerController asset(String assetPath) =>
      createAssetController(assetPath);

  static VideoPlayerController file(String path) => createFileController(path);

  static VideoPlayerController network(String url) =>
      createNetworkController(url);
}
