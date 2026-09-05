import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';

import '../model/idle_config.dart';
import '../service/gallery_feed_loader.dart';
import '../service/media_scanner.dart';
import '../service/video_controller_factory.dart';
import 'platform_file_image.dart';

/// 대기화면(attract screen) 위젯.
///
/// [IdleConfig.mode]에 따라 이미지, 슬라이드쇼, 폴더, 웹 갤러리 또는 URL을 표시한다.
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

    if (config.modes.length > 1) {
      content = _IdleMixedPlayer(config: config, onDismiss: onDismiss);
      absorbTaps = false;
    } else {
      switch (config.mode) {
        case IdleMode.image:
          content = _IdleImage(path: config.image!);
          absorbTaps = false;
          break;
        case IdleMode.slideshow:
          content = _IdleSlideshow(
            config: config.slideshow,
            onDismiss: onDismiss,
          );
          absorbTaps = false;
          break;
        case IdleMode.folder:
          content = _IdleFolderPlayer(
            config: config.folder,
            onDismiss: onDismiss,
          );
          absorbTaps = false;
          break;
        case IdleMode.gallery:
          content = _IdleGallery(
            config: config.gallery,
            onDismiss: onDismiss,
          );
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
              // 갤러리 모드의 게시물 제목 오버레이와 겹치지 않게 위로 띄운다.
              bottom: config.modes.contains(IdleMode.gallery) ? 150 : 48,
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _HintBadge(config: config),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // 순환 콘텐츠는 내부에서 탭과 스와이프를 구분하고 방향키 입력도 처리한다.
    if (config.modes.length > 1 ||
        config.mode == IdleMode.slideshow ||
        config.mode == IdleMode.folder ||
        config.mode == IdleMode.gallery) {
      return body;
    }

    // 나머지 모드는 화면 어디든 누르면 dismiss.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDismiss(),
      child: body,
    );
  }
}

/// 안내 배지.
class _HintBadge extends StatefulWidget {
  final IdleConfig config;
  const _HintBadge({required this.config});

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
      opacity: Tween(begin: 0.8, end: 1.0).animate(_ctrl),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.config.hintPaddingHorizontal,
          vertical: widget.config.hintPaddingVertical,
        ),
        decoration: BoxDecoration(
          color: widget.config.hintBackgroundColor,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 16, offset: Offset(0, 4))
          ],
        ),
        child: Text(
          widget.config.hintText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.config.hintTextColor,
            fontSize: widget.config.hintFontSize,
            fontWeight: FontWeight.w700,
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
  Widget build(BuildContext context) => SizedBox.expand(
        child: _idleImageForPath(path, fit: BoxFit.cover),
      );
}

Widget _idleImageForPath(String path, {required BoxFit fit, Key? key}) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Image.network(
      path,
      key: key,
      fit: fit,
      errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
    );
  }
  if (path.startsWith('assets/') || path.startsWith('asset/')) {
    return Image.asset(
      path,
      key: key,
      fit: fit,
      errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
    );
  }
  return PlatformFileImage(key: key, path: path, fit: fit);
}

VideoPlayerController _videoControllerForPath(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return VideoControllerFactory.network(path);
  }
  if (path.startsWith('assets/') || path.startsWith('asset/')) {
    return VideoControllerFactory.asset(path);
  }
  return VideoControllerFactory.file(path);
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
  final VoidCallback onDismiss;

  const _IdleSlideshow({required this.config, required this.onDismiss});

  @override
  State<_IdleSlideshow> createState() => _IdleSlideshowState();
}

class _IdleSlideshowState extends State<_IdleSlideshow> {
  int _index = 0;
  Timer? _timer;
  Timer? _youtubeLoadTimer;
  VideoPlayerController? _videoController;
  bool _videoListenerAttached = false;
  bool _videoLoadFailed = false;
  bool _youtubeLoadFailed = false;
  double _horizontalDragDistance = 0;

  @override
  void initState() {
    super.initState();
    _playCurrent();
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

  void _move(int offset) {
    if (widget.config.images.length < 2) return;
    _timer?.cancel();
    _youtubeLoadTimer?.cancel();
    _disposeVideo();
    setState(() {
      _index = (_index + offset) % widget.config.images.length;
      _videoLoadFailed = false;
      _youtubeLoadFailed = false;
    });
    _playCurrent();
  }

  void _playCurrent() {
    _timer?.cancel();
    _youtubeLoadTimer?.cancel();
    _disposeVideo();
    final path = widget.config.images[_index];
    final youtubeVideoId = parseYoutubeVideoId(path);
    if (youtubeVideoId != null) {
      _youtubeLoadTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) _onYoutubeError(path);
      });
      setState(() {});
    } else if (MediaScanner.isVideoPath(path)) {
      _startVideo(path);
    } else {
      _scheduleNext();
    }
  }

  Future<void> _startVideo(String path) async {
    final controller = _videoControllerForPath(path);
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoTick);
      _videoListenerAttached = true;
      await controller.setVolume(0);
      await controller.setLooping(widget.config.images.length == 1);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted || _videoController != controller) return;
      _disposeVideo();
      if (widget.config.images.length > 1) {
        _move(1);
      } else {
        setState(() => _videoLoadFailed = true);
      }
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.config.images.length > 1 &&
        controller.value.duration > Duration.zero &&
        controller.value.position >= controller.value.duration) {
      _move(1);
    }
  }

  void _onYoutubeReady(String path) {
    if (widget.config.images[_index] != path) return;
    _youtubeLoadTimer?.cancel();
    _youtubeLoadTimer = null;
  }

  void _onYoutubeEnded(String path) {
    if (widget.config.images[_index] != path) return;
    if (widget.config.images.length > 1) _move(1);
  }

  void _onYoutubeError(String path) {
    if (widget.config.images[_index] != path) return;
    _youtubeLoadTimer?.cancel();
    _youtubeLoadTimer = null;
    if (widget.config.images.length > 1) {
      _move(1);
    } else {
      setState(() => _youtubeLoadFailed = true);
    }
  }

  void _disposeVideo() {
    final controller = _videoController;
    if (controller == null) return;
    if (_videoListenerAttached) controller.removeListener(_onVideoTick);
    _videoListenerAttached = false;
    _videoController = null;
    controller.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _finishHorizontalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _horizontalDragDistance;
    _horizontalDragDistance = 0;
    if (distance.abs() >= 40) {
      _move(distance < 0 ? 1 : -1);
    } else if (velocity.abs() >= 250) {
      _move(velocity < 0 ? 1 : -1);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _youtubeLoadTimer?.cancel();
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.config.images[_index];
    final youtubeVideoId = parseYoutubeVideoId(path);
    if (youtubeVideoId != null) {
      final content = _youtubeLoadFailed
          ? Image.network(
              'https://i.ytimg.com/vi/$youtubeVideoId/hqdefault.jpg',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
            )
          : _YouTubeIdlePlayer(
              key: ValueKey(path),
              videoId: youtubeVideoId,
              loop: widget.config.images.length == 1,
              onReady: () => _onYoutubeReady(path),
              onEnded: () => _onYoutubeEnded(path),
              onError: () => _onYoutubeError(path),
            );
      return Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
          onHorizontalDragUpdate: (details) {
            _horizontalDragDistance += details.delta.dx;
          },
          onHorizontalDragEnd: _finishHorizontalDrag,
          child: ColoredBox(color: Colors.black, child: content),
        ),
      );
    }
    if (MediaScanner.isVideoPath(path)) {
      final controller = _videoController;
      final video = _videoLoadFailed
          ? const _IdleMediaFallback()
          : controller == null || !controller.value.isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                )
              : Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                );
      return Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
          onHorizontalDragUpdate: (details) {
            _horizontalDragDistance += details.delta.dx;
          },
          onHorizontalDragEnd: _finishHorizontalDrag,
          child: ColoredBox(
            key: ValueKey(path),
            color: Colors.black,
            child: video,
          ),
        ),
      );
    }
    final image = _idleImageForPath(
      path,
      key: ValueKey(path),
      fit: BoxFit.cover,
    );

    final content = widget.config.transition == SlideshowTransition.none
        ? SizedBox.expand(child: image)
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: SizedBox.expand(
              key: ValueKey(path),
              child: image,
            ),
          );
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _horizontalDragDistance += details.delta.dx;
        },
        onHorizontalDragEnd: _finishHorizontalDrag,
        child: content,
      ),
    );
  }
}

enum _MixedMediaKind {
  assetImage,
  networkImage,
  fileImage,
  assetVideo,
  fileVideo,
  networkVideo,
  youtube,
}

class _MixedMediaItem {
  final String id;
  final _MixedMediaKind kind;
  final String path;
  final String? title;
  final String? fallbackImagePath;
  final int intervalSec;
  final SlideshowTransition transition;
  final bool galleryImage;

  const _MixedMediaItem({
    required this.id,
    required this.kind,
    required this.path,
    required this.intervalSec,
    required this.transition,
    this.title,
    this.fallbackImagePath,
    this.galleryImage = false,
  });

  bool get isVideo =>
      kind == _MixedMediaKind.assetVideo ||
      kind == _MixedMediaKind.fileVideo ||
      kind == _MixedMediaKind.networkVideo;
  bool get isYoutube => kind == _MixedMediaKind.youtube;
}

class _MixedPlaybackSnapshot {
  final String currentId;
  final List<String> order;

  const _MixedPlaybackSnapshot({required this.currentId, required this.order});
}

final Map<String, _MixedPlaybackSnapshot> _mixedPlaybackMemory = {};

/// slideshow/folder/gallery의 콘텐츠를 하나의 탐색 가능한 재생 목록으로 합친다.
class _IdleMixedPlayer extends StatefulWidget {
  final IdleConfig config;
  final VoidCallback onDismiss;

  const _IdleMixedPlayer({required this.config, required this.onDismiss});

  @override
  State<_IdleMixedPlayer> createState() => _IdleMixedPlayerState();
}

class _IdleMixedPlayerState extends State<_IdleMixedPlayer> {
  late final GalleryFeedLoader _galleryLoader;
  List<_MixedMediaItem>? _items;
  String? _error;
  int _index = 0;
  Timer? _itemTimer;
  Timer? _refreshTimer;
  VideoPlayerController? _videoController;
  bool _videoListenerAttached = false;
  Timer? _youtubeLoadTimer;
  String? _youtubeReadyId;
  final Set<String> _failedYoutubeIds = {};
  bool _loading = false;
  double _horizontalDragDistance = 0;

  String get _memoryKey => [
        widget.config.modes.map((mode) => mode.name).join(','),
        widget.config.slideshow.images.join('|'),
        widget.config.folder.effectivePaths.join('|'),
        widget.config.gallery.playbackKey,
      ].join('::');

  @override
  void initState() {
    super.initState();
    _galleryLoader = GalleryFeedLoader();
    _load();
    if (widget.config.modes.contains(IdleMode.gallery)) {
      _refreshTimer = Timer.periodic(
        Duration(minutes: widget.config.gallery.refreshIntervalMin),
        (_) => _load(),
      );
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final byMode = <IdleMode, List<_MixedMediaItem>>{};

      if (widget.config.modes.contains(IdleMode.slideshow)) {
        byMode[IdleMode.slideshow] = widget.config.slideshow.images.map((path) {
          final network =
              path.startsWith('http://') || path.startsWith('https://');
          final isAsset =
              path.startsWith('assets/') || path.startsWith('asset/');
          final youtubeVideoId = parseYoutubeVideoId(path);
          final video = MediaScanner.isVideoPath(path);
          return _MixedMediaItem(
            id: 'slideshow:$path',
            kind: youtubeVideoId != null
                ? _MixedMediaKind.youtube
                : video
                    ? network
                        ? _MixedMediaKind.networkVideo
                        : isAsset
                            ? _MixedMediaKind.assetVideo
                            : _MixedMediaKind.fileVideo
                    : network
                        ? _MixedMediaKind.networkImage
                        : isAsset
                            ? _MixedMediaKind.assetImage
                            : _MixedMediaKind.fileImage,
            path: youtubeVideoId ?? path,
            fallbackImagePath: youtubeVideoId == null
                ? null
                : 'https://i.ytimg.com/vi/$youtubeVideoId/hqdefault.jpg',
            intervalSec: widget.config.slideshow.intervalSec,
            transition: widget.config.slideshow.transition,
          );
        }).toList(growable: false);
      }

      if (widget.config.modes.contains(IdleMode.folder)) {
        final groups = await Future.wait(
          widget.config.folder.effectivePaths.map((path) async {
            try {
              return await MediaScanner.scan(
                path: path,
                includeImages: widget.config.folder.includeImages,
                includeVideos: widget.config.folder.includeVideos,
              );
            } catch (_) {
              return const <MediaItem>[];
            }
          }),
        );
        final seen = <String>{};
        final media = groups
            .expand((group) => group)
            .where((item) => seen.add(item.path))
            .toList();
        if (widget.config.folder.shuffle) media.shuffle();
        byMode[IdleMode.folder] = media.map((item) {
          final kind = item.kind == MediaKind.video
              ? (item.isAsset
                  ? _MixedMediaKind.assetVideo
                  : _MixedMediaKind.fileVideo)
              : (item.isAsset
                  ? _MixedMediaKind.assetImage
                  : _MixedMediaKind.fileImage);
          return _MixedMediaItem(
            id: 'folder:${item.path}',
            kind: kind,
            path: item.path,
            intervalSec: widget.config.folder.intervalSec,
            transition: widget.config.folder.transition,
          );
        }).toList(growable: false);
      }

      if (widget.config.modes.contains(IdleMode.gallery)) {
        List<GalleryFeedItem> galleryItems;
        try {
          galleryItems = await _galleryLoader.load(widget.config.gallery);
        } catch (_) {
          galleryItems = const [];
        }
        final oldGalleryOrder = (_items ?? const <_MixedMediaItem>[])
            .where((item) => item.galleryImage)
            .map((item) => item.id.substring('gallery:'.length))
            .toList(growable: false);
        galleryItems = buildGalleryPlaybackOrder(
          galleryItems,
          shuffle: widget.config.gallery.shuffle,
          previousOrder: oldGalleryOrder,
        );
        byMode[IdleMode.gallery] = galleryItems
            .map(
              (item) => _MixedMediaItem(
                id: 'gallery:${item.playbackId}',
                kind: item.isYoutube
                    ? _MixedMediaKind.youtube
                    : _MixedMediaKind.networkImage,
                path: item.youtubeVideoId ?? item.imageUrl,
                fallbackImagePath: item.imageUrl,
                title: item.title,
                intervalSec: widget.config.gallery.intervalSec,
                transition: widget.config.gallery.transition,
                galleryImage: true,
              ),
            )
            .toList(growable: false);
      }

      var fresh = widget.config.modes
          .expand((mode) => byMode[mode] ?? const <_MixedMediaItem>[])
          .toList(growable: false);
      final oldItems = _items ?? const <_MixedMediaItem>[];
      final remembered = _mixedPlaybackMemory[_memoryKey];
      final previousOrder = oldItems.isNotEmpty
          ? oldItems.map((item) => item.id).toList(growable: false)
          : remembered?.order ?? const <String>[];
      if (previousOrder.isNotEmpty) {
        final byId = {for (final item in fresh) item.id: item};
        final used = <String>{};
        fresh = [
          for (final id in previousOrder)
            if (byId[id] case final item? when used.add(id)) item,
          for (final item in fresh)
            if (used.add(item.id)) item,
        ];
      }
      if (!mounted) return;
      if (fresh.isEmpty) {
        if (_items == null) {
          setState(() {
            _items = const [];
            _error = '복수 화면 보호기에서 표시할 미디어를 찾지 못했습니다.';
          });
        }
        return;
      }

      final currentId = oldItems.isNotEmpty && _index < oldItems.length
          ? oldItems[_index].id
          : remembered?.currentId;
      final nextIndex = currentId == null
          ? 0
          : fresh.indexWhere((item) => item.id == currentId);
      final currentPreserved = currentId != null && nextIndex >= 0;
      setState(() {
        _items = fresh;
        _index = nextIndex < 0 ? 0 : nextIndex;
        _error = null;
      });
      _remember();
      if (!currentPreserved) {
        _itemTimer?.cancel();
        _disposeVideo();
        _playCurrent();
      } else if (_itemTimer == null && _videoController == null) {
        _playCurrent();
      }
    } catch (error) {
      if (mounted && _items == null) {
        setState(() {
          _items = const [];
          _error = '복수 화면 보호기 로드 실패: $error';
        });
      }
    } finally {
      _loading = false;
    }
  }

  void _move(int offset) {
    final items = _items;
    if (items == null || items.length < 2) return;
    _itemTimer?.cancel();
    _youtubeLoadTimer?.cancel();
    _youtubeReadyId = null;
    _disposeVideo();
    setState(() => _index = (_index + offset) % items.length);
    _remember();
    _playCurrent();
  }

  void _playCurrent() {
    _itemTimer?.cancel();
    _youtubeLoadTimer?.cancel();
    _disposeVideo();
    final items = _items;
    if (items == null || items.isEmpty) return;
    final current = items[_index];
    if (current.isYoutube && !_failedYoutubeIds.contains(current.id)) {
      if (_youtubeReadyId != current.id) {
        _youtubeLoadTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) _onYoutubeError(current.id);
        });
      }
      setState(() {});
    } else if (current.isVideo) {
      _startVideo(current);
    } else {
      _itemTimer = Timer(Duration(seconds: current.intervalSec), () {
        if (mounted) _move(1);
      });
      setState(() {});
    }
  }

  void _onYoutubeReady(String itemId) {
    final items = _items;
    if (items == null || items.isEmpty || items[_index].id != itemId) return;
    _youtubeReadyId = itemId;
    _youtubeLoadTimer?.cancel();
    _youtubeLoadTimer = null;
  }

  void _onYoutubeEnded(String itemId) {
    final items = _items;
    if (items == null || items.isEmpty || items[_index].id != itemId) return;
    if (items.length > 1) _move(1);
  }

  void _onYoutubeError(String itemId) {
    final items = _items;
    if (items == null || items.isEmpty || items[_index].id != itemId) return;
    _youtubeLoadTimer?.cancel();
    _youtubeLoadTimer = null;
    _youtubeReadyId = null;
    _failedYoutubeIds.add(itemId);
    if (items.length > 1) {
      _move(1);
    } else {
      setState(() {});
    }
  }

  Future<void> _startVideo(_MixedMediaItem item) async {
    final controller = _videoControllerForPath(item.path);
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted || _videoController != controller) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoTick);
      _videoListenerAttached = true;
      await controller.setVolume(0);
      await controller.setLooping(false);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted || _videoController != controller) return;
      _disposeVideo();
      final items = _items;
      if (items == null || items.length < 2) {
        setState(() {
          _items = const [];
          _error = '재생할 수 있는 화면 보호기 동영상이 없습니다.';
        });
      } else {
        _move(1);
      }
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.duration > Duration.zero &&
        controller.value.position >= controller.value.duration) {
      _move(1);
    }
  }

  void _disposeVideo() {
    final controller = _videoController;
    if (controller == null) return;
    if (_videoListenerAttached) controller.removeListener(_onVideoTick);
    _videoListenerAttached = false;
    _videoController = null;
    controller.dispose();
  }

  void _remember() {
    final items = _items;
    if (items == null || items.isEmpty || _index >= items.length) return;
    _mixedPlaybackMemory[_memoryKey] = _MixedPlaybackSnapshot(
      currentId: items[_index].id,
      order: items.map((item) => item.id).toList(growable: false),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _withInput(Widget child) => Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
          onHorizontalDragUpdate: (details) {
            _horizontalDragDistance += details.delta.dx;
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            final distance = _horizontalDragDistance;
            _horizontalDragDistance = 0;
            if (distance.abs() >= 40) {
              _move(distance < 0 ? 1 : -1);
            } else if (velocity.abs() >= 250) {
              _move(velocity < 0 ? 1 : -1);
            }
          },
          child: child,
        ),
      );

  @override
  void dispose() {
    _remember();
    _itemTimer?.cancel();
    _youtubeLoadTimer?.cancel();
    _refreshTimer?.cancel();
    _disposeVideo();
    _galleryLoader.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _withInput(_FolderErrorView(message: _error!));
    final items = _items;
    if (items == null) {
      return _withInput(
        const Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }
    if (items.isEmpty) {
      return _withInput(const _FolderErrorView(message: '표시할 미디어가 없습니다.'));
    }
    final current = items[_index];
    Widget content;
    if (current.isYoutube && !_failedYoutubeIds.contains(current.id)) {
      content = _YouTubeIdlePlayer(
        key: ValueKey(current.id),
        videoId: current.path,
        loop: items.length == 1,
        onReady: () => _onYoutubeReady(current.id),
        onEnded: () => _onYoutubeEnded(current.id),
        onError: () => _onYoutubeError(current.id),
      );
    } else if (current.isVideo) {
      final controller = _videoController;
      content = controller == null || !controller.value.isInitialized
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white70))
          : Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            );
    } else {
      final image = switch (current.kind) {
        _MixedMediaKind.assetImage => Image.asset(
            current.path,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          ),
        _MixedMediaKind.fileImage => PlatformFileImage(
            path: current.path,
            fit: BoxFit.contain,
          ),
        _ => Image.network(
            current.fallbackImagePath ?? current.path,
            headers: current.galleryImage
                ? const {'User-Agent': 'SimpleKiosk/1.0 gallery-screen'}
                : null,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          ),
      };
      content = Stack(
        key: ValueKey(current.id),
        fit: StackFit.expand,
        children: [
          image,
          if (current.title case final title? when title.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(48, 54, 48, 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      );
      if (current.transition == SlideshowTransition.fade) {
        content = AnimatedSwitcher(
          duration: const Duration(milliseconds: 650),
          child: content,
        );
      }
    }
    return _withInput(ColoredBox(color: Colors.black, child: content));
  }
}

/// 포토갤러리 최신 게시물의 원본 사진과 제목을 순환 표시한다.
class _IdleGallery extends StatefulWidget {
  final GalleryConfig config;
  final VoidCallback onDismiss;

  const _IdleGallery({required this.config, required this.onDismiss});

  @override
  State<_IdleGallery> createState() => _IdleGalleryState();
}

class _GalleryPlaybackSnapshot {
  final String currentImageUrl;
  final List<String> order;

  const _GalleryPlaybackSnapshot({
    required this.currentImageUrl,
    required this.order,
  });
}

final Map<String, _GalleryPlaybackSnapshot> _galleryPlaybackMemory = {};

/// 랜덤 모드의 재생 순서를 미리 만든다. 기존 항목의 순서는 유지하고 새 항목만 섞어 넣는다.
List<GalleryFeedItem> buildGalleryPlaybackOrder(
  List<GalleryFeedItem> freshItems, {
  required bool shuffle,
  List<String> previousOrder = const [],
  Random? random,
}) {
  if (!shuffle) return List<GalleryFeedItem>.of(freshItems);
  final generator = random ?? Random();
  final byUrl = {for (final item in freshItems) item.playbackId: item};
  final used = <String>{};
  final ordered = <GalleryFeedItem>[];

  for (final url in previousOrder) {
    final item = byUrl[url];
    if (item != null && used.add(url)) ordered.add(item);
  }

  final added = freshItems
      .where((item) => used.add(item.playbackId))
      .toList(growable: false);
  if (ordered.isEmpty) {
    return List<GalleryFeedItem>.of(added)..shuffle(generator);
  }
  for (final item in added) {
    ordered.insert(generator.nextInt(ordered.length + 1), item);
  }
  return ordered;
}

int galleryInitialIndex(
  List<GalleryFeedItem> items,
  String? rememberedImageUrl,
) {
  if (items.isEmpty || rememberedImageUrl == null) return 0;
  final index = items.indexWhere(
    (item) => item.playbackId == rememberedImageUrl,
  );
  return index < 0 ? 0 : index;
}

/// 갤러리 갱신 후 현재 사진이 있으면 그 위치를, 없으면 기존 진행 위치를 유지한다.
int galleryIndexAfterRefresh(
  List<GalleryFeedItem> oldItems,
  int oldIndex,
  List<GalleryFeedItem> newItems,
) {
  if (newItems.isEmpty) return 0;
  if (oldItems.isEmpty || oldIndex < 0 || oldIndex >= oldItems.length) {
    return 0;
  }
  final currentUrl = oldItems[oldIndex].playbackId;
  final matchedIndex = newItems.indexWhere(
    (item) => item.playbackId == currentUrl,
  );
  if (matchedIndex >= 0) return matchedIndex;
  return oldIndex < newItems.length ? oldIndex : newItems.length - 1;
}

class _IdleGalleryState extends State<_IdleGallery> {
  late final GalleryFeedLoader _loader;
  List<GalleryFeedItem>? _items;
  String? _error;
  int _index = 0;
  Timer? _slideTimer;
  Timer? _refreshTimer;
  bool _loadInProgress = false;
  Timer? _youtubeLoadTimer;
  String? _youtubeReadyId;
  final Set<String> _failedYoutubeIds = {};
  double _horizontalDragDistance = 0;

  @override
  void initState() {
    super.initState();
    _loader = GalleryFeedLoader();
    _load();
    _scheduleRefresh();
  }

  Future<void> _load() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    try {
      final freshItems = await _loader.load(widget.config);
      if (!mounted) return;
      final oldItems = _items ?? const <GalleryFeedItem>[];
      final remembered = _galleryPlaybackMemory[widget.config.playbackKey];
      final previousOrder = oldItems.isNotEmpty
          ? oldItems.map((item) => item.playbackId).toList(growable: false)
          : remembered?.order ?? const <String>[];
      final items = buildGalleryPlaybackOrder(
        freshItems,
        shuffle: widget.config.shuffle,
        previousOrder: previousOrder,
      );
      final nextIndex = oldItems.isNotEmpty
          ? galleryIndexAfterRefresh(oldItems, _index, items)
          : galleryInitialIndex(items, remembered?.currentImageUrl);
      setState(() {
        _items = items;
        _error = null;
        _index = nextIndex;
      });
      _rememberCurrentPosition();
      _precacheNext();
      if (_slideTimer == null) _scheduleNext();
    } catch (error) {
      if (!mounted) return;
      // 주기 갱신 실패 시 재생 중인 기존 목록은 유지한다.
      if (_items == null) {
        setState(() {
          _items = const [];
          _error = '포토갤러리를 불러오지 못했습니다.\n$error';
        });
      }
    } finally {
      _loadInProgress = false;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      Duration(minutes: widget.config.refreshIntervalMin),
      (_) => _load(),
    );
  }

  void _scheduleNext() {
    _slideTimer?.cancel();
    _youtubeLoadTimer?.cancel();
    final items = _items;
    if (items == null || items.isEmpty) {
      _slideTimer = null;
      return;
    }
    final current = items[_index];
    if (current.isYoutube && !_failedYoutubeIds.contains(current.playbackId)) {
      if (_youtubeReadyId != current.playbackId) {
        _youtubeLoadTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) _onYoutubeError(current.playbackId);
        });
      }
      _slideTimer = null;
      return;
    }
    if (items.length < 2) {
      _slideTimer = null;
      return;
    }
    _slideTimer = Timer(Duration(seconds: widget.config.intervalSec), () {
      if (!mounted) return;
      _slideTimer = null;
      _move(1);
    });
  }

  void _move(int offset) {
    final items = _items;
    if (items == null || items.length < 2) return;
    _slideTimer?.cancel();
    _youtubeLoadTimer?.cancel();
    _youtubeReadyId = null;
    setState(() {
      _index = (_index + offset) % items.length;
    });
    _rememberCurrentPosition();
    _precacheNext();
    _scheduleNext();
  }

  void _rememberCurrentPosition() {
    final items = _items;
    if (items == null || items.isEmpty || _index >= items.length) return;
    _galleryPlaybackMemory[widget.config.playbackKey] =
        _GalleryPlaybackSnapshot(
      currentImageUrl: items[_index].playbackId,
      order: items.map((item) => item.playbackId).toList(growable: false),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _finishHorizontalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _horizontalDragDistance;
    _horizontalDragDistance = 0;
    if (distance.abs() >= 40) {
      _move(distance < 0 ? 1 : -1);
    } else if (velocity.abs() >= 250) {
      _move(velocity < 0 ? 1 : -1);
    }
  }

  void _precacheNext() {
    final items = _items;
    if (items == null || items.length < 2) return;
    final next = items[(_index + 1) % items.length];
    precacheImage(
      NetworkImage(
        next.imageUrl,
        headers: const {'User-Agent': 'SimpleKiosk/1.0 gallery-screen'},
      ),
      context,
    ).catchError((_) {});
  }

  void _onYoutubeReady(String playbackId) {
    final items = _items;
    if (items == null ||
        items.isEmpty ||
        items[_index].playbackId != playbackId) {
      return;
    }
    _youtubeReadyId = playbackId;
    _youtubeLoadTimer?.cancel();
    _youtubeLoadTimer = null;
  }

  void _onYoutubeEnded(String playbackId) {
    final items = _items;
    if (items == null ||
        items.isEmpty ||
        items[_index].playbackId != playbackId) {
      return;
    }
    if (items.length > 1) _move(1);
  }

  void _onYoutubeError(String playbackId) {
    final items = _items;
    if (items == null ||
        items.isEmpty ||
        items[_index].playbackId != playbackId) {
      return;
    }
    _youtubeLoadTimer?.cancel();
    _youtubeLoadTimer = null;
    _youtubeReadyId = null;
    _failedYoutubeIds.add(playbackId);
    if (items.length > 1) {
      _move(1);
    } else {
      setState(() {});
    }
  }

  Widget _withInput(Widget child) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _horizontalDragDistance += details.delta.dx;
        },
        onHorizontalDragEnd: _finishHorizontalDrag,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _rememberCurrentPosition();
    _slideTimer?.cancel();
    _youtubeLoadTimer?.cancel();
    _refreshTimer?.cancel();
    _loader.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return _withInput(_FolderErrorView(message: error));
    final items = _items;
    if (items == null) {
      return _withInput(
        const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }
    if (items.isEmpty) {
      return _withInput(
        const _FolderErrorView(message: '포토갤러리에 표시할 사진이 없습니다.'),
      );
    }

    final item = items[_index];
    final slide = Stack(
      key: ValueKey(item.playbackId),
      fit: StackFit.expand,
      children: [
        if (item.isYoutube && !_failedYoutubeIds.contains(item.playbackId))
          _YouTubeIdlePlayer(
            videoId: item.youtubeVideoId!,
            loop: items.length == 1,
            onReady: () => _onYoutubeReady(item.playbackId),
            onEnded: () => _onYoutubeEnded(item.playbackId),
            onError: () => _onYoutubeError(item.playbackId),
          )
        else
          Image.network(
            item.imageUrl,
            headers: const {'User-Agent': 'SimpleKiosk/1.0 gallery-screen'},
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              );
            },
            errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(48, 54, 48, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xE6000000)],
              ),
            ),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.25,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        ),
      ],
    );

    final content = widget.config.transition == SlideshowTransition.none
        ? ColoredBox(color: Colors.black, child: slide)
        : ColoredBox(
            color: Colors.black,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 650),
              child: slide,
            ),
          );
    return _withInput(content);
  }
}

String buildYoutubePlayerHtml(String videoId, {required bool loop}) {
  final encodedVideoId = jsonEncode(videoId);
  return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
  <style>
    html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}
  </style>
</head>
<body>
  <div id="player"></div>
  <script src="https://www.youtube.com/iframe_api"></script>
  <script>
    let player;
    let playingReported=false;
    const notify=(event,value)=>window.flutter_inappwebview
      ?.callHandler('youtubePlaybackEvent',event,value??null);
    function onYouTubeIframeAPIReady(){
      player=new YT.Player('player',{
        width:'100%',height:'100%',videoId:$encodedVideoId,
        playerVars:{
          autoplay:1,controls:0,disablekb:1,fs:0,playsinline:1,
          rel:0,mute:0,enablejsapi:1,origin:'https://www.youtube.com'
        },
        events:{
          onReady:event=>{
            event.target.unMute();
            event.target.setVolume(100);
            event.target.playVideo();
          },
          onStateChange:event=>{
            if(event.data===YT.PlayerState.PLAYING&&!playingReported){
              playingReported=true;
              notify('playing');
            }
            if(event.data===YT.PlayerState.ENDED){
              if(${loop ? 'true' : 'false'}){
                event.target.seekTo(0,true);
                event.target.unMute();
                event.target.setVolume(100);
                event.target.playVideo();
              }else{
                notify('ended');
              }
            }
          },
          onError:event=>notify('error',event.data)
        }
      });
    }
  </script>
</body>
</html>
''';
}

class _YouTubeIdlePlayer extends StatelessWidget {
  final String videoId;
  final bool loop;
  final VoidCallback onReady;
  final VoidCallback onEnded;
  final VoidCallback onError;

  const _YouTubeIdlePlayer({
    super.key,
    required this.videoId,
    required this.loop,
    required this.onReady,
    required this.onEnded,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: buildYoutubePlayerHtml(videoId, loop: loop),
          baseUrl: WebUri('https://www.youtube.com/'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          supportZoom: false,
          transparentBackground: false,
        ),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'youtubePlaybackEvent',
            callback: (arguments) {
              final event = arguments.isEmpty ? null : arguments.first;
              if (event == 'playing') {
                onReady();
              } else if (event == 'ended') {
                onEnded();
              } else if (event == 'error') {
                onError();
              }
              return null;
            },
          );
        },
      ),
    );
  }
}

/// 풀스크린 URL WebView.
///
/// 사용자가 페이지 내부 링크를 클릭하는 것을 막기 위해 호출자에서 위에
/// [AbsorbPointer] 를 깔아 탭을 가로채고 dismiss 처리한다.
class _IdleUrl extends StatefulWidget {
  final String url;
  const _IdleUrl({required this.url});

  @override
  State<_IdleUrl> createState() => _IdleUrlState();
}

class _IdleUrlState extends State<_IdleUrl> {
  Timer? _youtubeLoadTimer;
  bool _youtubeLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _startYoutubeLoadTimer();
  }

  @override
  void didUpdateWidget(covariant _IdleUrl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _youtubeLoadTimer?.cancel();
    _youtubeLoadFailed = false;
    _startYoutubeLoadTimer();
  }

  void _startYoutubeLoadTimer() {
    if (parseYoutubeVideoId(widget.url) == null) return;
    _youtubeLoadTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _youtubeLoadFailed = true);
    });
  }

  @override
  void dispose() {
    _youtubeLoadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final youtubeVideoId = parseYoutubeVideoId(widget.url);
    if (youtubeVideoId != null) {
      if (_youtubeLoadFailed) {
        return Image.network(
          'https://i.ytimg.com/vi/$youtubeVideoId/hqdefault.jpg',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _IdleMediaFallback(),
        );
      }
      return _YouTubeIdlePlayer(
        key: ValueKey('idle-url-youtube:$youtubeVideoId'),
        videoId: youtubeVideoId,
        loop: true,
        onReady: () {
          _youtubeLoadTimer?.cancel();
          _youtubeLoadTimer = null;
        },
        onEnded: () {},
        onError: () {
          _youtubeLoadTimer?.cancel();
          _youtubeLoadTimer = null;
          if (mounted) setState(() => _youtubeLoadFailed = true);
        },
      );
    }
    return InAppWebView(
      key: ValueKey('idle-url:${widget.url}'),
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
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
        if (current == widget.url) return NavigationActionPolicy.ALLOW;
        return NavigationActionPolicy.CANCEL;
      },
    );
  }
}

/// 폴더 순회 플레이어: 이미지와 동영상이 섞인 폴더를 자동 재생.
class _IdleFolderPlayer extends StatefulWidget {
  final FolderConfig config;
  final VoidCallback onDismiss;

  const _IdleFolderPlayer({
    required this.config,
    required this.onDismiss,
  });

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
  double _horizontalDragDistance = 0;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    try {
      final groups = await Future.wait(
        widget.config.effectivePaths.map(
          (path) async {
            try {
              return await MediaScanner.scan(
                path: path,
                includeImages: widget.config.includeImages,
                includeVideos: widget.config.includeVideos,
              );
            } catch (_) {
              return const <MediaItem>[];
            }
          },
        ),
      );
      final seen = <String>{};
      var items = groups
          .expand((group) => group)
          .where((item) => seen.add(item.path))
          .toList(growable: false);
      if (widget.config.shuffle) {
        items = List<MediaItem>.from(items)..shuffle();
      }
      if (!mounted) return;
      if (items.isEmpty) {
        setState(() {
          _items = const [];
          _error = '폴더에서 표시할 미디어를 찾지 못했습니다.\n'
              '경로: ${widget.config.effectivePaths.join(', ')}';
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
    _move(1);
  }

  void _move(int offset) {
    final items = _items;
    if (items == null || items.isEmpty) return;
    _imageTimer?.cancel();
    _disposeVideo();
    setState(() => _index = (_index + offset) % items.length);
    _playCurrent();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _finishHorizontalDrag(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _horizontalDragDistance;
    _horizontalDragDistance = 0;
    if (distance.abs() >= 40) {
      _move(distance < 0 ? 1 : -1);
    } else if (velocity.abs() >= 250) {
      _move(velocity < 0 ? 1 : -1);
    }
  }

  Widget _withInput(Widget child) => Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
          onHorizontalDragUpdate: (details) {
            _horizontalDragDistance += details.delta.dx;
          },
          onHorizontalDragEnd: _finishHorizontalDrag,
          child: child,
        ),
      );

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

      await controller.setVolume(0); // 사이니지: 기본 무음(원하면 옵션화 가능).
      await controller.setLooping(false);
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      // 재생 실패 시 다음 항목으로 이동하되, 단일 항목은 반복 재시도하지 않는다.
      if (!mounted || _videoController != controller) return;
      _disposeVideo();
      final items = _items;
      if (items == null || items.length < 2) {
        setState(() {
          _items = const [];
          _error = '동영상을 재생할 수 없습니다: ${item.path}';
        });
      } else {
        _next();
      }
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
      return _withInput(_FolderErrorView(message: _error!));
    }
    final items = _items;
    if (items == null) {
      return _withInput(
        const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }
    if (items.isEmpty) {
      return _withInput(
        const _FolderErrorView(message: '표시할 미디어가 없습니다.'),
      );
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
      return _withInput(Container(color: Colors.black, child: img));
    }

    // 비디오.
    final c = _videoController;
    if (c == null || !c.value.isInitialized) {
      return _withInput(
        const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }
    return _withInput(
      Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio:
                c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
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
