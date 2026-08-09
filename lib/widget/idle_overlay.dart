import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';

import '../model/idle_config.dart';
import '../service/media_scanner.dart';
import '../service/video_controller_factory.dart';
import 'platform_file_image.dart';

/// 대기화면(attract screen) 위젯.
///
/// [IdleConfig.mode] 에 따라 단일 이미지, 슬라이드쇼, 풀스크린 URL WebView를 표시한다.
/// 화면 어디든 탭하면 [onDismiss] 가 호출된다.
class IdleOverlay extends StatelessWidget {
  final IdleConfig config;
  final VoidCallback onDismiss;

  const IdleOverlay({
    super.key,
    required this.config,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    bool absorbTaps; // url 모드는 WebView 위에서 탭을 가로채야 한다.

    switch (config.mode) {
      case IdleMode.image:
        content = _IdleImage(path: config.image!);
        absorbTaps = false;
        break;
      case IdleMode.slideshow:
        content = _IdleSlideshow(config: config.slideshow);
        absorbTaps = false;
        break;
      case IdleMode.folder:
        content = _IdleFolderPlayer(config: config.folder);
        absorbTaps = false;
        break;
      case IdleMode.url:
        content = _IdleUrl(url: config.url!);
        absorbTaps = true;
        break;
      case IdleMode.none:
        content = const SizedBox.shrink();
        absorbTaps = false;
        break;
    }

    final body = Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: content),

          // URL 모드: WebView가 자체적으로 입력을 먹어버리지 않도록 위에 투명 레이어를
          // 깔아서 모든 포인터 이벤트를 우리가 가로챈다.
          if (absorbTaps)
            const Positioned.fill(
              child: AbsorbPointer(absorbing: true, child: SizedBox.expand()),
            ),

          if (config.showHint && config.hintText.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: IgnorePointer(
                child: Center(
                  child: _HintBadge(text: config.hintText),
                ),
              ),
            ),
        ],
      ),
    );

    // 화면 어디든 탭하면 dismiss.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDismiss(),
      child: body,
    );
  }
}

/// 안내 배지.
class _HintBadge extends StatefulWidget {
  final String text;
  const _HintBadge({required this.text});

  @override
  State<_HintBadge> createState() => _HintBadgeState();
}

class _HintBadgeState extends State<_HintBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_ctrl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          widget.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// 단일 이미지.
class _IdleImage extends StatelessWidget {
  final String path;
  const _IdleImage({required this.path});

  @override
  Widget build(BuildContext context) {
    final isNetwork = path.startsWith('http://') || path.startsWith('https://');
    final image = isNetwork
        ? Image.network(
            path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          )
        : Image.asset(
            path,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          );
    return SizedBox.expand(child: image);
  }
}

/// 설정된 대기 이미지가 없거나 네트워크에서 읽히지 않을 때 표시하는 안전 화면.
///
/// 운영 중 콘텐츠 파일 하나가 빠져도 이미지 디코딩 오류가 화면 전체를 깨뜨리지
/// 않도록 한다. 하단의 터치 안내는 [IdleOverlay]가 그대로 겹쳐 표시한다.
class _IdleMediaFallback extends StatelessWidget {
  const _IdleMediaFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF111827),
      child: Center(
        child: Icon(
          Icons.church_outlined,
          size: 120,
          color: Color(0xFFD1D5DB),
        ),
      ),
    );
  }
}

/// 이미지 슬라이드쇼.
class _IdleSlideshow extends StatefulWidget {
  final SlideshowConfig config;
  const _IdleSlideshow({required this.config});

  @override
  State<_IdleSlideshow> createState() => _IdleSlideshowState();
}

class _IdleSlideshowState extends State<_IdleSlideshow> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: widget.config.intervalSec), () {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.config.images.length;
      });
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.config.images[_index];
    final isNetwork = path.startsWith('http://') || path.startsWith('https://');
    final image = isNetwork
        ? Image.network(
            path,
            key: ValueKey(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          )
        : Image.asset(
            path,
            key: ValueKey(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          );

    if (widget.config.transition == SlideshowTransition.none) {
      return SizedBox.expand(child: image);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: SizedBox.expand(
        key: ValueKey(path),
        child: image,
      ),
    );
  }
}

/// 풀스크린 URL WebView.
///
/// 사용자가 페이지 내부 링크를 클릭하는 것을 막기 위해 호출자에서 위에
/// [AbsorbPointer] 를 깔아 탭을 가로채고 dismiss 처리한다.
class _IdleUrl extends StatelessWidget {
  final String url;
  const _IdleUrl({required this.url});

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        transparentBackground: false,
        // 대기화면 내부 네비게이션 차단.
        useShouldOverrideUrlLoading: true,
      ),
      shouldOverrideUrlLoading: (controller, navAction) async {
        // 최초 로드만 허용하고, 그 외 URL 이동은 모두 차단(대기화면 콘텐츠 고정).
        if (navAction.isForMainFrame == false) {
          return NavigationActionPolicy.ALLOW;
        }
        final current = navAction.request.url?.toString();
        if (current == url) return NavigationActionPolicy.ALLOW;
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}

/// 폴더 순회 플레이어: 이미지와 동영상이 섞인 폴더를 자동 재생.
class _IdleFolderPlayer extends StatefulWidget {
  final FolderConfig config;
  const _IdleFolderPlayer({required this.config});

  @override
  State<_IdleFolderPlayer> createState() => _IdleFolderPlayerState();
}

class _IdleFolderPlayerState extends State<_IdleFolderPlayer> {
  List<MediaItem>? _items;
  String? _error;
  int _index = 0;

  Timer? _imageTimer;
  VideoPlayerController? _videoController;
  bool _videoListenerAttached = false;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    try {
      var items = await MediaScanner.scan(
        path: widget.config.path,
        includeImages: widget.config.includeImages,
        includeVideos: widget.config.includeVideos,
      );
      if (widget.config.shuffle) {
        items = List<MediaItem>.from(items)..shuffle();
      }
      if (!mounted) return;
      if (items.isEmpty) {
        setState(() {
          _items = const [];
          _error = '폴더에서 표시할 미디어를 찾지 못했습니다.\n경로: ${widget.config.path}';
        });
        return;
      }
      setState(() {
        _items = items;
        _index = 0;
        _error = null;
      });
      _playCurrent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _error = '폴더 스캔 실패: $e';
      });
    }
  }

  void _next() {
    final items = _items;
    if (items == null || items.isEmpty) return;
    setState(() => _index = (_index + 1) % items.length);
    _playCurrent();
  }

  void _playCurrent() {
    _imageTimer?.cancel();
    _disposeVideo();

    final items = _items;
    if (items == null || items.isEmpty) return;
    final cur = items[_index];

    if (cur.kind == MediaKind.image) {
      _imageTimer = Timer(
        Duration(seconds: widget.config.intervalSec),
        () {
          if (!mounted) return;
          _next();
        },
      );
      // 이미지 표시 자체는 build()가 처리.
      setState(() {});
    } else {
      _startVideo(cur);
    }
  }

  Future<void> _startVideo(MediaItem item) async {
    final controller = item.isAsset
        ? VideoControllerFactory.asset(item.path)
        : VideoControllerFactory.file(item.path);

    _videoController = controller;
    _videoListenerAttached = false;
    setState(() {}); // 로딩 표시.

    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) {
        // 이미 다른 항목으로 넘어감.
        await controller.dispose();
        return;
      }
      // 영상 종료 감지: 끝까지 재생되면 다음 항목으로.
      controller.addListener(_onVideoTick);
      _videoListenerAttached = true;

      await controller.setVolume(0); // 키오스크: 기본 무음(원하면 옵션화 가능).
      await controller.setLooping(false);
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      // 재생 실패 → 다음 항목으로.
      if (!mounted) return;
      _next();
    }
  }

  void _onVideoTick() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur > Duration.zero && pos >= dur) {
      _next();
    }
  }

  void _disposeVideo() {
    final c = _videoController;
    if (c == null) return;
    if (_videoListenerAttached) {
      c.removeListener(_onVideoTick);
      _videoListenerAttached = false;
    }
    _videoController = null;
    // dispose는 비동기지만 await하지 않음(다음 콘텐츠 우선).
    c.dispose();
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _FolderErrorView(message: _error!);
    }
    final items = _items;
    if (items == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    if (items.isEmpty) {
      return const _FolderErrorView(message: '표시할 미디어가 없습니다.');
    }

    final cur = items[_index];
    if (cur.kind == MediaKind.image) {
      Widget img = cur.isAsset
          ? Image.asset(
              cur.path,
              key: ValueKey('img:${cur.path}'),
              fit: BoxFit.contain,
            )
          : PlatformFileImage(
              key: ValueKey('img:${cur.path}'),
              path: cur.path,
              fit: BoxFit.contain,
            );

      final transition = widget.config.transition;
      if (transition == SlideshowTransition.fade) {
        img = AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: SizedBox.expand(
            key: ValueKey(cur.path),
            child: img,
          ),
        );
      } else {
        img = SizedBox.expand(child: img);
      }
      return Container(color: Colors.black, child: img);
    }

    // 비디오.
    final c = _videoController;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

class _FolderErrorView extends StatelessWidget {
  final String message;
  const _FolderErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white70, fontSize: 18),
        textAlign: TextAlign.center,
      ),
    );
  }
}
