import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'model/idle_config.dart';
import 'model/layout_config.dart';
import 'model/menu_config.dart';
import 'model/menu_item.dart';
import 'service/menu_config_loader.dart';
import 'widget/idle_gate.dart';
import 'widget/kiosk_webview.dart';
import 'widget/navigation_menu.dart';
import 'widget/virtual_keyboard.dart';
import 'service/keyboard_controller.dart';
import 'service/system_keyboard.dart';
import 'service/app_health_signal.dart';
import 'service/update_controller.dart';
import 'service/update_service.dart';
import 'widget/kiosk_shortcuts.dart';
import 'widget/update_admin_dialog.dart';

/// 앱 진입 위젯.
///
/// 메뉴 JSON 로딩 → 로딩/에러 처리 → [_KioskHome] 표시 순으로 진행한다.
class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      // 모든 화면 위에 가상 키보드 오버레이를 띄울 수 있도록 builder 로 감싼다.
      // KeyboardController.visible 가 true 일 때만 키보드 위젯이 표시된다.
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<bool>(
              valueListenable: KeyboardController.instance.visible,
              builder: (context, visible, _) {
                if (!visible) return const SizedBox.shrink();
                return const VirtualKeyboardOverlay();
              },
            ),
          ],
        );
      },
      home: const _MenuBootstrap(),
    );
  }
}

/// 메뉴 설정을 비동기로 로드해서 [_KioskHome]에 전달한다.
class _MenuBootstrap extends StatefulWidget {
  const _MenuBootstrap();

  @override
  State<_MenuBootstrap> createState() => _MenuBootstrapState();
}

class _MenuBootstrapState extends State<_MenuBootstrap> {
  late Future<MenuConfig> _future;

  /// 로드 실패 시 자동 재시도 타이머. 무인 운영 환경에서 외부 개입 없이
  /// 회복되도록 한다.
  Timer? _autoRetryTimer;
  int _autoRetrySecondsLeft = 0;
  static const Duration _autoRetryDelay = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  void _startLoad() {
    _future = const MenuConfigLoader().load();
    // 별도 리스너로 실패를 감지해 자동 재시도를 예약한다.
    // FutureBuilder 는 원본 _future 의 에러를 그대로 받아 에러 UI 를 표시한다.
    _future.then<void>((_) {
      AppHealthSignal.markReady();
    }, onError: (Object _) {
      if (mounted) _scheduleAutoRetry();
    });
  }

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
        _retry();
      }
    });
  }

  void _retry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    setState(_startLoad);
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MenuConfig>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 64, color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(
                      '메뉴 설정을 불러올 수 없습니다.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18),
                    ),
                    if (_autoRetryTimer != null &&
                        _autoRetrySecondsLeft > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        '$_autoRetrySecondsLeft초 후 자동으로 다시 시도합니다…',
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
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label:
                            const Text('다시 시도', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return _KioskHome(
          items: snapshot.data!.items,
          layout: snapshot.data!.layout,
          idle: snapshot.data!.idle,
        );
      },
    );
  }
}

/// 키오스크 메인 화면.
///
/// - [LayoutConfig.navPosition] 에 따라 네비게이션 위치를 결정한다.
///   - `auto`: 화면 폭이 [LayoutConfig.breakpoint] 이상이면 좌측, 아니면 하단.
///   - `left`/`right`: 항상 좌/우측.
///   - `top`/`bottom`: 항상 상/하단.
/// - Android Back 버튼:
///   - WebView 뒤로갈 수 있으면 WebView 뒤로
///   - 아니면 첫 번째(홈) 메뉴로 이동(앱 종료 방지)
class _KioskHome extends StatefulWidget {
  final List<MenuItem> items;
  final LayoutConfig layout;
  final IdleConfig idle;
  const _KioskHome({
    required this.items,
    required this.layout,
    required this.idle,
  });

  @override
  State<_KioskHome> createState() => _KioskHomeState();
}

class _KioskHomeState extends State<_KioskHome> {
  int _selectedIndex = 0;
  final IdleGateController _idleGateController = IdleGateController();
  late final UpdateController _updateController;
  bool _versionDialogOpen = false;
  bool _manualUpdateRunning = false;

  /// 최초 방문 메뉴가 백그라운드에서 준비되는 동안 선택 표시할 인덱스.
  /// 실제 화면은 준비가 끝날 때까지 [_selectedIndex]를 유지한다.
  int? _pendingIndex;

  /// 하단 네비게이션 바를 접었는지 여부.
  ///
  /// 접힌 동안에는 WebView 위에 최소 조작 버튼만 플로팅으로 남긴다.
  late bool _bottomToolbarHidden;

  /// 메뉴 인덱스별 컨트롤러. 한 번이라도 mount 된 항목에 대해서만 채워진다.
  final Map<int, KioskWebViewController> _controllers = {};

  /// 한 번이라도 방문한(=WebView 가 mount 된) 메뉴 인덱스 집합.
  ///
  /// IndexedStack 의 자식 중 mount 안 된 항목은 [SizedBox.shrink] 로 두어
  /// 메모리(WebView2 인스턴스) 를 절약한다. 첫 항목은 앱 시작 시 자동 mount.
  final Set<int> _mountedIndices = {0};

  /// 최초 페이지 로드가 끝나 즉시 화면 전환할 수 있는 메뉴 인덱스 집합.
  final Set<int> _readyIndices = {};

  /// 더블 탭 감지를 위한 마지막 탭 시점/대상 메뉴.
  ///
  /// `keepStateOnTap` 옵션이 켜진 경우, 같은 메뉴를 짧은 시간(300ms) 내에 두
  /// 번 누르면 강제 reload 하도록 한다.
  DateTime? _lastTapAt;
  int? _lastTapIndex;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _bottomToolbarHidden = widget.layout.toolbarInitiallyHidden;
    _updateController = UpdateController();
    _updateController.initialize();
  }

  @override
  void dispose() {
    _updateController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _KioskHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.toolbarInitiallyHidden !=
        widget.layout.toolbarInitiallyHidden) {
      _bottomToolbarHidden = widget.layout.toolbarInitiallyHidden;
    }
  }

  void _hideBottomToolbar() {
    if (_bottomToolbarHidden) return;
    setState(() => _bottomToolbarHidden = true);
  }

  void _showBottomToolbar() {
    if (!_bottomToolbarHidden) return;
    setState(() => _bottomToolbarHidden = false);
  }

  KioskWebViewController? get _currentController =>
      _controllers[_selectedIndex];

  void _onSelect(int index) {
    if (index < 0 || index >= widget.items.length) return;

    // 이미 백그라운드에서 준비 중인 메뉴를 다시 눌러도 빈 WebView로 먼저
    // 전환하지 않는다.
    if (_pendingIndex == index) return;

    final item = widget.items[index];
    final url = item.url;
    final now = DateTime.now();

    // 더블 탭 판정: 같은 메뉴를 윈도우 내에 다시 누른 경우.
    final isDoubleTap = _lastTapIndex == index &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapWindow;
    _lastTapAt = now;
    _lastTapIndex = index;

    // 항목별 설정이 있으면 우선, 없으면 layout 기본값.
    final keepState = item.keepStateOnTap ?? widget.layout.keepStateOnTap;

    if (kDebugMode) {
      debugPrint(
        '[KioskHome] _onSelect '
        'index=$index id="${item.id}" '
        'currentSelected=$_selectedIndex '
        'keepState=$keepState (item=${item.keepStateOnTap}, layout=${widget.layout.keepStateOnTap}) '
        'isDoubleTap=$isDoubleTap '
        'mounted=${_mountedIndices.contains(index)}',
      );
    }

    final wasMounted = _mountedIndices.contains(index);
    final isReady = _readyIndices.contains(index);

    if (index == _selectedIndex) {
      // 준비 중이던 다른 메뉴 선택만 취소한다. 현재 메뉴가 상태 유지 모드면
      // 부모 전체를 다시 그릴 필요가 없다.
      if (_pendingIndex != null) {
        setState(() => _pendingIndex = null);
      }
      if (isDoubleTap || !keepState) {
        _controllers[index]?.loadUrl(url);
      }
      return;
    }

    if (!isReady) {
      // 최초 방문 메뉴는 기존 화면 뒤에서 먼저 mount/load 한다. 페이지가 준비되면
      // [_onInitialLoadReady]가 실제 선택 인덱스를 바꿔 빈 화면 노출을 막는다.
      setState(() {
        _pendingIndex = index;
        _mountedIndices.add(index);
      });
      return;
    }

    setState(() {
      _pendingIndex = null;
      _selectedIndex = index;
    });

    // 이미 mount 되어 있는 항목.
    if (wasMounted && (isDoubleTap || !keepState)) {
      // 강제 재로드: keepState=false 이거나 더블 탭.
      _controllers[index]?.loadUrl(url);
    }
    // keepState=true & 단일 탭 & 이미 mount 됨 → 아무 것도 안 함(상태 유지).
  }

  void _onInitialLoadReady(int index) {
    if (!mounted) return;
    final shouldSelect = _pendingIndex == index;
    setState(() {
      _readyIndices.add(index);
      if (shouldSelect) {
        _selectedIndex = index;
        _pendingIndex = null;
      }
    });
  }

  /// 대기화면 진입 시 호출.
  ///
  /// 메모리 절약을 위해 모든 WebView 를 언mount 해서 WebView2 인스턴스를
  /// 해제한다. 다음 사용자가 깨운 뒤 메뉴를 누르면 그 항목만 새로 mount 된다.
  /// (첫 항목 = 홈은 항상 mount 상태로 둔다 — 깨운 직후 즉시 표시되어야 하므로.)
  ///
  /// 이전 사용자의 로그인 세션이 다음 사용자에게 노출되지 않도록 **모든 쿠키를
  /// 삭제**한다. 캐시(이미지/JS/CSS) 는 유지해 다음 로딩 성능 손해는 없다.
  void _onEnterIdle() {
    if (widget.items.isEmpty) return;
    _updateController.setIdle(true);
    if (_updateController.canAutoInstall(isIdle: true)) {
      _updateController.installNow();
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[KioskHome] 대기화면 진입 → WebView 정리 '
        '(mounted=${_mountedIndices.toList()..sort()})',
      );
    }
    setState(() {
      _bottomToolbarHidden = true;
      _selectedIndex = 0;
      _pendingIndex = null;
      // 홈만 남기고 모두 언mount.
      _mountedIndices
        ..clear()
        ..add(0);
      _readyIndices
        ..clear()
        ..add(0);
      // 언mount 되는 항목의 컨트롤러 참조도 정리(위젯이 dispose 되면 무효).
      _controllers.removeWhere((index, _) => index != 0);
    });
    // 쿠키 삭제 후 홈을 초기 URL 로 리셋. 순서 보장을 위해 await.
    () async {
      // idle 진입 시 떠 있던 OS 가상 키보드도 함께 닫는다.
      await SystemKeyboard.hide();
      try {
        await CookieManager.instance().deleteAllCookies();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[KioskHome] 쿠키 삭제 실패: $e');
        }
      }
      if (!mounted) return;
      _controllers[0]?.loadUrl(widget.items.first.url);
    }();
  }

  /// 대기화면에서 깨어날 때 호출.
  ///
  /// 이미 [_onEnterIdle] 에서 정리되었으므로 여기서는 인덱스만 홈으로 보장한다.
  void _onWake() {
    _updateController.setIdle(false);
    if (widget.items.isEmpty) return;
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
  }

  Future<bool> _onWillPop() async {
    // WebView 뒤로가기 우선.
    final controller = _currentController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    // 홈(첫 번째) 메뉴가 아니면 홈으로 이동.
    if (_selectedIndex != 0) {
      _onSelect(0);
      return false;
    }
    // 그 외에는 그대로(앱 종료하지 않도록 false 유지).
    return false;
  }

  Future<void> _showVersionInfo() async {
    if (_versionDialogOpen || _manualUpdateRunning || !mounted) return;
    _versionDialogOpen = true;
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline),
              SizedBox(width: 10),
              Text('프로그램 버전 정보'),
            ],
          ),
          content: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Simple Kiosk v${info.version}'),
                if (info.buildNumber.isNotEmpty)
                  Text('빌드 번호: ${info.buildNumber}'),
                const Text(
                  'Updater 버전: v${UpdateService.updaterVersion}',
                ),
                const Text(
                  '실행 모드: ${kReleaseMode ? 'Release' : 'Debug'}',
                ),
                Text('운영체제: ${Platform.operatingSystem}'),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
    } finally {
      _versionDialogOpen = false;
    }
  }

  Future<T> _runUpdateProgress<T>(
    String title,
    Future<T> Function() operation,
  ) async {
    final dialogReady = Completer<void>();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          if (!dialogReady.isCompleted) dialogReady.complete();
          return PopScope(
            canPop: false,
            child: AnimatedBuilder(
              animation: _updateController,
              builder: (context, _) => AlertDialog(
                title: Text(title),
                content: Row(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Text(_updateController.status)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    await dialogReady.future;
    try {
      return await operation();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _showMessage(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdateFromShortcut() async {
    if (_manualUpdateRunning || _versionDialogOpen || !mounted) return;
    _manualUpdateRunning = true;
    try {
      await _updateController.initialize();
      if (!_updateController.supported) {
        await _showMessage('업데이트', '자동 업데이트는 Windows에서 지원됩니다.');
        return;
      }
      if (_updateController.busy) {
        await _showMessage('업데이트', '다른 업데이트 작업이 진행 중입니다.');
        return;
      }

      final update = await _runUpdateProgress(
        '업데이트 확인',
        () => _updateController.check(rethrowErrors: true),
      );
      if (!mounted) return;
      if (update == null) {
        await _showMessage(
          '업데이트',
          '현재 v${_updateController.currentVersion}가 최신 버전입니다.',
        );
        return;
      }

      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('새 업데이트 발견'),
          content: Text(
            '현재 버전: v${_updateController.currentVersion}\n'
            '새 버전: v${update.manifest.version}\n\n'
            '업데이트를 설치하면 프로그램이 자동으로 재시작됩니다.\n'
            '지금 업데이트하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('나중에'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('업데이트'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;

      final package = await _runUpdateProgress(
        '업데이트 다운로드',
        () => _updateController.download(
          allowAutoInstall: false,
          rethrowErrors: true,
        ),
      );
      if (package == null || !mounted) return;

      await _runUpdateProgress(
        '업데이트 설치 및 재시작',
        _updateController.installNow,
      );
    } catch (error) {
      if (mounted) await _showMessage('업데이트 실패', '$error');
    } finally {
      _manualUpdateRunning = false;
    }
  }

  /// 현재 화면 크기와 설정을 토대로 실제 적용될 위치를 계산한다.
  NavPosition _effectivePosition(double width) {
    final p = widget.layout.navPosition;
    if (p != NavPosition.auto) return p;
    return width >= widget.layout.breakpoint
        ? NavPosition.left
        : NavPosition.bottom;
  }

  @override
  Widget build(BuildContext context) {
    final content = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        body: SafeArea(
          child: IdleGate(
            config: widget.idle,
            controller: _idleGateController,
            // 대기화면 진입 시 메모리 정리, 깨어날 때 첫 화면으로.
            onEnterIdle: _onEnterIdle,
            onWake: _onWake,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final position = _effectivePosition(constraints.maxWidth);

                // 메뉴별 WebView 를 IndexedStack 에 lazy 배치.
                // 한 번이라도 방문한 항목만 실제 KioskWebView 로 mount 된다.
                final webViewStack = IndexedStack(
                  index: _selectedIndex,
                  children: List<Widget>.generate(widget.items.length, (i) {
                    if (!_mountedIndices.contains(i)) {
                      return const SizedBox.shrink();
                    }
                    final item = widget.items[i];
                    return KioskWebView(
                      key: ValueKey('kiosk-webview-${item.id}'),
                      initialUrl: item.url,
                      active: i == _selectedIndex,
                      onShowVersion: _showVersionInfo,
                      onCheckUpdate: _checkUpdateFromShortcut,
                      onReady: (c) {
                        _controllers[i] = c;
                        // 현재 화면의 history 컨트롤만 새 컨트롤러를 받도록 리빌드.
                        // 백그라운드 준비 메뉴는 완료 콜백에서 함께 갱신된다.
                        if (mounted && i == _selectedIndex) setState(() {});
                      },
                      onInitialLoadReady: () => _onInitialLoadReady(i),
                    );
                  }),
                );

                final isSide = position == NavPosition.left ||
                    position == NavPosition.right;
                // 네이티브 WebView가 교체/표시될 때 메뉴바까지 함께 다시 칠해져
                // 번쩍이는 현상을 막도록 별도 합성 레이어로 격리한다.
                final nav = RepaintBoundary(
                  child: NavigationMenu(
                    items: widget.items,
                    selectedIndex: _pendingIndex ?? _selectedIndex,
                    onSelected: _onSelect,
                    orientation: isSide
                        ? NavigationOrientation.side
                        : NavigationOrientation.bottom,
                    sideWidth: widget.layout.sideWidth,
                    barHeight: widget.layout.barHeight,
                    buttonHeight: widget.layout.buttonHeight,
                    buttonWidth: widget.layout.buttonWidth,
                    buttonGap: widget.layout.buttonGap,
                    buttonAlignment: widget.layout.buttonAlignment,
                    showHistoryButtons: widget.layout.showHistoryButtons,
                    historyController: _currentController,
                    showKeyboardToggle: widget.layout.showKeyboardToggle,
                    barColor: widget.layout.barColor,
                    buttonColor: widget.layout.buttonColor,
                    buttonForegroundColor: widget.layout.buttonForegroundColor,
                    selectedButtonColor: widget.layout.selectedButtonColor,
                    selectedButtonForegroundColor:
                        widget.layout.selectedButtonForegroundColor,
                    onHide: position == NavPosition.bottom
                        ? _hideBottomToolbar
                        : null,
                    onEnterIdle: widget.idle.isUsable
                        ? _idleGateController.enterIdle
                        : null,
                    onOpenAdmin: UpdateAdminDialog.isConfigured
                        ? () => UpdateAdminDialog.show(
                              context,
                              _updateController,
                            )
                        : null,
                  ),
                );

                switch (position) {
                  case NavPosition.left:
                    return Row(
                      children: [
                        nav,
                        const VerticalDivider(width: 1),
                        Expanded(child: webViewStack),
                      ],
                    );
                  case NavPosition.right:
                    return Row(
                      children: [
                        Expanded(child: webViewStack),
                        const VerticalDivider(width: 1),
                        nav,
                      ],
                    );
                  case NavPosition.top:
                    return Column(
                      children: [
                        nav,
                        const Divider(height: 1),
                        Expanded(child: webViewStack),
                      ],
                    );
                  case NavPosition.bottom:
                  case NavPosition.auto: // 이론상 도달 불가 — 안전망.
                    // 툴바 표시 여부와 관계없이 WebView는 항상 Stack의 첫 번째
                    // 자식에 고정한다. 부모 구조가 바뀌면 네이티브 WebView가
                    // dispose/recreate되어 페이지 상태가 사라질 수 있기 때문이다.
                    return BottomToolbarHost(
                      hidden: _bottomToolbarHidden,
                      toolbarHeight: widget.layout.barHeight,
                      autoHideDuration: Duration(
                        seconds: widget.layout.toolbarAutoHideSec,
                      ),
                      onAutoHide: _hideBottomToolbar,
                      webView: webViewStack,
                      toolbar: nav,
                      overlay: CollapsedToolbarOverlay(
                        historyController: _currentController,
                        onShowToolbar: _showBottomToolbar,
                      ),
                    );
                }
              },
            ),
          ),
        ),
      ),
    );
    return KioskShortcuts(
      onShowVersion: _showVersionInfo,
      onCheckUpdate: _checkUpdateFromShortcut,
      child: content,
    );
  }
}
