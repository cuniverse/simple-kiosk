import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'media_scanner_fs_stub.dart'
    if (dart.library.io) 'media_scanner_fs_io.dart' as fs;

/// 미디어 한 항목.
enum MediaKind { image, video }

class MediaItem {
  final String path;
  final MediaKind kind;

  /// `assets/...` 경로면 true, 파일시스템 경로면 false.
  final bool isAsset;

  const MediaItem({
    required this.path,
    required this.kind,
    required this.isAsset,
  });
}

/// 폴더(에셋 또는 파일시스템)를 스캔해서 미디어 목록을 만든다.
class MediaScanner {
  static const Set<String> _imageExt = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  };
  static const Set<String> videoExtensions = {
    '.mp4',
    '.mov',
    '.m4v',
    '.webm',
    '.mkv',
    '.avi',
  };

  /// 설정에 직접 입력한 에셋·파일·URL 경로가 지원 동영상인지 판별한다.
  /// URL의 쿼리 문자열과 fragment는 확장자 판별에서 제외한다.
  static bool isVideoPath(String path) =>
      _classify(
        path.split(RegExp(r'[?#]')).first,
        includeImages: false,
        includeVideos: true,
      ) ==
      MediaKind.video;

  /// 지정한 폴더([path])에서 미디어 파일들을 찾아 [MediaItem] 목록을 반환한다.
  ///
  /// - `assets/`로 시작하는 경로 → AssetManifest를 통해 등록된 에셋만 수집.
  /// - 그 외 → 파일시스템에서 직접 스캔(웹에서는 불가).
  ///
  /// 결과는 항상 파일명 알파벳 오름차순.
  static Future<List<MediaItem>> scan({
    required String path,
    required bool includeImages,
    required bool includeVideos,
  }) async {
    if (path.startsWith('assets/') || path.startsWith('asset/')) {
      return _scanAssets(
        path: _normalizeAssetPath(path),
        includeImages: includeImages,
        includeVideos: includeVideos,
      );
    }

    if (kIsWeb) {
      throw StateError(
        '웹에서는 파일시스템 폴더 스캔이 지원되지 않습니다. '
        '"assets/..." 경로를 사용하세요.',
      );
    }
    return _scanFileSystem(
      path: path,
      includeImages: includeImages,
      includeVideos: includeVideos,
    );
  }

  static String _normalizeAssetPath(String p) {
    var s = p;
    if (!s.endsWith('/')) s = '$s/';
    return s;
  }

  static MediaKind? _classify(
    String filename, {
    required bool includeImages,
    required bool includeVideos,
  }) {
    final lower = filename.toLowerCase();
    final dotIdx = lower.lastIndexOf('.');
    if (dotIdx < 0) return null;
    final ext = lower.substring(dotIdx);
    if (includeImages && _imageExt.contains(ext)) return MediaKind.image;
    if (includeVideos && videoExtensions.contains(ext)) return MediaKind.video;
    return null;
  }

  static Future<List<MediaItem>> _scanAssets({
    required String path,
    required bool includeImages,
    required bool includeVideos,
  }) async {
    // Flutter 3.x: AssetManifest.json (구) / AssetManifest.bin (신) 둘 다 가능.
    // 가장 호환성 좋은 방법은 AssetManifest.json 직접 읽기.
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestJson);

    final result = <MediaItem>[];
    for (final key in manifest.keys) {
      if (!key.startsWith(path)) continue;
      // 하위 폴더 제외: path 바로 아래 파일만 수집.
      final rest = key.substring(path.length);
      if (rest.contains('/')) continue;

      final kind = _classify(
        rest,
        includeImages: includeImages,
        includeVideos: includeVideos,
      );
      if (kind == null) continue;
      result.add(MediaItem(path: key, kind: kind, isAsset: true));
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  static Future<List<MediaItem>> _scanFileSystem({
    required String path,
    required bool includeImages,
    required bool includeVideos,
  }) async {
    final entries = await fs.listDirectoryFiles(path);
    final result = <MediaItem>[];
    for (final entry in entries) {
      final kind = _classify(
        entry.name,
        includeImages: includeImages,
        includeVideos: includeVideos,
      );
      if (kind == null) continue;
      result.add(MediaItem(path: entry.fullPath, kind: kind, isAsset: false));
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  /// Windows 여부(파일 경로 안내용).
  static bool get isWindowsPlatform => !kIsWeb && fs.isWindows;
}
