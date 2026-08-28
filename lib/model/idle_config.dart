/// 대기화면(attract / idle screen)에서 표시할 콘텐츠 종류.
enum IdleMode { none, image, slideshow, url, folder, gallery }

IdleMode _parseIdleMode(Object? raw) {
  if (raw == null) return IdleMode.none;
  if (raw is! String) {
    throw const FormatException('menu.json idle.mode: 문자열이어야 함');
  }
  switch (raw.toLowerCase()) {
    case 'none':
      return IdleMode.none;
    case 'image':
      return IdleMode.image;
    case 'slideshow':
      return IdleMode.slideshow;
    case 'url':
      return IdleMode.url;
    case 'folder':
      return IdleMode.folder;
    case 'gallery':
      return IdleMode.gallery;
    default:
      throw FormatException('menu.json: 알 수 없는 idle.mode 값 "$raw"');
  }
}

/// 슬라이드쇼 전환 효과.
enum SlideshowTransition { none, fade }

SlideshowTransition _parseTransition(Object? raw) {
  if (raw == null) return SlideshowTransition.fade;
  if (raw is! String) {
    throw const FormatException('menu.json idle.slideshow.transition: 문자열');
  }
  switch (raw.toLowerCase()) {
    case 'none':
      return SlideshowTransition.none;
    case 'fade':
      return SlideshowTransition.fade;
    default:
      throw FormatException('menu.json: 알 수 없는 transition 값 "$raw"');
  }
}

class SlideshowConfig {
  /// 한 장당 표시 시간(초).
  final int intervalSec;

  /// 전환 효과.
  final SlideshowTransition transition;

  /// 이미지 또는 동영상 경로 목록.
  /// - `assets/...` → 에셋
  /// - `http(s)://...` → 네트워크
  final List<String> images;

  const SlideshowConfig({
    this.intervalSec = 6,
    this.transition = SlideshowTransition.fade,
    this.images = const [],
  });

  static const SlideshowConfig defaults = SlideshowConfig();

  factory SlideshowConfig.fromJson(Map<String, dynamic> json) {
    final intervalRaw = json['intervalSec'];
    int interval = defaults.intervalSec;
    if (intervalRaw != null) {
      if (intervalRaw is! num || intervalRaw <= 0) {
        throw const FormatException(
          'menu.json idle.slideshow.intervalSec: 양수 필요',
        );
      }
      interval = intervalRaw.toInt();
    }

    final imagesRaw = json['images'];
    final images = <String>[];
    if (imagesRaw is List) {
      for (var i = 0; i < imagesRaw.length; i++) {
        final v = imagesRaw[i];
        if (v is! String || v.isEmpty) {
          throw FormatException(
            'menu.json idle.slideshow.images[$i]: 비어있지 않은 문자열 필요',
          );
        }
        images.add(v);
      }
    } else if (imagesRaw != null) {
      throw const FormatException(
        'menu.json idle.slideshow.images: 배열이어야 함',
      );
    }

    return SlideshowConfig(
      intervalSec: interval,
      transition: _parseTransition(json['transition']),
      images: List.unmodifiable(images),
    );
  }
}

/// 폴더 순회 모드 설정.
///
/// `path`가 `assets/...` 로 시작하면 Flutter 에셋 폴더를 자동 스캔하고,
/// 그 외의 절대 경로이면 파일시스템을 스캔한다. 웹에서는 에셋 모드만 지원.
class FolderConfig {
  /// 폴더 경로.
  final String path;

  /// 복수 폴더 경로. 비어 있으면 기존 [path]를 사용한다.
  final List<String> paths;

  List<String> get effectivePaths =>
      paths.isNotEmpty ? paths : (path.isEmpty ? const [] : [path]);

  /// 이미지 장당 표시 시간(초). 동영상은 구간 종료까지 재생 후 다음.
  final int intervalSec;

  /// 순서 섬플.
  final bool shuffle;

  /// 이미지 파일 포함 여부.
  final bool includeImages;

  /// 동영상 파일 포함 여부.
  final bool includeVideos;

  /// 이미지 간 전환 효과.
  final SlideshowTransition transition;

  const FolderConfig({
    this.path = '',
    this.paths = const [],
    this.intervalSec = 8,
    this.shuffle = false,
    this.includeImages = true,
    this.includeVideos = true,
    this.transition = SlideshowTransition.fade,
  });

  static const FolderConfig defaults = FolderConfig();

  bool get isUsable =>
      effectivePaths.isNotEmpty && (includeImages || includeVideos);

  factory FolderConfig.fromJson(Map<String, dynamic> json) {
    String parseStringRequired(String key) {
      final v = json[key];
      if (v == null || (v is String && v.isEmpty)) {
        throw FormatException('menu.json idle.folder.$key: 분 이었음 불가');
      }
      if (v is! String) {
        throw FormatException('menu.json idle.folder.$key: 문자열 필요');
      }
      return v;
    }

    int parseInt(String key, int fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is! num || v <= 0) {
        throw FormatException('menu.json idle.folder.$key: 양수 필요');
      }
      return v.toInt();
    }

    bool parseBool(String key, bool fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is bool) return v;
      throw FormatException('menu.json idle.folder.$key: bool 필요');
    }

    final paths = <String>[];
    final pathsRaw = json['paths'];
    if (pathsRaw is List) {
      for (var i = 0; i < pathsRaw.length; i++) {
        final value = pathsRaw[i];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException(
            'menu.json idle.folder.paths[$i]: 비어있지 않은 문자열 필요',
          );
        }
        if (!paths.contains(value.trim())) paths.add(value.trim());
      }
      if (paths.isEmpty) {
        throw const FormatException('menu.json idle.folder.paths: 한 개 이상 필요');
      }
    } else if (pathsRaw != null) {
      throw const FormatException('menu.json idle.folder.paths: 배열이어야 함');
    }

    return FolderConfig(
      path: paths.isEmpty ? parseStringRequired('path') : '',
      paths: List.unmodifiable(paths),
      intervalSec: parseInt('intervalSec', defaults.intervalSec),
      shuffle: parseBool('shuffle', defaults.shuffle),
      includeImages: parseBool('includeImages', defaults.includeImages),
      includeVideos: parseBool('includeVideos', defaults.includeVideos),
      transition: _parseTransition(json['transition']),
    );
  }
}

/// 웹 포토갤러리 게시물의 사진을 순회하는 대기화면 설정.
class GallerySourceConfig {
  final String url;
  final int? lookbackDays;
  final int minPosts;
  final int maxPosts;

  const GallerySourceConfig({
    required this.url,
    this.lookbackDays,
    this.minPosts = 1,
    this.maxPosts = 4,
  });

  bool get isUsable =>
      _isValidHttpUrl(url) &&
      (lookbackDays == null || lookbackDays! > 0) &&
      minPosts > 0 &&
      maxPosts > 0 &&
      minPosts <= maxPosts;

  String get playbackKey => '$url|$lookbackDays|$minPosts|$maxPosts';
}

class GalleryConfig {
  /// 포토갤러리 게시판 목록 URL.
  final String url;

  /// 복수 포토갤러리 게시판 URL. 비어 있으면 기존 [url]을 사용한다.
  final List<String> urls;

  /// 주소별 게시물 선택 조건. JSON의 `urls` 객체 항목에서 읽는다.
  final List<GallerySourceConfig> sources;

  List<String> get _legacyUrls =>
      urls.isNotEmpty ? urls : (url.isEmpty ? const [] : [url]);

  List<GallerySourceConfig> get effectiveSources => sources.isNotEmpty
      ? sources
      : _legacyUrls
          .map(
            (sourceUrl) => GallerySourceConfig(
              url: sourceUrl,
              lookbackDays: lookbackDays,
              minPosts: minPosts,
              maxPosts: maxPosts,
            ),
          )
          .toList(growable: false);

  List<String> get effectiveUrls =>
      effectiveSources.map((source) => source.url).toList(growable: false);

  String get playbackKey =>
      effectiveSources.map((source) => source.playbackKey).join('||');

  /// 사진 한 장당 표시 시간(초).
  final int intervalSec;

  /// 목록에서 읽을 최신 게시물 수.
  final int maxPosts;

  /// 현재 시각부터 과거 며칠까지의 게시물을 우선 선택할지. 미지정 시 최신순만 사용한다.
  final int? lookbackDays;

  /// 기간 조건에 맞는 게시물이 부족할 때 최신순으로 보충할 최소 게시물 수.
  final int minPosts;

  /// 실행 중인 갤러리 목록을 다시 확인하는 주기(분).
  final int refreshIntervalMin;

  /// 사진 순서를 한 번 섞어 재생할지.
  final bool shuffle;

  /// 한 번에 표시할 최대 사진 수.
  final int maxImages;

  /// 사진 간 전환 효과.
  final SlideshowTransition transition;

  const GalleryConfig({
    this.url = '',
    this.urls = const [],
    this.sources = const [],
    this.intervalSec = 8,
    this.maxPosts = 4,
    this.lookbackDays,
    this.minPosts = 1,
    this.refreshIntervalMin = 5,
    this.shuffle = false,
    this.maxImages = 40,
    this.transition = SlideshowTransition.fade,
  });

  static const GalleryConfig defaults = GalleryConfig();

  bool get isUsable {
    return effectiveSources.isNotEmpty &&
        effectiveSources.every((source) => source.isUsable);
  }

  factory GalleryConfig.fromJson(Map<String, dynamic> json) {
    String parseUrlValue(Object? value, String key) {
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('menu.json idle.gallery.$key: URL 필요');
      }
      final uri = Uri.tryParse(value.trim());
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        throw FormatException('menu.json idle.gallery.$key: HTTP(S) URL 필요');
      }
      return value.trim();
    }

    int parsePositiveInt(String key, int fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || value <= 0) {
        throw FormatException('menu.json idle.gallery.$key: 양수 필요');
      }
      return value.toInt();
    }

    bool parseBool(String key, bool fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! bool) {
        throw FormatException('menu.json idle.gallery.$key: true/false 필요');
      }
      return value;
    }

    final maxPosts = parsePositiveInt('maxPosts', defaults.maxPosts);
    final minPosts = parsePositiveInt('minPosts', defaults.minPosts);
    final lookbackDays = json['lookbackDays'] == null
        ? null
        : parsePositiveInt('lookbackDays', 1);
    if (minPosts > maxPosts) {
      throw const FormatException(
        'menu.json idle.gallery.minPosts: maxPosts 이하여야 함',
      );
    }

    GallerySourceConfig parseSource(Object? raw, String key) {
      if (raw is String) {
        return GallerySourceConfig(
          url: parseUrlValue(raw, key),
          lookbackDays: lookbackDays,
          minPosts: minPosts,
          maxPosts: maxPosts,
        );
      }
      if (raw is! Map<String, dynamic>) {
        throw FormatException(
          'menu.json idle.gallery.$key: URL 문자열 또는 설정 객체 필요',
        );
      }
      final sourceUrl = parseUrlValue(raw['url'], '$key.url');

      int sourcePositiveInt(String field, int fallback) {
        final value = raw[field];
        if (value == null) return fallback;
        if (value is! num || value <= 0) {
          throw FormatException(
            'menu.json idle.gallery.$key.$field: 양수 필요',
          );
        }
        return value.toInt();
      }

      final sourceLookbackDays = raw.containsKey('lookbackDays')
          ? (raw['lookbackDays'] == null
              ? null
              : sourcePositiveInt('lookbackDays', 1))
          : lookbackDays;
      final sourceMinPosts = sourcePositiveInt('minPosts', minPosts);
      final sourceMaxPosts = sourcePositiveInt('maxPosts', maxPosts);
      if (sourceMinPosts > sourceMaxPosts) {
        throw FormatException(
          'menu.json idle.gallery.$key.minPosts: maxPosts 이하여야 함',
        );
      }
      return GallerySourceConfig(
        url: sourceUrl,
        lookbackDays: sourceLookbackDays,
        minPosts: sourceMinPosts,
        maxPosts: sourceMaxPosts,
      );
    }

    final sources = <GallerySourceConfig>[];
    final seenUrls = <String>{};
    final urlsRaw = json['urls'];
    if (urlsRaw is List) {
      for (var i = 0; i < urlsRaw.length; i++) {
        final source = parseSource(urlsRaw[i], 'urls[$i]');
        if (seenUrls.add(source.url)) sources.add(source);
      }
      if (sources.isEmpty) {
        throw const FormatException('menu.json idle.gallery.urls: 한 개 이상 필요');
      }
    } else if (urlsRaw != null) {
      throw const FormatException('menu.json idle.gallery.urls: 배열이어야 함');
    }

    if (sources.isEmpty) {
      final legacyUrl = parseUrlValue(json['url'], 'url');
      sources.add(
        GallerySourceConfig(
          url: legacyUrl,
          lookbackDays: lookbackDays,
          minPosts: minPosts,
          maxPosts: maxPosts,
        ),
      );
    }

    return GalleryConfig(
      sources: List.unmodifiable(sources),
      intervalSec: parsePositiveInt(
        'intervalSec',
        defaults.intervalSec,
      ),
      maxPosts: maxPosts,
      lookbackDays: lookbackDays,
      minPosts: minPosts,
      refreshIntervalMin: parsePositiveInt(
        'refreshIntervalMin',
        defaults.refreshIntervalMin,
      ),
      shuffle: parseBool('shuffle', defaults.shuffle),
      maxImages: parsePositiveInt('maxImages', defaults.maxImages),
      transition: _parseTransition(json['transition']),
    );
  }
}

bool _isValidHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// 대기화면 설정.
///
/// `menu.json`의 선택적 `idle` 섹션에서 로드된다.
/// 값이 누락되면 모두 기본값을 사용한다.
class IdleConfig {
  /// 대기화면 기능 활성화 여부.
  final bool enabled;

  /// 무입력 타임아웃(초). `0` 이하면 무입력 진입을 사용하지 않는다.
  final int timeoutSec;

  /// 앱 시작(콜드 스타트) 직후에 대기화면부터 보여줄지.
  final bool startOnLaunch;

  /// 표시할 콘텐츠 종류. `slideshow`, `folder`, `gallery`는 함께 사용할 수 있다.
  final List<IdleMode> modes;

  /// 기존 단일 모드 접근과의 호환용 첫 번째 모드.
  IdleMode get mode => modes.isEmpty ? IdleMode.none : modes.first;

  /// [mode]가 [IdleMode.image]일 때 사용할 단일 이미지 경로.
  final String? image;

  /// [mode]가 [IdleMode.slideshow]일 때의 설정.
  final SlideshowConfig slideshow;

  /// [mode]가 [IdleMode.url]일 때 표시할 URL.
  final String? url;

  /// [mode]가 [IdleMode.folder]일 때 사용할 설정.
  final FolderConfig folder;

  /// [mode]가 [IdleMode.gallery]일 때 사용할 설정.
  final GalleryConfig gallery;

  /// "터치하여 시작" 같은 안내 표시 여부.
  final bool showHint;

  /// 안내 텍스트.
  final String hintText;

  const IdleConfig({
    this.enabled = false,
    this.timeoutSec = 60,
    this.startOnLaunch = true,
    this.modes = const [IdleMode.none],
    this.image,
    this.slideshow = SlideshowConfig.defaults,
    this.url,
    this.folder = FolderConfig.defaults,
    this.gallery = GalleryConfig.defaults,
    this.showHint = true,
    this.hintText = '화면을 터치해 주세요',
  });

  static const IdleConfig defaults = IdleConfig();

  /// 실질적으로 대기화면을 사용할 수 있는 상태인지.
  /// `enabled=true` 이고, 모드/콘텐츠가 유효해야 한다.
  bool get isUsable {
    if (!enabled) return false;
    if (modes.isEmpty || modes.contains(IdleMode.none)) return false;
    return modes.every((mode) {
      switch (mode) {
        case IdleMode.none:
          return false;
        case IdleMode.image:
          return image != null && image!.isNotEmpty;
        case IdleMode.slideshow:
          return slideshow.images.isNotEmpty;
        case IdleMode.url:
          return url != null && url!.isNotEmpty;
        case IdleMode.folder:
          return folder.isUsable;
        case IdleMode.gallery:
          return gallery.isUsable;
      }
    });
  }

  factory IdleConfig.fromJson(Map<String, dynamic> json) {
    bool parseBool(String key, bool fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is bool) return v;
      throw FormatException('menu.json idle.$key: bool 필요');
    }

    int parseInt(String key, int fallback) {
      final v = json[key];
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      throw FormatException('menu.json idle.$key: 숫자 필요');
    }

    String? parseString(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is String) return v.isEmpty ? null : v;
      throw FormatException('menu.json idle.$key: 문자열 필요');
    }

    SlideshowConfig slideshow = SlideshowConfig.defaults;
    final slideshowRaw = json['slideshow'];
    if (slideshowRaw is Map<String, dynamic>) {
      slideshow = SlideshowConfig.fromJson(slideshowRaw);
    } else if (slideshowRaw != null) {
      throw const FormatException('menu.json idle.slideshow: 객체여야 함');
    }

    FolderConfig folder = FolderConfig.defaults;
    final folderRaw = json['folder'];
    if (folderRaw is Map<String, dynamic>) {
      folder = FolderConfig.fromJson(folderRaw);
    } else if (folderRaw != null) {
      throw const FormatException('menu.json idle.folder: 객체여야 함');
    }

    GalleryConfig gallery = GalleryConfig.defaults;
    final galleryRaw = json['gallery'];
    if (galleryRaw is Map<String, dynamic>) {
      gallery = GalleryConfig.fromJson(galleryRaw);
    } else if (galleryRaw != null) {
      throw const FormatException('menu.json idle.gallery: 객체여야 함');
    }

    final modes = <IdleMode>[];
    final modesRaw = json['modes'];
    if (modesRaw is List) {
      for (var i = 0; i < modesRaw.length; i++) {
        final mode = _parseIdleMode(modesRaw[i]);
        if (!modes.contains(mode)) modes.add(mode);
      }
      if (modes.isEmpty) {
        throw const FormatException('menu.json idle.modes: 한 개 이상 필요');
      }
    } else if (modesRaw != null) {
      throw const FormatException('menu.json idle.modes: 배열이어야 함');
    } else {
      modes.add(_parseIdleMode(json['mode']));
    }

    if (modes.contains(IdleMode.url) && modes.length != 1) {
      throw const FormatException('menu.json idle.modes: url은 단독 모드만 가능');
    }
    if (modes.length > 1) {
      const combinable = {
        IdleMode.slideshow,
        IdleMode.folder,
        IdleMode.gallery,
      };
      if (modes.any((mode) => !combinable.contains(mode))) {
        throw const FormatException(
          'menu.json idle.modes: slideshow, folder, gallery만 복수 지정 가능',
        );
      }
    }
    final hintText = parseString('hintText') ?? defaults.hintText;

    return IdleConfig(
      enabled: parseBool('enabled', defaults.enabled),
      timeoutSec: parseInt('timeoutSec', defaults.timeoutSec),
      startOnLaunch: parseBool('startOnLaunch', defaults.startOnLaunch),
      modes: List.unmodifiable(modes),
      image: parseString('image'),
      slideshow: slideshow,
      url: parseString('url'),
      folder: folder,
      gallery: gallery,
      showHint: parseBool('showHint', defaults.showHint),
      hintText: hintText,
    );
  }
}
