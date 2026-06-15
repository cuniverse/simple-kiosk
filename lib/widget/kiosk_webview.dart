import 'dart:async';
import 'dart:convert' show jsonEncode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../service/keyboard_controller.dart';
import '../service/system_keyboard.dart';

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

  /// 현재 선택되어 가상 키보드 입력을 받아야 하는 WebView 여부.
  final bool active;

  const KioskWebView({
    super.key,
    required this.initialUrl,
    this.onReady,
    this.active = true,
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

  /// 사용자가 [loadUrl] 을 호출한 시점에 [_KioskWebViewState] 가 응답 감시
  /// 타이머를 걸 수 있도록 하는 훅. WebView 가 죽은 상태에서도 [loadUrl] 호출
  /// 자체는 throw 하지 않을 수 있어, 호출 직후 [onLoadStart]/[onLoadStop] 이
  /// 일정 시간 내 도착했는지를 별도로 감시할 필요가 있다.
  void Function(String url)? _onLoadRequested;

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

  /// 메뉴 선택 등으로 명시적으로 새 URL을 로드한다.
  ///
  /// 메뉴 전환은 "새 탭"과 같은 의미이므로 **이전 히스토리는 모두 초기화**하고
  /// 새 URL을 첫 항목으로 둔다. 사용자가 그 페이지에서 링크를 따라간 이동만이
  /// 뒤/앞 버튼의 대상이 된다.
  Future<void> loadUrl(String url) async {
    _resetHistory(url);
    // state 에 사용자 로드 요청을 알린다(응답 감시 타이머 시작용).
    _onLoadRequested?.call(url);
    await _controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  /// 히스토리를 초기화하고 주어진 URL을 첫 항목으로 만든다.
  void _resetHistory(String url) {
    _history
      ..clear()
      ..add(url);
    _index = 0;
    _publishState();
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

  /// 마지막으로 정상 로드된 URL. 재생성 후 복귀 대상.
  String? _lastGoodUrl;

  /// `onLoadStop`/`onProgressChanged` 이벤트가 도착하지 않을 경우(특히
  /// 웹 타겟의 cross-origin iframe) 로딩 표시가 영원히 남는 것을 방지하는
  /// 안전망 타이머.
  Timer? _loadingFallback;
  static const Duration _loadingTimeout = Duration(seconds: 8);

  /// 에러 화면에서 자동 재시도까지 남은 시간 카운트다운 타이머.
  Timer? _autoRetryTimer;
  int _autoRetrySecondsLeft = 0;
  static const Duration _autoRetryDelay = Duration(seconds: 5);

  /// 연속 실패 누적 횟수. 정상 로드되면 0 으로 리셋.
  int _consecutiveErrors = 0;

  /// 누적 실패가 이 임계값을 넘으면 단순 재시도 대신 WebView 자체를 재생성한다.
  static const int _maxRetriesBeforeRecreate = 3;

  /// InAppWebView 위젯을 강제로 다시 만들기 위한 세대 카운터.
  /// 값이 바뀌면 [ValueKey]가 달라져 Flutter 가 위젯을 새로 빌드한다.
  int _webviewGeneration = 0;

  /// 컨트롤러 헬스체크용 watchdog 타이머.
  ///
  /// Windows 빌드에서는 WebView2 가 별도 자식 HWND 로 존재하기 때문에
  /// Alt+F4 등으로 자식 창만 닫혀 부모(Flutter) 윈도우는 살아있는 상태가
  /// 발생할 수 있다. 이 경우 콜백(예: onRenderProcessGone)이 호출되지
  /// 않으므로, 페이지에서 1초 간격으로 보내는 heartbeat 가 일정 시간 도달하지
  /// 않으면 위젯을 재생성한다.
  Timer? _healthCheck;
  static const Duration _healthCheckInterval = Duration(seconds: 1);

  /// heartbeat 가 이 시간 동안 들어오지 않으면 WebView 가 죽은 것으로 본다.
  static const Duration _heartbeatTimeout = Duration(seconds: 4);

  /// 마지막으로 heartbeat 가 도달한 시각. null 이면 아직 한 번도 받지 못함.
  DateTime? _lastHeartbeat;

  /// 컨트롤러가 준비되었는지(=heartbeat 검사가 의미 있는지) 표시.
  bool _heartbeatArmed = false;

  /// 사용자가 메뉴를 눌러 [KioskWebViewController.loadUrl] 을 호출한 후,
  /// 응답(onLoadStart/onLoadStop)이 도달하기를 기다리는 감시 타이머.
  ///
  /// 정해진 시간 내 응답이 없으면 WebView 가 죽은 것으로 보고 재생성한다.
  Timer? _loadResponseWatchdog;
  String? _pendingLoadUrl;
  static const Duration _loadResponseTimeout = Duration(seconds: 3);

  /// OS 가상 키보드 hide debounce. 한 input 에서 다른 input 으로 포커스가
  /// 옮겨질 때 focusout → focusin 이 연속으로 호출되며, 그 사이에 키보드를
  /// 닫았다가 다시 띄우면 깜빡이므로 짧게 지연시킨다.
  Timer? _keyboardHideDebounce;
  static const Duration _keyboardHideDelay = Duration(milliseconds: 200);

  void _requestShowSystemKeyboard() {
    KeyboardController.instance.attach(_handleKeyEvent);
    _keyboardHideDebounce?.cancel();
    _keyboardHideDebounce = null;
    SystemKeyboard.show();
  }

  void _requestHideSystemKeyboard() {
    _keyboardHideDebounce?.cancel();
    _keyboardHideDebounce = Timer(_keyboardHideDelay, () {
      SystemKeyboard.hide();
    });
  }

  /// 가상 키보드가 보낸 입력을 WebView 의 활성 요소(active element) 로 주입.
  ///
  /// `KeyboardController.instance` 가 발행하는 [KeyboardEvent] 시퀀스를 받아
  /// JS 에서 활성 요소에 직접 값/이벤트를 디스패치한다.
  void _handleKeyEvent(KeyboardEvent event) {
    final controller = _webController;
    if (controller == null) return;
    final String type;
    final String payload;
    switch (event) {
      case InsertText(:final text):
        type = 'insert';
        payload = text;
      case ReplaceLast(:final text):
        type = 'replaceLast';
        payload = text;
      case BackspaceEvent():
        type = 'backspace';
        payload = '';
      case EnterEvent():
        type = 'enter';
        payload = '';
    }
    final js = '''
      (function (type, text) {
        var el = document.activeElement;
        if (!el || el === document.body) return;
        var isEditable = el.isContentEditable ||
            el.tagName === 'TEXTAREA' ||
            (el.tagName === 'INPUT');
        if (!isEditable) return;
        function fireInput() {
          try { el.dispatchEvent(new Event('input', {bubbles: true})); } catch (_) {}
        }
        function fireChange() {
          try { el.dispatchEvent(new Event('change', {bubbles: true})); } catch (_) {}
        }
        if (type === 'insert' || type === 'replaceLast') {
          if (el.isContentEditable) {
            if (type === 'replaceLast') {
              try { document.execCommand('delete', false); } catch (_) {}
            }
            try { document.execCommand('insertText', false, text); } catch (_) {}
            fireInput();
            return;
          }
          if (typeof el.selectionStart === 'number') {
            var s = el.selectionStart, e = el.selectionEnd;
            var v = el.value || '';
            if (type === 'replaceLast') {
              if (s === e && s > 0) { s = s - 1; }
            }
            el.value = v.slice(0, s) + text + v.slice(e);
            var pos = s + text.length;
            try { el.selectionStart = el.selectionEnd = pos; } catch (_) {}
            fireInput();
            return;
          }
          el.value = (el.value || '') + text;
          fireInput();
          return;
        }
        if (type === 'backspace') {
          if (el.isContentEditable) {
            try { document.execCommand('delete', false); } catch (_) {}
            fireInput();
            return;
          }
          if (typeof el.selectionStart === 'number') {
            var ss = el.selectionStart, ee = el.selectionEnd;
            var vv = el.value || '';
            if (ss !== ee) {
              el.value = vv.slice(0, ss) + vv.slice(ee);
              try { el.selectionStart = el.selectionEnd = ss; } catch (_) {}
            } else if (ss > 0) {
              el.value = vv.slice(0, ss - 1) + vv.slice(ss);
              try { el.selectionStart = el.selectionEnd = ss - 1; } catch (_) {}
            }
            fireInput();
          }
          return;
        }
        if (type === 'enter') {
          if (el.form && typeof el.form.requestSubmit === 'function') {
            try { el.form.requestSubmit(); return; } catch (_) {}
          }
          try {
            el.dispatchEvent(new KeyboardEvent('keydown', {
              key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true,
            }));
            el.dispatchEvent(new KeyboardEvent('keyup', {
              key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true,
            }));
          } catch (_) {}
          fireChange();
          return;
        }
      })(${jsonEncode(type)}, ${jsonEncode(payload)});
    ''';
    controller.evaluateJavascript(source: js);
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      KeyboardController.instance.attach(_handleKeyEvent);
    }
  }

  @override
  void didUpdateWidget(covariant KioskWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      KeyboardController.instance.attach(_handleKeyEvent);
    } else if (!widget.active && oldWidget.active) {
      KeyboardController.instance.detach(_handleKeyEvent);
    }
  }

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

  /// watchdog 시작. 이미 실행 중이면 재시작한다.
  void _startHealthCheck() {
    _healthCheck?.cancel();
    _heartbeatArmed = false;
    _lastHeartbeat = null;
    _healthCheck =
        Timer.periodic(_healthCheckInterval, (_) => _checkHeartbeat());
  }

  void _stopHealthCheck() {
    _healthCheck?.cancel();
    _healthCheck = null;
    _heartbeatArmed = false;
    _lastHeartbeat = null;
  }

  /// 페이지에서 보낸 heartbeat 가 아직 살아있는지 검사한다.
  ///
  /// 첫 heartbeat 가 한 번이라도 도착해 [_heartbeatArmed] 가 true 가 된 이후
  /// [_heartbeatTimeout] 동안 추가 heartbeat 가 없으면 WebView 가 죽은 것으로
  /// 판단하고 [_recreateWebView] 를 호출한다.
  void _checkHeartbeat() {
    if (!mounted) return;
    if (!_heartbeatArmed) return;
    final last = _lastHeartbeat;
    if (last == null) return;
    if (DateTime.now().difference(last) > _heartbeatTimeout) {
      if (kDebugMode) {
        debugPrint(
          '[KioskWebView] heartbeat 끊김 → WebView 재생성',
        );
      }
      _recreateWebView();
    }
  }

  /// 페이지에 1초 간격 heartbeat 스크립트를 주입한다. `onLoadStop` 마다 다시
  /// 주입해 페이지 이동 후에도 동작이 유지되게 한다.
  Future<void> _injectHeartbeatScript() async {
    final controller = _webController;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: r'''
        (function () {
          if (window.__kioskHeartbeatStarted) return;
          window.__kioskHeartbeatStarted = true;
          var send = function () {
            try {
              window.flutter_inappwebview.callHandler('kioskHeartbeat');
            } catch (e) { /* 무시 */ }
          };
          send();
          setInterval(send, 1000);
        })();
      ''');
    } catch (_) {
      // 주입 실패는 무시. 다음 onLoadStop 에서 다시 시도.
    }
  }

  /// 페이지의 모든 편집 가능한 요소(input/textarea/contenteditable) 에 포커스
  /// 이벤트 리스너를 부착해 OS 가상 키보드 표시/숨김을 요청한다.
  ///
  /// `focusin`/`focusout` 은 캡처링 단계에서 처리해 동적으로 추가되는 요소까지
  /// 한 번의 리스너로 잡는다.
  Future<void> _injectKeyboardFocusScript() async {
    final controller = _webController;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: r'''
        (function () {
          if (window.__kioskKbHookStarted) return;
          window.__kioskKbHookStarted = true;

          var NON_EDIT_INPUT_TYPES = {
            button: 1, submit: 1, reset: 1, checkbox: 1, radio: 1,
            range: 1, color: 1, file: 1, hidden: 1, image: 1
          };

          function isEditable(el) {
            if (!el) return false;
            if (el.isContentEditable) return true;
            var tag = el.tagName;
            if (tag === 'TEXTAREA') return true;
            if (tag === 'INPUT') {
              var t = (el.type || 'text').toLowerCase();
              return !NON_EDIT_INPUT_TYPES[t];
            }
            return false;
          }

          document.addEventListener('focusin', function (e) {
            if (isEditable(e.target)) {
              try {
                window.flutter_inappwebview.callHandler('kioskKeyboardShow');
              } catch (_) { /* 무시 */ }
            }
          }, true);

          document.addEventListener('focusout', function (e) {
            if (isEditable(e.target)) {
              try {
                window.flutter_inappwebview.callHandler('kioskKeyboardHide');
              } catch (_) { /* 무시 */ }
            }
          }, true);
        })();
      ''');
    } catch (_) {
      // 주입 실패는 무시. 다음 onLoadStop 에서 다시 시도.
    }
  }

  /// 사용자가 메뉴를 눌렀을 때 응답 감시 타이머를 시작한다.
  /// 일정 시간 내 [onLoadStart]/[onLoadStop] 이 도달하지 않으면 WebView 를
  /// 재생성한다.
  void _startLoadResponseWatchdog(String url) {
    _loadResponseWatchdog?.cancel();
    _pendingLoadUrl = url;
    _loadResponseWatchdog = Timer(_loadResponseTimeout, () {
      if (!mounted) return;
      if (_pendingLoadUrl == null) return;
      if (kDebugMode) {
        debugPrint(
          '[KioskWebView] 메뉴 클릭 응답 없음 → WebView 재생성',
        );
      }
      _recreateWebView();
    });
  }

  void _cancelLoadResponseWatchdog() {
    _loadResponseWatchdog?.cancel();
    _loadResponseWatchdog = null;
    _pendingLoadUrl = null;
  }

  /// 에러 발생 시 5초 카운트다운 후 자동 재시도. 3회 연속 실패하면 WebView 를
  /// 통째로 재생성한다(키오스크가 외부 개입 없이 회복되도록).
  void _scheduleAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetrySecondsLeft = _autoRetryDelay.inSeconds;
    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _autoRetrySecondsLeft -= 1;
      });
      if (_autoRetrySecondsLeft <= 0) {
        timer.cancel();
        _performAutoRetry();
      }
    });
  }

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    _autoRetrySecondsLeft = 0;
  }

  void _performAutoRetry() {
    if (!mounted) return;
    _consecutiveErrors += 1;
    if (kDebugMode) {
      debugPrint(
        '[KioskWebView] 자동 재시도 #$_consecutiveErrors',
      );
    }
    if (_consecutiveErrors >= _maxRetriesBeforeRecreate) {
      _recreateWebView(resetToHome: true);
      return;
    }
    final target = _currentUrl ?? _lastGoodUrl ?? widget.initialUrl;
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    _scheduleLoadingFallback();
    _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target)),
    );
  }

  /// WebView 위젯을 통째로 새로 만든다.
  ///
  /// 사용 시점:
  /// - 렌더러 프로세스가 종료된 경우(`onRenderProcessGone`,
  ///   `onWebContentProcessDidTerminate`)
  /// - 렌더러가 응답하지 않는 경우(`onRenderProcessUnresponsive`)
  /// - 인라인 자동 재시도가 [_maxRetriesBeforeRecreate] 회 연속 실패한 경우
  /// - watchdog 헬스체크가 [_maxHealthFailures] 회 연속 실패한 경우
  ///   (Windows 에서 Alt+F4 로 WebView2 자식 창만 닫힌 상황 등)
  void _recreateWebView({bool resetToHome = false}) {
    _cancelAutoRetry();
    _loadingFallback?.cancel();
    _stopHealthCheck();
    // 메뉴 클릭으로 인한 재생성이라면 사용자가 가려던 URL 을 복귀 대상으로 쓴다.
    final pending = _pendingLoadUrl;
    _cancelLoadResponseWatchdog();
    if (kDebugMode) {
      debugPrint(
        '[KioskWebView] WebView 재생성 (resetToHome=$resetToHome)',
      );
    }
    final target = resetToHome
        ? widget.initialUrl
        : (pending ?? _lastGoodUrl ?? widget.initialUrl);
    _webController = null;
    _kioskController = null;
    _consecutiveErrors = 0;
    if (!mounted) return;
    setState(() {
      _webviewGeneration += 1;
      _errorMessage = null;
      _isLoading = true;
      _currentUrl = target;
      _lastGoodUrl = target;
    });
  }

  @override
  void dispose() {
    KeyboardController.instance.detach(_handleKeyEvent);
    _loadingFallback?.cancel();
    _autoRetryTimer?.cancel();
    _healthCheck?.cancel();
    _loadResponseWatchdog?.cancel();
    _keyboardHideDebounce?.cancel();
    // 위젯이 사라질 때 시스템 키보드도 함께 닫는다.
    SystemKeyboard.hide();
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
            // 세대 카운터를 키에 포함하면 [_recreateWebView] 호출 시
            // Flutter 가 InAppWebView 를 폐기하고 새로 빌드한다.
            key: ValueKey('kiosk-inappwebview-$_webviewGeneration'),
            initialUrlRequest: URLRequest(
              url: WebUri(_lastGoodUrl ?? widget.initialUrl),
            ),
            initialSettings: _settings,
            onWebViewCreated: (controller) {
              _webController = controller;
              final kc = KioskWebViewController._(controller);
              _kioskController = kc;
              // 메뉴 클릭(loadUrl) 시 응답 감시 타이머를 건다.
              kc._onLoadRequested = _startLoadResponseWatchdog;
              // 초기 URL을 히스토리 첫 항목으로 등록(메뉴 첫 항목과 동일).
              kc._resetHistory(_lastGoodUrl ?? widget.initialUrl);
              widget.onReady?.call(kc);
              // 페이지에서 보낼 heartbeat 수신용 핸들러 등록.
              controller.addJavaScriptHandler(
                handlerName: 'kioskHeartbeat',
                callback: (_) {
                  _lastHeartbeat = DateTime.now();
                  _heartbeatArmed = true;
                  return null;
                },
              );
              // OS 가상 키보드 표시/숨김 요청 수신.
              controller.addJavaScriptHandler(
                handlerName: 'kioskKeyboardShow',
                callback: (_) {
                  _requestShowSystemKeyboard();
                  return null;
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'kioskKeyboardHide',
                callback: (_) {
                  _requestHideSystemKeyboard();
                  return null;
                },
              );
              // 컨트롤러가 준비된 시점부터 watchdog 가동.
              _startHealthCheck();
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _isLoading = true;
                _errorMessage = null;
                _currentUrl = url?.toString();
              });
              _scheduleLoadingFallback();
              // 응답이 도착했으므로 메뉴 클릭 watchdog 해제.
              _cancelLoadResponseWatchdog();
              _kioskController?._noteNavigationStart(url?.toString());
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() {
                _currentUrl = url?.toString();
              });
              _finishLoading();
              // 정상 로드 완료 → 자동 재시도 카운터/타이머 초기화.
              _consecutiveErrors = 0;
              _cancelAutoRetry();
              if (url != null && url.toString() != 'about:blank') {
                _lastGoodUrl = url.toString();
              }
              // 페이지가 바뀔 때마다 heartbeat 스크립트를 다시 주입.
              _injectHeartbeatScript();
              // OS 가상 키보드 트리거용 input 포커스 리스너도 함께 주입.
              _injectKeyboardFocusScript();
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
                _scheduleAutoRetry();
              }
            },
            onReceivedHttpError: (controller, request, errorResponse) {
              if (!mounted) return;
              if (request.isForMainFrame == true &&
                  (errorResponse.statusCode ?? 0) >= 400) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = '페이지 오류 (HTTP ${errorResponse.statusCode}): '
                      '${errorResponse.reasonPhrase ?? ''}';
                });
                _scheduleAutoRetry();
              }
            },
            // Android: 렌더러 프로세스가 죽었을 때(OOM 포함). 컨트롤러는 무효
            // 상태이므로 위젯을 통째로 새로 만든다.
            onRenderProcessGone: (controller, detail) {
              if (kDebugMode) {
                debugPrint(
                  '[KioskWebView] onRenderProcessGone '
                  '(didCrash=${detail.didCrash})',
                );
              }
              _recreateWebView();
            },
            // Android: 렌더러가 응답하지 않음. TERMINATE 를 돌려주면
            // onRenderProcessGone 이 이어서 발생해 위 핸들러로 회복된다.
            onRenderProcessUnresponsive: (controller, url) async {
              if (kDebugMode) {
                debugPrint('[KioskWebView] onRenderProcessUnresponsive: $url');
              }
              return WebViewRenderProcessAction.TERMINATE;
            },
            // iOS / macOS: WebContent 프로세스(즉, 렌더러)가 종료된 경우.
            onWebContentProcessDidTerminate: (controller) {
              if (kDebugMode) {
                debugPrint('[KioskWebView] onWebContentProcessDidTerminate');
              }
              _recreateWebView();
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
              autoRetrySecondsLeft:
                  _autoRetryTimer != null ? _autoRetrySecondsLeft : null,
              onRetry: () {
                _cancelAutoRetry();
                final target = _currentUrl ?? _lastGoodUrl ?? widget.initialUrl;
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _scheduleLoadingFallback();
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

  /// 자동 재시도까지 남은 시간(초). null 이면 카운트다운을 표시하지 않는다.
  final int? autoRetrySecondsLeft;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.autoRetrySecondsLeft,
  });

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
          if (autoRetrySecondsLeft != null && autoRetrySecondsLeft! > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$autoRetrySecondsLeft초 후 자동으로 다시 시도합니다…',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
