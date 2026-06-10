import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 키오스크용 WebView 위젯.
///
/// 주요 정책:
/// - JavaScript 허용
/// - HTML5 video 인라인 재생
/// - 새 창 / 팝업 / 외부 스킴(tel:, mailto:, intent: 등) 차단
/// - 다운로드 차단
/// - 로딩/에러 상태 표시
/// - 외부에서 [KioskWebViewController]로 URL 변경, 뒤로가기 제어
class KioskWebView extends StatefulWidget {
  /// 최초로 로드할 URL.
  final String initialUrl;

  /// 컨트롤러를 외부에 노출하기 위한 콜백.
  final ValueChanged<KioskWebViewController>? onReady;

  const KioskWebView({
    super.key,
    required this.initialUrl,
    this.onReady,
  });

  @override
  State<KioskWebView> createState() => _KioskWebViewState();
}

/// WebView 네비게이션 상태(뒤/앞 버튼 활성화용).
class WebNavState {
  final bool canGoBack;
  final bool canGoForward;

  const WebNavState({
    required this.canGoBack,
    required this.canGoForward,
  });

  static const empty = WebNavState(canGoBack: false, canGoForward: false);

  @override
  bool operator ==(Object other) =>
      other is WebNavState &&
      other.canGoBack == canGoBack &&
      other.canGoForward == canGoForward;

  @override
  int get hashCode => Object.hash(canGoBack, canGoForward);
}

/// 외부에서 WebView를 제어하기 위한 컨트롤러.
///
/// 플랫폼 WebView의 `canGoBack/Forward()` 는 환경에 따라 신뢰성이 다르므로
/// (특히 Flutter Web의 iframe 환경) 자체 히스토리 스택으로 뒤/앞 이동을
/// 관리한다. 메뉴 클릭으로 URL이 바뀌거나, 페이지 내 링크 클릭으로
/// `onLoadStart` 가 새 URL과 함께 호출될 때마다 스택에 푸시한다.
class KioskWebViewController {
  final InAppWebViewController _controller;
  final ValueNotifier<WebNavState> navState;

  // 히스토리 스택과 현재 인덱스(0..length-1). 비어있으면 빈 상태.
  final List<String> _history = [];
  int _index = -1;

  // goBack/goForward 로 이동 중일 때 onLoadStart 의 자동 푸시를 막기 위한 플래그.
  bool _navigatingHistory = false;

  KioskWebViewController._(this._controller)
      : navState = ValueNotifier(WebNavState.empty);

  WebNavState _computeState() => WebNavState(
        canGoBack: _index > 0,
        canGoForward: _index >= 0 && _index < _history.length - 1,
      );

  void _publishState() {
    navState.value = _computeState();
  }

  /// 새로운 URL을 히스토리에 푸시한다.
  /// - 현재 위치 뒤쪽의 항목들은 잘려나가고 새 항목이 추가된다(브라우저 기본 동작).
  /// - 직전 URL과 같으면 중복으로 추가하지 않는다.
  void _pushHistory(String url) {
    if (_index >= 0 && _history[_index] == url) return;
    if (_index < _history.length - 1) {
      _history.removeRange(_index + 1, _history.length);
    }
    _history.add(url);
    _index = _history.length - 1;
    _publishState();
  }

  /// 메뉴 선택 등으로 명시적으로 새 URL을 로드한다(히스토리에 푸시됨).
  Future<void> loadUrl(String url) async {
    _pushHistory(url);
    await _controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  /// 뒤로 갈 수 있는지 여부.
  bool canGoBackSync() => _index > 0;

  /// 앞으로 갈 수 있는지 여부.
  bool canGoForwardSync() => _index >= 0 && _index < _history.length - 1;

  /// 비동기 호환용(기존 API 유지).
  Future<bool> canGoBack() async => canGoBackSync();
  Future<bool> canGoForward() async => canGoForwardSync();

  /// 자체 스택으로 뒤로 이동.
  Future<void> goBack() async {
    if (!canGoBackSync()) return;
    _index -= 1;
    _publishState();
    await _loadHistoryEntry();
  }

  /// 자체 스택으로 앞으로 이동.
  Future<void> goForward() async {
    if (!canGoForwardSync()) return;
    _index += 1;
    _publishState();
    await _loadHistoryEntry();
  }

  Future<void> _loadHistoryEntry() async {
    final url = _history[_index];
    _navigatingHistory = true;
    try {
      await _controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    } finally {
      // 로드 콜백이 끝날 시점까지 잠깐 보호.
      Future.delayed(const Duration(milliseconds: 300), () {
        _navigatingHistory = false;
      });
    }
  }

  /// 현재 페이지를 다시 로드한다.
  Future<void> reload() => _controller.reload();

  /// WebView 내부에서 발생한 네비게이션(페이지 내 링크 클릭 등)을 히스토리에
  /// 반영한다. 호출자는 [_KioskWebViewState] 의 `onLoadStart`.
  void _noteNavigationStart(String? url) {
    if (url == null || url.isEmpty) return;
    if (url == 'about:blank') return;
    if (_navigatingHistory) return; // goBack/goForward 중에는 무시.
    _pushHistory(url);
  }
}

class _KioskWebViewState extends State<KioskWebView> {
  InAppWebViewController? _webController;
  KioskWebViewController? _kioskController;

  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUrl;

  /// `onLoadStop`/`onProgressChanged` 이벤트가 도착하지 않을 경우(특히
  /// 웹 타겟의 cross-origin iframe) 로딩 표시가 영원히 남는 것을 방지하는
  /// 안전망 타이머.
  Timer? _loadingFallback;
  static const Duration _loadingTimeout = Duration(seconds: 8);

  void _scheduleLoadingFallback() {
    _loadingFallback?.cancel();
    _loadingFallback = Timer(_loadingTimeout, () {
      if (!mounted) return;
      if (_isLoading) {
        setState(() => _isLoading = false);
      }
    });
  }

  void _finishLoading() {
    _loadingFallback?.cancel();
    if (_isLoading) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _loadingFallback?.cancel();
    super.dispose();
  }

  // WebView 동작 정책 설정.
  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    // shouldOverrideUrlLoading 콜백 사용 활성화.
    useShouldOverrideUrlLoading: true,
    // 새 창 차단 정책과 함께 동작.
    javaScriptCanOpenWindowsAutomatically: false,
    supportMultipleWindows: false,
    // HTML5 video 인라인 재생 허용 (자동재생은 사이트/브라우저 정책 영향).
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    // 운영에서는 HTTPS 사용을 권장한다. 필요 시 HTTP도 허용.
    allowsBackForwardNavigationGestures: false,
    transparentBackground: false,
    useHybridComposition: true,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
            initialSettings: _settings,
            onWebViewCreated: (controller) {
              _webController = controller;
              final kc = KioskWebViewController._(controller);
              _kioskController = kc;
              // 초기 URL을 히스토리 스택의 첫 항목으로 등록.
              kc._noteNavigationStart(widget.initialUrl);
              widget.onReady?.call(kc);
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _isLoading = true;
                _errorMessage = null;
                _currentUrl = url?.toString();
              });
              _scheduleLoadingFallback();
              _kioskController?._noteNavigationStart(url?.toString());
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() {
                _currentUrl = url?.toString();
              });
              _finishLoading();
              // 일부 사이트는 onLoadStart 없이 리다이렉트만 되는 경우도 있으므로 공식
              // 종료 시점의 url 도 히스토리에 안전하게 포함시킨다(중복은 자체 필터됨).
              _kioskController?._noteNavigationStart(url?.toString());
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              if (progress >= 100) {
                _finishLoading();
              }
            },
            // 네비게이션 요청 가로채기:
            // http(s)만 허용하고, 그 외 스킴(tel:, mailto:, intent: 등)은 차단.
            shouldOverrideUrlLoading: (controller, navAction) async {
              final uri = navAction.request.url;
              if (uri == null) return NavigationActionPolicy.CANCEL;
              final scheme = uri.scheme.toLowerCase();
              if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
                return NavigationActionPolicy.ALLOW;
              }
              if (kDebugMode) {
                debugPrint('[KioskWebView] 차단된 스킴: $uri');
              }
              return NavigationActionPolicy.CANCEL;
            },
            // 새 창/팝업 요청 차단 (true 반환 시 기본 동작 막음).
            onCreateWindow: (controller, createWindowAction) async {
              if (kDebugMode) {
                debugPrint(
                  '[KioskWebView] 새 창 차단: ${createWindowAction.request.url}',
                );
              }
              return true;
            },
            // 다운로드 시작 시 차단.
            onDownloadStartRequest: (controller, downloadRequest) async {
              if (kDebugMode) {
                debugPrint('[KioskWebView] 다운로드 차단: ${downloadRequest.url}');
              }
              // 별도 처리 없이 무시 → 다운로드 진행하지 않음.
            },
            onReceivedError: (controller, request, error) {
              if (!mounted) return;
              // 메인 프레임에서 발생한 오류만 사용자에게 표시.
              if (request.isForMainFrame == true) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = '페이지를 불러올 수 없습니다.\n(${error.description})';
                });
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              if (!mounted) return;
              if (request.isForMainFrame == true &&
                  (errorResponse.statusCode ?? 0) >= 400) {
                setState(() {
                  _isLoading = false;
                  _errorMessage =
                      '페이지 오류 (HTTP ${errorResponse.statusCode}): '
                      '${errorResponse.reasonPhrase ?? ''}';
                });
              }
            },
          ),
        ),

        // 로딩 인디케이터.
        // 웹(Chrome) 빌드에서는 iframe 구조 특성상 로드 완료 이벤트를 감지하지
        // 못하는 경우가 많아 항상 돌아가는 것처럼 보일 수 있다. 이를 피하기 위해
        // 웹에서는 인디케이터를 표시하지 않고, 네이티브 빌드(Android/Windows/macOS)
        // 에서만 표시한다.
        if (!kIsWeb && _isLoading && _errorMessage == null)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 4),
          ),

        // 에러 오버레이.
        if (_errorMessage != null)
          Positioned.fill(
            child: _ErrorView(
              message: _errorMessage!,
              onRetry: () {
                final target = _currentUrl ?? widget.initialUrl;
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _webController?.loadUrl(
                  urlRequest: URLRequest(url: WebUri(target)),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 64,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text(
                '다시 시도',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
