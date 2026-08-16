import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'app_identity.dart';

import 'model/idle_config.dart';
import 'model/layout_config.dart';
import 'model/menu_config.dart';
import 'model/menu_item.dart';
import 'model/menu_language.dart';
import 'service/admin_api_controller.dart';
import 'service/configuration_backup_service.dart';
import 'service/menu_config_loader.dart';
import 'service/runtime_paths.dart';
import 'widget/idle_gate.dart';
import 'widget/kiosk_webview.dart';
import 'widget/navigation_menu.dart';
import 'widget/virtual_keyboard.dart';
import 'service/keyboard_controller.dart';
import 'service/kiosk_tray_controller.dart';
import 'service/system_keyboard.dart';
import 'service/app_health_signal.dart';
import 'service/update_controller.dart';
import 'service/update_service.dart';
import 'widget/kiosk_shortcuts.dart';
import 'widget/language_selection.dart';
import 'widget/update_admin_dialog.dart';

/// 앱 진입 위젯.
///
/// 메뉴 JSON 로딩 → 로딩/에러 처리 → [_KioskHome] 표시 순으로 진행한다.
class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
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
          languages: snapshot.data!.languages,
          defaultLanguageId: snapshot.data!.defaultLanguageId,
          languageSelectionTitle: snapshot.data!.languageSelectionTitle,
          languageSelectionSubtitle: snapshot.data!.languageSelectionSubtitle,
          layout: snapshot.data!.layout,
          idle: snapshot.data!.idle,
          onReloadConfig: _retry,
        );
      },
    );
  }
}

/// 사이니지 메인 화면.
///
/// - [LayoutConfig.navPosition] 에 따라 네비게이션 위치를 결정한다.
///   - `auto`: 화면 폭이 [LayoutConfig.breakpoint] 이상이면 좌측, 아니면 하단.
///   - `left`/`right`: 항상 좌/우측.
///   - `top`/`bottom`: 항상 상/하단.
/// - Android Back 버튼:
///   - WebView 뒤로갈 수 있으면 WebView 뒤로
///   - 아니면 첫 번째(홈) 메뉴로 이동(앱 종료 방지)
class _KioskHome extends StatefulWidget {
  final List<MenuLanguage> languages;
  final String defaultLanguageId;
  final String languageSelectionTitle;
  final String languageSelectionSubtitle;
  final LayoutConfig layout;
  final IdleConfig idle;
  final VoidCallback onReloadConfig;
  const _KioskHome({
    required this.languages,
    required this.defaultLanguageId,
    required this.languageSelectionTitle,
    required this.languageSelectionSubtitle,
    required this.layout,
    required this.idle,
    required this.onReloadConfig,
  });

  @override
  State<_KioskHome> createState() => _KioskHomeState();
}

class _KioskHomeState extends State<_KioskHome> {
  int _selectedIndex = 0;
  late int _selectedLanguageIndex;
  bool _showLanguageSelection = false;
  final IdleGateController _idleGateController = IdleGateController();
  late final UpdateController _updateController;
  late final KioskTrayController _trayController;
  late final AdminApiController _adminApiController;
  final DateTime _startedAt = DateTime.now();
  bool _versionDialogOpen = false;
  bool _manualDialogOpen = false;
  bool _manualUpdateRunning = false;

  /// 최초 방문 메뉴가 백그라운드에서 준비되는 동안 선택 표시할 인덱스.
  /// 실제 화면은 준비가 끝날 때까지 [_selectedIndex]를 유지한다.
  int? _pendingIndex;

  /// 네비게이션 툴바를 감추었는지 여부.
  ///
  /// 접힌 동안에는 WebView 위에 최소 조작 버튼만 플로팅으로 남긴다.
  late bool _toolbarHidden;

  /// 화면 보호기 더블클릭 후 툴바 감추기 더블클릭을 받을 수 있는 시각.
  DateTime? _hideSignageGestureExpiresAt;
  static const Duration _hideSignageGestureWindow = Duration(seconds: 5);

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

  MenuLanguage get _selectedLanguage =>
      widget.languages[_selectedLanguageIndex];

  List<MenuItem> get _items => _selectedLanguage.items;

  @override
  void initState() {
    super.initState();
    _selectedLanguageIndex = _defaultLanguageIndex();
    _toolbarHidden = widget.layout.toolbarInitiallyHidden;
    _updateController = UpdateController();
    _updateController.initialize();
    _trayController = KioskTrayController(
      onOpenSettings: _showAdminSettings,
      onOpenManual: _showUserManual,
    );
    const configLoader = MenuConfigLoader();
    _adminApiController = AdminApiController(
      statusProvider: _adminStatus,
      actionHandler: _handleAdminAction,
      configReader: configLoader.readOverride,
      effectiveConfigReader: configLoader.readEffective,
      configWriter: _saveExternalConfig,
      backupService: const ConfigurationBackupService(),
      onConfigurationImported: () async => widget.onReloadConfig(),
    );
    unawaited(_initializeTray());
    unawaited(_initializeAdminApi());
  }

  @override
  void dispose() {
    unawaited(_trayController.dispose());
    unawaited(_adminApiController.close());
    _adminApiController.dispose();
    _updateController.dispose();
    super.dispose();
  }

  Future<void> _initializeTray() async {
    try {
      await _trayController.initialize();
    } catch (error) {
      if (kDebugMode) debugPrint('[tray] 초기화 실패: $error');
    }
  }

  Future<void> _initializeAdminApi() async {
    try {
      await _adminApiController.initialize();
    } catch (error) {
      if (kDebugMode) debugPrint('[admin-api] 초기화 실패: $error');
    }
  }

  Future<Map<String, dynamic>> _adminStatus() async {
    await _updateController.initialize();
    final visible = Platform.isWindows ? await windowManager.isVisible() : true;
    return {
      'application': appDisplayName,
      'running': true,
      'visible': visible,
      'version': _updateController.currentVersion,
      'startedAt': _startedAt.toUtc().toIso8601String(),
      'uptimeSeconds': DateTime.now().difference(_startedAt).inSeconds,
      'selectedLanguage': _selectedLanguage.id,
      'selectedMenu': _items[_selectedIndex].id,
      'update': {
        'status': _updateController.status,
        'busy': _updateController.busy,
        'availableVersion': _updateController.available?.manifest.version,
        'lastCheckedAt':
            _updateController.lastCheckedAt?.toUtc().toIso8601String(),
      },
    };
  }

  Future<Map<String, dynamic>> _handleAdminAction(String action) async {
    switch (action) {
      case 'show':
        await _trayController.showWindow();
        return {'message': '사이니지 화면을 표시했습니다.'};
      case 'hide':
        await _trayController.hideWindow();
        return {'message': '사이니지 화면을 감췄습니다.'};
      case 'restart':
        Timer(const Duration(milliseconds: 500), _restartApplication);
        return {'message': '사이니지를 재시작합니다.'};
      case 'shutdown':
        Timer(
          const Duration(milliseconds: 500),
          () => unawaited(_trayController.exitApplication()),
        );
        return {'message': '사이니지를 완전히 종료합니다.'};
      case 'update':
        await _updateController.initialize();
        final available = await _updateController.check(rethrowErrors: true);
        if (available == null) {
          return {'message': '이미 최신 버전입니다.'};
        }
        final package = await _updateController.download(
          allowAutoInstall: false,
          rethrowErrors: true,
        );
        if (package == null) throw StateError('업데이트 패키지를 내려받지 못했습니다.');
        Timer(
          const Duration(milliseconds: 500),
          () => unawaited(_updateController.installNow()),
        );
        return {
          'message': '업데이트 설치를 시작합니다.',
          'version': available.manifest.version,
        };
    }
    throw ArgumentError.value(action, 'action', '지원하지 않는 관리 작업');
  }

  Future<void> _saveExternalConfig(Map<String, dynamic> config) async {
    await const MenuConfigLoader().saveOverride(config);
    Timer(const Duration(milliseconds: 500), widget.onReloadConfig);
  }

  void _restartApplication() {
    unawaited(
      Process.start(
        Platform.resolvedExecutable,
        const ['--restart-delay'],
        mode: ProcessStartMode.detached,
      ).then((_) => exit(0)),
    );
  }

  @override
  void didUpdateWidget(covariant _KioskHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.toolbarInitiallyHidden !=
        widget.layout.toolbarInitiallyHidden) {
      _toolbarHidden = widget.layout.toolbarInitiallyHidden;
    }
    final previousLanguageId = oldWidget.languages[_selectedLanguageIndex].id;
    final matchingIndex = widget.languages.indexWhere(
      (language) => language.id == previousLanguageId,
    );
    _selectedLanguageIndex =
        matchingIndex >= 0 ? matchingIndex : _defaultLanguageIndex();
    if (_selectedIndex >= _items.length) {
      _resetWebViewsForLanguage();
    }
  }

  int _defaultLanguageIndex() {
    final index = widget.languages.indexWhere(
      (language) => language.id == widget.defaultLanguageId,
    );
    return index >= 0 ? index : 0;
  }

  void _resetWebViewsForLanguage() {
    _selectedIndex = 0;
    _pendingIndex = null;
    _mountedIndices
      ..clear()
      ..add(0);
    _readyIndices.clear();
    _controllers.clear();
  }

  void _selectLanguage(int index) {
    if (index < 0 || index >= widget.languages.length) return;
    setState(() {
      _selectedLanguageIndex = index;
      _showLanguageSelection = false;
      _toolbarHidden = widget.layout.toolbarInitiallyHidden;
      _resetWebViewsForLanguage();
    });
  }

  void _hideToolbar() {
    if (_toolbarHidden) return;
    setState(() => _toolbarHidden = true);
  }

  void _showToolbar() {
    if (!_toolbarHidden) return;
    setState(() => _toolbarHidden = false);
  }

  void _prepareHideSignageGesture() {
    _hideSignageGestureExpiresAt =
        DateTime.now().add(_hideSignageGestureWindow);
  }

  void _completeHideSignageGesture() {
    final expiresAt = _hideSignageGestureExpiresAt;
    _hideSignageGestureExpiresAt = null;
    if (expiresAt != null && !DateTime.now().isAfter(expiresAt)) {
      unawaited(_trayController.hideWindow());
      return;
    }
    _hideToolbar();
  }

  KioskWebViewController? get _currentController =>
      _controllers[_selectedIndex];

  void _onSelect(int index) {
    if (index < 0 || index >= _items.length) return;

    // 이미 백그라운드에서 준비 중인 메뉴를 다시 눌러도 빈 WebView로 먼저
    // 전환하지 않는다.
    if (_pendingIndex == index) return;

    final item = _items[index];
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
    if (_items.isEmpty) return;
    final languageIdAtEntry = _selectedLanguage.id;
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
      _toolbarHidden = true;
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
      if (_selectedLanguage.id == languageIdAtEntry &&
          !_showLanguageSelection) {
        _controllers[0]?.loadUrl(_items.first.url);
      }
    }();
  }

  /// 대기화면에서 깨어날 때 호출.
  ///
  /// 이미 [_onEnterIdle] 에서 정리되었으므로 여기서는 인덱스만 홈으로 보장한다.
  void _onWake() {
    _updateController.setIdle(false);
    if (_items.isEmpty) return;
    setState(() {
      _selectedIndex = 0;
      _showLanguageSelection = true;
    });
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
                Text('$appDisplayName v${info.version}'),
                if (info.buildNumber.isNotEmpty)
                  Text('빌드 번호: ${info.buildNumber}'),
                const Text(
                  'Updater 버전: v${UpdateService.updaterVersion}',
                ),
                const Text(
                  '실행 모드: ${kReleaseMode ? 'Release' : 'Debug'}',
                ),
                Text('운영체제: ${Platform.operatingSystem}'),
                const SizedBox(height: 12),
                const Divider(),
                const Text(
                  'GitHub: https://github.com/cuniverse/simple-kiosk',
                ),
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

  Future<void> _showUserManual() async {
    if (_manualDialogOpen || _manualUpdateRunning || !mounted) return;
    _manualDialogOpen = true;
    try {
      final path = RuntimePaths.child('USER_MANUAL.html');
      if (path == null || !await File(path).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자 매뉴얼 파일을 찾을 수 없습니다.')),
          );
        }
        return;
      }
      final html = await File(path).readAsString();
      if (!mounted) return;
      final baseUrl = WebUri.uri(File(path).uri);
      InAppWebViewController? manualController;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: MediaQuery.sizeOf(dialogContext).width - 48,
            height: MediaQuery.sizeOf(dialogContext).height - 48,
            child: Column(
              children: [
                Material(
                  color: Theme.of(dialogContext).colorScheme.surfaceContainer,
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '뒤로',
                          onPressed: () async {
                            final controller = manualController;
                            if (controller != null &&
                                await controller.canGoBack()) {
                              await controller.goBack();
                            }
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        IconButton(
                          tooltip: '매뉴얼 처음으로',
                          onPressed: () => manualController?.loadData(
                            data: html,
                            baseUrl: baseUrl,
                          ),
                          icon: const Icon(Icons.home_outlined),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.menu_book_outlined),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '$appDisplayName 사용자 매뉴얼',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: InAppWebView(
                    initialData: InAppWebViewInitialData(
                      data: html,
                      baseUrl: baseUrl,
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: false,
                      useShouldOverrideUrlLoading: true,
                      supportZoom: true,
                    ),
                    onWebViewCreated: (controller) {
                      manualController = controller;
                    },
                    shouldOverrideUrlLoading: (controller, action) async {
                      final scheme = action.request.url?.scheme;
                      return const {'file', 'about', 'http', 'https'}
                              .contains(scheme)
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                    onCreateWindow: (controller, action) async => false,
                    onDownloadStartRequest: (controller, request) async {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _manualDialogOpen = false;
    }
  }

  Future<void> _showAdminSettings() async {
    if (!mounted) return;
    await UpdateAdminDialog.show(
      context,
      _updateController,
      adminApiController: _adminApiController,
      onExit: _exitApplication,
    );
  }

  Future<void> _exitApplication() async {
    if (Platform.isWindows) {
      await _trayController.exitApplication();
      return;
    }
    await SystemNavigator.pop();
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final position = _effectivePosition(constraints.maxWidth);

                    // 메뉴별 WebView 를 IndexedStack 에 lazy 배치.
                    // 한 번이라도 방문한 항목만 실제 KioskWebView 로 mount 된다.
                    final webViewStack = IndexedStack(
                      index: _selectedIndex,
                      children: List<Widget>.generate(_items.length, (i) {
                        if (!_mountedIndices.contains(i)) {
                          return const SizedBox.shrink();
                        }
                        final item = _items[i];
                        return KioskWebView(
                          key: ValueKey(
                            'kiosk-webview-${_selectedLanguage.id}-${item.id}',
                          ),
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
                        items: _items,
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
                        buttonForegroundColor:
                            widget.layout.buttonForegroundColor,
                        selectedButtonColor: widget.layout.selectedButtonColor,
                        selectedButtonForegroundColor:
                            widget.layout.selectedButtonForegroundColor,
                        onHide: _hideToolbar,
                        onEnterIdle: widget.idle.isUsable
                            ? _idleGateController.enterIdle
                            : null,
                        onOpenAdmin: UpdateAdminDialog.isConfigured
                            ? _showAdminSettings
                            : null,
                        onPrepareHideKiosk: _prepareHideSignageGesture,
                        onHideKiosk: _completeHideSignageGesture,
                      ),
                    );

                    // 모든 배치에서 WebView를 Stack의 첫 번째 자식으로 유지해
                    // 툴바를 감추거나 보여도 현재 페이지 상태가 보존되게 한다.
                    return ToolbarHost(
                      hidden: _toolbarHidden,
                      position: position,
                      sideWidth: widget.layout.sideWidth,
                      toolbarHeight: widget.layout.barHeight,
                      autoHideDuration: Duration(
                        seconds: widget.layout.toolbarAutoHideSec,
                      ),
                      onAutoHide: _hideToolbar,
                      webView: webViewStack,
                      toolbar: nav,
                      overlay: CollapsedToolbarOverlay(
                        historyController: _currentController,
                        onShowToolbar: _showToolbar,
                      ),
                    );
                  },
                ),
                if (_showLanguageSelection)
                  Positioned.fill(
                    child: LanguageSelection(
                      languages: widget.languages,
                      title: widget.languageSelectionTitle,
                      subtitle: widget.languageSelectionSubtitle,
                      onSelected: _selectLanguage,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return KioskShortcuts(
      onShowManual: _showUserManual,
      onShowVersion: _showVersionInfo,
      onCheckUpdate: _checkUpdateFromShortcut,
      child: content,
    );
  }
}
