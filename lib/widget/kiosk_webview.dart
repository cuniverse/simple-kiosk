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

/// 외부에서 WebView를 제어하기 위한 컨트롤러.
class KioskWebViewController {
  final InAppWebViewController _controller;
  KioskWebViewController._(this._controller);

  /// 지정한 URL을 로드한다.
  Future<void> loadUrl(String url) {
    return _controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  /// 뒤로 갈 수 있는지 여부.
  Future<bool> canGoBack() => _controller.canGoBack();

  /// 뒤로 이동한다.
  Future<void> goBack() => _controller.goBack();

  /// 현재 페이지를 다시 로드한다.
  Future<void> reload() => _controller.reload();
}

class _KioskWebViewState extends State<KioskWebView> {
  InAppWebViewController? _webController;

  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUrl;

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
              widget.onReady?.call(KioskWebViewController._(controller));
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _isLoading = true;
                _errorMessage = null;
                _currentUrl = url?.toString();
              });
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() {
                _isLoading = false;
                _currentUrl = url?.toString();
              });
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              if (progress >= 100 && _isLoading) {
                setState(() => _isLoading = false);
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
        if (_isLoading && _errorMessage == null)
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
