import 'dart:io';

import '../service/runtime_paths.dart';

enum MenuFileKind { image, video, page }

/// `item.file`의 종류와 실제 파일 위치를 일관되게 해석한다.
class MenuFileTarget {
  static const imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  };

  static const videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.m4v',
    '.webm',
    '.mkv',
    '.avi',
  };

  static MenuFileKind classify(String configuredPath) {
    final path = configuredPath.split(RegExp(r'[?#]')).first.toLowerCase();
    final dot = path.lastIndexOf('.');
    final extension = dot < 0 ? '' : path.substring(dot);
    if (imageExtensions.contains(extension)) return MenuFileKind.image;
    if (videoExtensions.contains(extension)) return MenuFileKind.video;
    return MenuFileKind.page;
  }

  static bool isAsset(String configuredPath) {
    final normalized = configuredPath.trim().replaceAll('\\', '/');
    return normalized.startsWith('assets/') || normalized.startsWith('asset/');
  }

  static String assetPath(String configuredPath) {
    final normalized = configuredPath.trim().replaceAll('\\', '/');
    if (normalized.startsWith('asset/')) {
      return 'assets/${normalized.substring('asset/'.length)}';
    }
    return normalized;
  }

  /// 상대 경로는 앱 데이터 루트를 기준으로 해석한다.
  ///
  /// 따라서 WEB 관리자에서 올린 파일은 `exdata/...` 그대로 지정할 수 있다.
  static String fileSystemPath(String configuredPath) {
    final trimmed = configuredPath.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return uri.toFilePath(windows: Platform.isWindows);
    }
    if (File(trimmed).isAbsolute) return File(trimmed).path;
    return RuntimePaths.child(trimmed) ?? File(trimmed).absolute.path;
  }
}
