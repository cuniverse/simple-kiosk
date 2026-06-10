import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../model/idle_config.dart';

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
    final isNetwork =
        path.startsWith('http://') || path.startsWith('https://');
    final image = isNetwork
        ? Image.network(path, fit: BoxFit.cover)
        : Image.asset(path, fit: BoxFit.cover);
    return SizedBox.expand(child: image);
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
    final isNetwork =
        path.startsWith('http://') || path.startsWith('https://');
    final image = isNetwork
        ? Image.network(
            path,
            key: ValueKey(path),
            fit: BoxFit.cover,
          )
        : Image.asset(
            path,
            key: ValueKey(path),
            fit: BoxFit.cover,
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
