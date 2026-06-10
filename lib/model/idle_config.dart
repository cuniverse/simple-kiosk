/// 대기화면(attract / idle screen)에서 표시할 콘텐츠 종류.
enum IdleMode { none, image, slideshow, url }

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

  /// 이미지 경로 목록.
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

  /// 표시할 콘텐츠 종류.
  final IdleMode mode;

  /// [mode]가 [IdleMode.image]일 때 사용할 단일 이미지 경로.
  final String? image;

  /// [mode]가 [IdleMode.slideshow]일 때의 설정.
  final SlideshowConfig slideshow;

  /// [mode]가 [IdleMode.url]일 때 표시할 URL.
  final String? url;

  /// "터치하여 시작" 같은 안내 표시 여부.
  final bool showHint;

  /// 안내 텍스트.
  final String hintText;

  const IdleConfig({
    this.enabled = false,
    this.timeoutSec = 60,
    this.startOnLaunch = true,
    this.mode = IdleMode.none,
    this.image,
    this.slideshow = SlideshowConfig.defaults,
    this.url,
    this.showHint = true,
    this.hintText = '화면을 터치해 주세요',
  });

  static const IdleConfig defaults = IdleConfig();

  /// 실질적으로 대기화면을 사용할 수 있는 상태인지.
  /// `enabled=true` 이고, 모드/콘텐츠가 유효해야 한다.
  bool get isUsable {
    if (!enabled) return false;
    switch (mode) {
      case IdleMode.none:
        return false;
      case IdleMode.image:
        return image != null && image!.isNotEmpty;
      case IdleMode.slideshow:
        return slideshow.images.isNotEmpty;
      case IdleMode.url:
        return url != null && url!.isNotEmpty;
    }
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

    final hintText = parseString('hintText') ?? defaults.hintText;

    return IdleConfig(
      enabled: parseBool('enabled', defaults.enabled),
      timeoutSec: parseInt('timeoutSec', defaults.timeoutSec),
      startOnLaunch: parseBool('startOnLaunch', defaults.startOnLaunch),
      mode: _parseIdleMode(json['mode']),
      image: parseString('image'),
      slideshow: slideshow,
      url: parseString('url'),
      showHint: parseBool('showHint', defaults.showHint),
      hintText: hintText,
    );
  }
}
