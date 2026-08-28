import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'app_identity.dart';

import 'model/idle_config.dart';
import 'model/layout_config.dart';
import 'model/menu_config.dart';
import 'model/menu_item.dart';
import 'model/menu_language.dart';
import 'model/menu_topic.dart';
import 'model/webview_slot_id.dart';
import 'model/webview_data_policy.dart';
import 'service/admin_api_controller.dart';
import 'service/app_logger.dart';
import 'service/configuration_backup_service.dart';
import 'service/font_resource_service.dart';
import 'service/menu_config_loader.dart';
import 'service/runtime_paths.dart';
import 'widget/idle_gate.dart';
import 'widget/kiosk_webview.dart';
import 'widget/navigation_menu.dart';
import 'widget/virtual_keyboard.dart';
import 'widget/webview_loading_overlay.dart';
import 'service/keyboard_controller.dart';
import 'service/kiosk_tray_controller.dart';
import 'service/system_keyboard.dart';
import 'service/touch_input_guard.dart';
import 'service/webview_data_service.dart';
import 'service/app_health_signal.dart';
import 'service/update_controller.dart';
import 'service/update_service.dart';
import 'service/user_manual_service.dart';
import 'service/windows_firewall_service.dart';
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
    return ValueListenableBuilder<ResolvedFontResource>(
      valueListenable: FontResourceService.current,
      builder: (context, font, _) => MaterialApp(
        title: appDisplayName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          fontFamily: font.effectiveFamily,
        ),
        // 모든 화면 위에 가상 키보드 오버레이를 띄울 수 있도록 builder 로 감싼다.
        // KeyboardController.visible 가 true 일 때만 키보드 위젯이 표시된다.
        builder: (context, child) {
          return Stack(
            children: [
              if (child != null) child,
              ValueListenableBuilder<bool>(
                valueListenable: SystemKeyboard.builtInEnabled,
                builder: (context, builtInEnabled, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: KeyboardController.instance.visible,
                    builder: (context, visible, _) {
                      if (!builtInEnabled || !visible) {
                        return const SizedBox.shrink();
                      }
                      return const VirtualKeyboardOverlay();
                    },
                  );
                },
              ),
            ],
          );
        },
        home: const _MenuBootstrap(),
      ),
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
    _future = () async {
      final config = await const MenuConfigLoader().load();
      await FontResourceService.apply(
        config.layout.fontFamily,
        additionalFamilies: [
          config.layout.menuFontFamily,
          config.languageSelectionFontFamily,
          for (final language in config.languages) ...[
            language.fontFamily,
            for (final topic in language.effectiveTopics)
              for (final item in topic.items) item.fontFamily,
          ],
        ],
      );
      return config;
    }();
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
          languageSelectionFontFamily:
              snapshot.data!.languageSelectionFontFamily,
          topicSelectionTitle: snapshot.data!.topicSelectionTitle,
          topicSelectionSubtitle: snapshot.data!.topicSelectionSubtitle,
          skipSingleTopic: snapshot.data!.skipSingleTopic,
          layout: snapshot.data!.layout,
          idle: snapshot.data!.idle,
          webViewDataPolicy: snapshot.data!.webViewDataPolicy,
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
  final String? languageSelectionFontFamily;
  final String topicSelectionTitle;
  final String topicSelectionSubtitle;
  final bool skipSingleTopic;
  final LayoutConfig layout;
  final IdleConfig idle;
  final WebViewDataPolicy webViewDataPolicy;
  final VoidCallback onReloadConfig;
  const _KioskHome({
    required this.languages,
    required this.defaultLanguageId,
    required this.languageSelectionTitle,
    required this.languageSelectionSubtitle,
    required this.languageSelectionFontFamily,
    required this.topicSelectionTitle,
    required this.topicSelectionSubtitle,
    required this.skipSingleTopic,
    required this.layout,
    required this.idle,
    required this.webViewDataPolicy,
    required this.onReloadConfig,
  });

  @override
  State<_KioskHome> createState() => _KioskHomeState();
}

class _KioskHomeState extends State<_KioskHome> {
  late String _selectedLanguageId;
  late String _selectedTopicId;
  late String _selectedMenuId;
  bool _showLanguageSelection = false;
  int _languageSelectionGeneration = 0;
  bool _languageSelectionTransitioning = false;
  final IdleGateController _idleGateController = IdleGateController();
  late final UpdateController _updateController;
  late final KioskTrayController _trayController;
  late final AdminApiController _adminApiController;
  final WindowsFirewallService _windowsFirewallService =
      WindowsFirewallService();
  final DateTime _startedAt = DateTime.now();
  bool _versionDialogOpen = false;
  bool _manualDialogOpen = false;
  bool _manualUpdateRunning = false;
  String? _versionLabel;

  /// 최초 방문 메뉴가 백그라운드에서 준비되는 동안 선택 표시할 슬롯.
  /// 언어와 메뉴 ID를 함께 사용해 순서 변경에도 동일 WebView를 추적한다.
  WebViewSlotId? _pendingSlot;
  Timer? _pendingOverlayTimer;
  Timer? _pendingTimeoutTimer;
  bool _showPendingOverlay = false;
  bool _pendingTimedOut = false;
  static const Duration _pendingOverlayDelay = Duration(milliseconds: 200);
  static const Duration _pendingTimeout = Duration(seconds: 12);

  /// 네비게이션 툴바를 감추었는지 여부.
  ///
  /// 접힌 동안에는 WebView 위에 최소 조작 버튼만 플로팅으로 남긴다.
  late bool _toolbarHidden;

  /// 화면 보호기 더블클릭 후 툴바 감추기 더블클릭을 받을 수 있는 시각.
  DateTime? _hideSignageGestureExpiresAt;
  static const Duration _hideSignageGestureWindow = Duration(seconds: 5);

  /// 언어 ID + 메뉴 ID별 컨트롤러.
  final Map<WebViewSlotId, KioskWebViewController> _controllers = {};

  /// 한 번이라도 방문한(=WebView 가 mount 된) 메뉴 인덱스 집합.
  ///
  /// IndexedStack 의 자식 중 mount 안 된 항목은 [SizedBox.shrink] 로 두어
  /// 메모리(WebView2 인스턴스) 를 절약한다. 첫 항목은 앱 시작 시 자동 mount.
  final Set<WebViewSlotId> _mountedSlots = {};

  /// 최초 페이지 로드가 끝나 즉시 화면 전환할 수 있는 메뉴 인덱스 집합.
  final Set<WebViewSlotId> _readySlots = {};

  /// WebView 트리를 명시적으로 교체할 때 증가한다. 이전 세대에서 늦게 도착한
  /// onReady/onInitialLoadReady 콜백은 현재 상태를 변경할 수 없다.
  final WebViewGeneration _webViewGeneration = WebViewGeneration();

  /// 더블 탭 감지를 위한 마지막 탭 시점/대상 메뉴.
  ///
  /// `keepStateOnTap` 옵션이 켜진 경우, 같은 메뉴를 짧은 시간(300ms) 내에 두
  /// 번 누르면 강제 reload 하도록 한다.
  DateTime? _lastTapAt;
  WebViewSlotId? _lastTapSlot;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);
  final TouchInputGuard<WebViewSlotId> _touchInputGuard = TouchInputGuard();

  int get _selectedLanguageIndex {
    final index = widget.languages.indexWhere(
      (language) => language.id == _selectedLanguageId,
    );
    return index >= 0 ? index : 0;
  }

  MenuLanguage get _selectedLanguage =>
      widget.languages[_selectedLanguageIndex];

  MenuTopic get _selectedTopic {
    final matches = _selectedLanguage.effectiveTopics.where(
      (topic) => topic.id == _selectedTopicId,
    );
    return matches.isNotEmpty ? matches.first : _selectedLanguage.defaultTopic;
  }

  List<MenuItem> get _items => _selectedTopic.items;

  MenuItem get _defaultMenu => _selectedTopic.defaultItem;

  int get _selectedIndex {
    final index = _items.indexWhere((item) => item.id == _selectedMenuId);
    return index >= 0 ? index : 0;
  }

  int? get _pendingIndex {
    final pending = _pendingSlot;
    if (pending == null ||
        pending.languageId != _selectedLanguage.id ||
        pending.topicId != _selectedTopic.id) {
      return null;
    }
    final index = _items.indexWhere((item) => item.id == pending.menuId);
    return index >= 0 ? index : null;
  }

  WebViewSlotId _slotFor(MenuItem item) => WebViewSlotId(
        languageId: _selectedLanguage.id,
        topicId: _selectedTopic.id,
        menuId: item.id,
      );

  WebViewSlotId get _selectedSlot => WebViewSlotId(
        languageId: _selectedLanguage.id,
        topicId: _selectedTopic.id,
        menuId: _selectedMenuId,
      );

  MenuItem? get _pendingItem {
    final pending = _pendingSlot;
    if (pending == null ||
        pending.languageId != _selectedLanguage.id ||
        pending.topicId != _selectedTopic.id) {
      return null;
    }
    for (final item in _items) {
      if (item.id == pending.menuId) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    SystemKeyboard.configure(widget.layout.keyboardMode);
    _selectedLanguageId = _defaultLanguageId();
    _selectedTopicId = _selectedLanguage.defaultTopicId;
    _selectedMenuId = _defaultMenu.id;
    // 시작 화면보호기가 켜진 경우 첫 WebView를 즉시 만들지 않는다. IdleGate의
    // 초기 진입 콜백에서 화면보호기 뒤에 한 번만 mount해 Windows 플랫폼 뷰가
    // 생성 도중 교체되는 시작 경합을 피한다.
    if (!(widget.idle.isUsable && widget.idle.startOnLaunch)) {
      _mountedSlots.add(_selectedSlot);
    }
    _toolbarHidden = widget.layout.toolbarInitiallyHidden;
    _updateController = UpdateController();
    unawaited(_updateController.initialize());
    unawaited(_loadVersionLabel());
    _trayController = KioskTrayController(
      onOpenSettings: _showAdminSettings,
      onOpenManual: _showUserManual,
      onOpenWebAdmin: _openWebAdminFromTray,
      onRestart: () async => _restartApplication(),
      shortcutLockdownEnabled: widget.layout.windowsKioskLockdown,
      shortcutSettings: widget.layout.windowsKioskShortcuts,
      disableEdgeSwipe: widget.layout.windowsDisableEdgeSwipe,
      alwaysOnTopEnabled: widget.layout.windowsAlwaysOnTop,
      preventScreenSaver: widget.layout.windowsPreventScreenSaver,
      preventDisplaySleep: widget.layout.windowsPreventDisplaySleep,
    );
    const configLoader = MenuConfigLoader();
    _adminApiController = AdminApiController(
      statusProvider: _adminStatus,
      actionHandler: _handleAdminAction,
      configReader: configLoader.readOverride,
      effectiveConfigReader: configLoader.readEffective,
      defaultConfigReader: configLoader.readDefaults,
      configWriter: _saveExternalConfig,
      backupService: const ConfigurationBackupService(),
      onConfigurationImported: () async => widget.onReloadConfig(),
      beforeNetworkStart: (settings) async {
        await _windowsFirewallService.reconcile(settings);
      },
    );
    _adminApiController.addListener(_updateTrayWebAdminState);
    unawaited(_initializeTray());
    unawaited(_initializeAdminApi());
  }

  @override
  void dispose() {
    _pendingOverlayTimer?.cancel();
    _pendingTimeoutTimer?.cancel();
    unawaited(_trayController.dispose());
    _adminApiController.removeListener(_updateTrayWebAdminState);
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

  Future<void> _loadVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _versionLabel = info.version);
    } catch (error) {
      if (kDebugMode) debugPrint('[version] 버전 읽기 실패: $error');
    }
  }

  Future<void> _initializeAdminApi() async {
    try {
      await _adminApiController.initialize();
    } catch (error) {
      if (kDebugMode) debugPrint('[admin-api] 초기화 실패: $error');
    }
  }

  void _updateTrayWebAdminState() {
    final tunnel = _adminApiController.webAdminSshTunnel;
    final forwardingActive =
        _adminApiController.settings.webAdminSshForwardingEnabled &&
            tunnel.connected &&
            tunnel.forwardingVerified;
    _trayController.updateWebAdminState(
      available: _adminApiController.running,
      reverseForwardingStatus: forwardingActive ? '연결됨' : '연결 안 됨',
      reverseForwardingUri:
          forwardingActive ? _adminApiController.webAdminSshRemoteUri : null,
    );
  }

  Future<void> _openWebAdminFromTray() async {
    final port = _adminApiController.actualPort;
    if (!_adminApiController.running || port == null) return;
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port == 80 ? null : port,
    );
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('기본 브라우저를 실행할 수 없습니다.');
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.api, error, stackTrace);
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
      'system': {
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'buildMode': kReleaseMode ? 'release' : 'debug',
        'updaterVersion': UpdateService.updaterVersion,
      },
      'selectedLanguage': _selectedLanguage.id,
      'selectedTopic': _selectedTopic.id,
      'selectedMenu': _items[_selectedIndex].id,
      'webViewData': {
        'sharing': {
          'cookies': true,
          'cache': true,
          'localStorage': true,
        },
        'idlePolicy': widget.webViewDataPolicy.idlePolicy.name,
        'preserveDomains': widget.webViewDataPolicy.preserveDomains,
      },
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
          () => unawaited(_updateController.installNow(manual: true)),
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
    if (oldWidget.layout.keyboardMode != widget.layout.keyboardMode) {
      SystemKeyboard.configure(widget.layout.keyboardMode);
    }
    if (oldWidget.layout.windowsKioskLockdown !=
            widget.layout.windowsKioskLockdown ||
        oldWidget.layout.windowsKioskShortcuts !=
            widget.layout.windowsKioskShortcuts ||
        oldWidget.layout.windowsDisableEdgeSwipe !=
            widget.layout.windowsDisableEdgeSwipe ||
        oldWidget.layout.windowsAlwaysOnTop !=
            widget.layout.windowsAlwaysOnTop ||
        oldWidget.layout.windowsPreventScreenSaver !=
            widget.layout.windowsPreventScreenSaver ||
        oldWidget.layout.windowsPreventDisplaySleep !=
            widget.layout.windowsPreventDisplaySleep) {
      unawaited(_trayController.configureKioskMode(
        shortcutLockdownEnabled: widget.layout.windowsKioskLockdown,
        shortcutSettings: widget.layout.windowsKioskShortcuts,
        disableEdgeSwipe: widget.layout.windowsDisableEdgeSwipe,
        alwaysOnTopEnabled: widget.layout.windowsAlwaysOnTop,
        preventScreenSaver: widget.layout.windowsPreventScreenSaver,
        preventDisplaySleep: widget.layout.windowsPreventDisplaySleep,
      ));
    }
    if (oldWidget.layout.toolbarInitiallyHidden !=
        widget.layout.toolbarInitiallyHidden) {
      _toolbarHidden = widget.layout.toolbarInitiallyHidden;
    }
    final previousLanguageId = _selectedLanguageId;
    final definitionsChanged = _webViewDefinitionsChanged(oldWidget, widget);
    final matchingIndex = widget.languages.indexWhere(
      (language) => language.id == previousLanguageId,
    );
    _selectedLanguageId =
        matchingIndex >= 0 ? previousLanguageId : _defaultLanguageId();
    if (!_selectedLanguage.effectiveTopics
        .any((topic) => topic.id == _selectedTopicId)) {
      _selectedTopicId = _selectedLanguage.defaultTopicId;
    }
    if (matchingIndex < 0 || definitionsChanged) {
      _resetWebViewsForLanguage();
      return;
    }

    final validSlots = <WebViewSlotId>{
      for (final language in widget.languages)
        for (final topic in language.effectiveTopics)
          for (final item in topic.items)
            WebViewSlotId(
              languageId: language.id,
              topicId: topic.id,
              menuId: item.id,
            ),
    };
    _mountedSlots.removeWhere((slot) => !validSlots.contains(slot));
    _readySlots.removeWhere((slot) => !validSlots.contains(slot));
    _controllers.removeWhere((slot, _) => !validSlots.contains(slot));
    if (!_items.any((item) => item.id == _selectedMenuId)) {
      _resetWebViewsForLanguage();
    }
  }

  bool _webViewDefinitionsChanged(_KioskHome oldWidget, _KioskHome newWidget) {
    final oldUrls = <WebViewSlotId, String>{
      for (final language in oldWidget.languages)
        for (final topic in language.effectiveTopics)
          for (final item in topic.items)
            WebViewSlotId(
              languageId: language.id,
              topicId: topic.id,
              menuId: item.id,
            ): item.url,
    };
    final newUrls = <WebViewSlotId, String>{
      for (final language in newWidget.languages)
        for (final topic in language.effectiveTopics)
          for (final item in topic.items)
            WebViewSlotId(
              languageId: language.id,
              topicId: topic.id,
              menuId: item.id,
            ): item.url,
    };
    // 순서만 바뀐 경우에는 슬롯과 WebView 상태를 그대로 유지한다.
    if (!setEquals(oldUrls.keys.toSet(), newUrls.keys.toSet())) return true;
    for (final entry in oldUrls.entries) {
      if (newUrls[entry.key] != entry.value) return true;
    }
    return false;
  }

  String _defaultLanguageId() {
    final language = widget.languages.where(
      (language) => language.id == widget.defaultLanguageId,
    );
    return language.isNotEmpty ? language.first.id : widget.languages.first.id;
  }

  void _resetWebViewsForLanguage() {
    _webViewGeneration.next();
    _selectedMenuId = _defaultMenu.id;
    _pendingSlot = null;
    _clearPendingFeedback();
    _mountedSlots
      ..clear()
      ..add(_selectedSlot);
    _readySlots.clear();
    _controllers.clear();
    _touchInputGuard.clear();
    _lastTapAt = null;
    _lastTapSlot = null;
  }

  void _selectLanguageAndTopic(int languageIndex, int topicIndex) {
    if (languageIndex < 0 ||
        languageIndex >= widget.languages.length ||
        _languageSelectionTransitioning) {
      return;
    }
    final language = widget.languages[languageIndex];
    if (topicIndex < 0 || topicIndex >= language.effectiveTopics.length) {
      return;
    }
    final topic = language.effectiveTopics[topicIndex];
    final selectionChanged =
        language.id != _selectedLanguageId || topic.id != _selectedTopicId;
    _languageSelectionTransitioning = true;

    // 언어 선택 화면을 한 프레임 더 유지한 상태에서 WebView와 툴바 배치를 먼저
    // 완성한다. 네이티브 WebView 크기 변경이 사용자에게 노출되지 않아 툴바가
    // 번쩍이는 현상을 막는다.
    setState(() {
      _selectedLanguageId = language.id;
      _selectedTopicId = topic.id;
      _toolbarHidden = widget.layout.toolbarInitiallyHidden;
      if (selectionChanged) {
        _resetWebViewsForLanguage();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showLanguageSelection = false;
        _languageSelectionTransitioning = false;
      });
    });
  }

  void _showLanguageSelectionScreen() {
    if (_showLanguageSelection || _languageSelectionTransitioning) return;
    setState(() {
      _pendingSlot = null;
      _clearPendingFeedback();
      _showLanguageSelection = true;
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

  KioskWebViewController? get _currentController => _controllers[_selectedSlot];

  void _clearPendingFeedback() {
    _pendingOverlayTimer?.cancel();
    _pendingTimeoutTimer?.cancel();
    _pendingOverlayTimer = null;
    _pendingTimeoutTimer = null;
    _showPendingOverlay = false;
    _pendingTimedOut = false;
  }

  void _startPendingFeedback(
    WebViewSlotId slot, {
    bool showImmediately = false,
  }) {
    _clearPendingFeedback();
    final generation = _webViewGeneration.value;
    _showPendingOverlay = showImmediately;
    if (!showImmediately) {
      _pendingOverlayTimer = Timer(_pendingOverlayDelay, () {
        if (!mounted ||
            _pendingSlot != slot ||
            !_webViewGeneration.isCurrent(generation)) {
          return;
        }
        setState(() => _showPendingOverlay = true);
      });
    }
    _pendingTimeoutTimer = Timer(_pendingTimeout, () {
      if (!mounted ||
          _pendingSlot != slot ||
          !_webViewGeneration.isCurrent(generation)) {
        return;
      }
      setState(() {
        _showPendingOverlay = true;
        _pendingTimedOut = true;
      });
    });
  }

  void _cancelPendingSelection() {
    final pending = _pendingSlot;
    if (pending == null) return;
    setState(() {
      _discardPendingMount(pending);
      _pendingSlot = null;
      _clearPendingFeedback();
    });
  }

  /// 화면에 선택되지 않았고 아직 준비도 끝나지 않은 이전 후보 WebView를 제거한다.
  /// 빠르게 여러 메뉴를 누를 때 WebView2가 동시에 계속 생성되는 것을 막는다.
  void _discardPendingMount(WebViewSlotId? slot) {
    if (slot == null || slot == _selectedSlot || _readySlots.contains(slot)) {
      return;
    }
    _mountedSlots.remove(slot);
    _controllers.remove(slot);
  }

  void _reloadSlot(WebViewSlotId slot, String url, DateTime now) {
    if (!_touchInputGuard.acceptReload(slot, now)) return;
    final controller = _controllers[slot];
    if (controller != null) unawaited(controller.loadUrl(url));
  }

  void _retryPendingSelection() {
    final slot = _pendingSlot;
    final item = _pendingItem;
    if (slot == null || item == null) return;
    final controller = _controllers[slot];
    setState(() {
      _startPendingFeedback(slot, showImmediately: true);
      if (controller == null) _mountedSlots.remove(slot);
    });
    if (controller != null) {
      controller.loadUrl(item.url);
      return;
    }
    // 컨트롤러 생성 자체가 지연된 경우 해당 슬롯만 한 프레임 언mount한 뒤
    // 다시 생성한다. 현재 보이는 WebView는 그대로 유지된다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingSlot != slot) return;
      setState(() => _mountedSlots.add(slot));
    });
  }

  void _onSelect(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final slot = _slotFor(item);
    final now = DateTime.now();

    // 한 번의 손동작에서 쏟아지는 연속 탭은 하나의 선택으로 합친다.
    if (!_touchInputGuard.acceptSelection(slot, now)) return;

    // 이미 백그라운드에서 준비 중인 메뉴를 다시 눌러도 빈 WebView로 먼저
    // 전환하지 않는다.
    if (_pendingSlot == slot) return;

    final url = item.url;
    // 더블 탭 판정: 같은 메뉴를 윈도우 내에 다시 누른 경우.
    final isDoubleTap = _lastTapSlot == slot &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapWindow;
    if (isDoubleTap) {
      // 세 번째 이후의 연타가 모두 더블 탭으로 판정되어 재로드를 반복하지 않게 한다.
      _lastTapAt = null;
      _lastTapSlot = null;
    } else {
      _lastTapAt = now;
      _lastTapSlot = slot;
    }

    // 항목별 설정이 있으면 우선, 없으면 layout 기본값.
    final keepState = item.keepStateOnTap ?? widget.layout.keepStateOnTap;

    if (kDebugMode) {
      debugPrint(
        '[KioskHome] _onSelect '
        'index=$index id="${item.id}" '
        'currentSelected=$_selectedMenuId '
        'keepState=$keepState (item=${item.keepStateOnTap}, layout=${widget.layout.keepStateOnTap}) '
        'isDoubleTap=$isDoubleTap '
        'mounted=${_mountedSlots.contains(slot)}',
      );
    }

    final wasMounted = _mountedSlots.contains(slot);
    final isReady = _readySlots.contains(slot);

    if (slot == _selectedSlot) {
      // 준비 중이던 다른 메뉴 선택만 취소한다. 현재 메뉴가 상태 유지 모드면
      // 부모 전체를 다시 그릴 필요가 없다.
      if (_pendingSlot != null) {
        final obsoletePending = _pendingSlot;
        setState(() {
          _discardPendingMount(obsoletePending);
          _pendingSlot = null;
          _clearPendingFeedback();
        });
      }
      if (isDoubleTap || !keepState) {
        _reloadSlot(slot, url, now);
      }
      return;
    }

    if (!isReady) {
      // 최초 방문 메뉴는 기존 화면 뒤에서 먼저 mount/load 한다. 페이지가 준비되면
      // [_onInitialLoadReady]가 실제 선택 인덱스를 바꿔 빈 화면 노출을 막는다.
      setState(() {
        _discardPendingMount(_pendingSlot);
        _pendingSlot = slot;
        _mountedSlots.add(slot);
        _startPendingFeedback(slot);
      });
      return;
    }

    final obsoletePending = _pendingSlot;
    setState(() {
      _discardPendingMount(obsoletePending);
      _pendingSlot = null;
      _selectedMenuId = item.id;
      _clearPendingFeedback();
    });

    // 이미 mount 되어 있는 항목.
    if (wasMounted && (isDoubleTap || !keepState)) {
      // 강제 재로드: keepState=false 이거나 더블 탭.
      _reloadSlot(slot, url, now);
    }
    // keepState=true & 단일 탭 & 이미 mount 됨 → 아무 것도 안 함(상태 유지).
  }

  void _onInitialLoadReady(WebViewSlotId slot, int generation) {
    if (!mounted ||
        !_webViewGeneration.isCurrent(generation) ||
        !_mountedSlots.contains(slot)) {
      return;
    }
    final shouldSelect = _pendingSlot == slot;
    setState(() {
      _readySlots.add(slot);
      if (shouldSelect) {
        _selectedMenuId = slot.menuId;
        _pendingSlot = null;
        _clearPendingFeedback();
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
        '(mounted=${_mountedSlots.map((slot) => '${slot.languageId}/${slot.menuId}').toList()..sort()})',
      );
    }
    setState(() {
      _toolbarHidden = true;
      // 화면보호기에서 다시 깨어날 때 이전 주제 선택 상태가 남지 않도록
      // 언어 선택 화면의 State를 새로 만든다.
      _languageSelectionGeneration += 1;
      _webViewGeneration.next();
      _selectedMenuId = _defaultMenu.id;
      _pendingSlot = null;
      _clearPendingFeedback();
      final homeSlot = _selectedSlot;
      // 홈만 남기고 모두 언mount.
      _mountedSlots
        ..clear()
        ..add(homeSlot);
      _readySlots.clear();
      // 새 세대로 교체되므로 이전 WebView 컨트롤러는 모두 무효다.
      _controllers.clear();
    });
    // 쿠키 삭제 후 홈을 초기 URL 로 리셋. 순서 보장을 위해 await.
    () async {
      // idle 진입 시 떠 있던 OS 가상 키보드도 함께 닫는다.
      await SystemKeyboard.hide();
      try {
        await WebViewDataService.applyIdlePolicy(
          widget.webViewDataPolicy,
          knownUrls: widget.languages.expand(
            (language) => language.effectiveTopics.expand(
              (topic) => topic.items.map((item) => item.url),
            ),
          ),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[KioskHome] 쿠키 삭제 실패: $e');
        }
      }
      if (!mounted) return;
      if (_selectedLanguage.id == languageIdAtEntry &&
          !_showLanguageSelection) {
        _controllers[_selectedSlot]?.loadUrl(_defaultMenu.url);
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
      _selectedMenuId = _defaultMenu.id;
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
    if (_selectedMenuId != _defaultMenu.id) {
      _onSelect(_items.indexWhere((item) => item.id == _defaultMenu.id));
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
      late final String html;
      late final WebUri baseUrl;
      if (path != null && await File(path).exists()) {
        html = await File(path).readAsString();
        baseUrl = WebUri.uri(File(path).uri);
      } else {
        try {
          final markdownSource = await rootBundle.loadString('docs/MANUAL.md');
          html = buildUserManualHtml(markdownSource);
          baseUrl = WebUri(userManualRepositoryDocsBase);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('사용자 매뉴얼을 불러올 수 없습니다.')),
            );
          }
          return;
        }
      }
      if (!mounted) return;
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
      keyboardMode: widget.layout.keyboardMode,
      onKeyboardModeChanged: _saveKeyboardMode,
    );
  }

  Future<void> _saveKeyboardMode(KeyboardMode mode) async {
    const loader = MenuConfigLoader();
    final config = await loader.readEffective();
    final layout = Map<String, dynamic>.from(
      config['layout'] as Map<String, dynamic>? ?? const {},
    );
    layout['keyboardMode'] =
        mode == KeyboardMode.windows ? 'windows' : 'builtin';
    config['layout'] = layout;
    await loader.saveOverride(config);
    SystemKeyboard.configure(mode);
    Timer(const Duration(milliseconds: 500), widget.onReloadConfig);
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
        () => _updateController.installNow(
          manual: true,
          confirmSetupFallback: _confirmSetupUpdateFallback,
        ),
      );
    } catch (error) {
      if (mounted) await _showMessage('업데이트 실패', '$error');
    } finally {
      _manualUpdateRunning = false;
    }
  }

  Future<bool> _confirmSetupUpdateFallback(Object error) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Setup으로 업데이트'),
            content: Text(
              '기본 업데이터가 실패했습니다.\n\n$error\n\n'
              'GitHub Release의 Setup 설치 파일을 다운로드하고 '
              '검증한 뒤 실행할까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Setup 다운로드 및 실행'),
              ),
            ],
          ),
        ) ??
        false;
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
                    final languageId = _selectedLanguage.id;
                    final topicId = _selectedTopic.id;
                    final generation = _webViewGeneration.value;

                    // 메뉴별 WebView 를 IndexedStack 에 lazy 배치.
                    // 한 번이라도 방문한 항목만 실제 KioskWebView 로 mount 된다.
                    final webViewStack = IndexedStack(
                      index: _selectedIndex,
                      children: List<Widget>.generate(_items.length, (i) {
                        final item = _items[i];
                        final slot = WebViewSlotId(
                          languageId: languageId,
                          topicId: topicId,
                          menuId: item.id,
                        );
                        if (!_mountedSlots.contains(slot)) {
                          return SizedBox.shrink(
                            key: ValueKey(
                              'empty-${slot.languageId}-${slot.menuId}-$generation',
                            ),
                          );
                        }
                        return KioskWebView(
                          key: ValueKey(
                            'kiosk-webview-${slot.languageId}-${slot.menuId}-$generation',
                          ),
                          initialUrl: item.url,
                          active: slot == _selectedSlot,
                          onShowManual: _showUserManual,
                          onShowVersion: _showVersionInfo,
                          onCheckUpdate: _checkUpdateFromShortcut,
                          onReady: (c) {
                            if (!mounted ||
                                !_webViewGeneration.isCurrent(generation) ||
                                !_mountedSlots.contains(slot)) {
                              return;
                            }
                            _controllers[slot] = c;
                            // 현재 화면의 history 컨트롤만 새 컨트롤러를 받도록 리빌드.
                            // 백그라운드 준비 메뉴는 완료 콜백에서 함께 갱신된다.
                            if (slot == _selectedSlot) setState(() {});
                          },
                          onInitialLoadReady: () =>
                              _onInitialLoadReady(slot, generation),
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
                        selectedTopicLabel: widget.layout.showSelectedTopic
                            ? _selectedTopic.label
                            : null,
                        selectedTopicLabelColor:
                            widget.layout.selectedTopicLabelColor,
                        barColor: widget.layout.barColor,
                        buttonColor: widget.layout.buttonColor,
                        buttonForegroundColor:
                            widget.layout.buttonForegroundColor,
                        selectedButtonColor: widget.layout.selectedButtonColor,
                        selectedButtonForegroundColor:
                            widget.layout.selectedButtonForegroundColor,
                        fontFamily: FontResourceService.familyFor(
                          widget.layout.menuFontFamily,
                        ),
                        onHide: _hideToolbar,
                        onEnterIdle: widget.idle.isUsable
                            ? _idleGateController.enterIdle
                            : null,
                        onOpenAdmin: UpdateAdminDialog.isConfigured
                            ? _showAdminSettings
                            : null,
                        onSelectLanguage: _showLanguageSelectionScreen,
                        onPrepareHideKiosk: _prepareHideSignageGesture,
                        onHideKiosk: _completeHideSignageGesture,
                        versionLabel: _versionLabel,
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
                      versionLabel: _versionLabel,
                    );
                  },
                ),
                if (_showPendingOverlay &&
                    _pendingItem != null &&
                    !_showLanguageSelection)
                  Positioned.fill(
                    child: WebViewLoadingOverlay(
                      title: _pendingItem!.title,
                      timedOut: _pendingTimedOut,
                      onCancel: _cancelPendingSelection,
                      onRetry: _retryPendingSelection,
                    ),
                  ),
                if (_showLanguageSelection)
                  Positioned.fill(
                    child: LanguageSelection(
                      key: ValueKey(
                        'language-selection-$_languageSelectionGeneration',
                      ),
                      languages: widget.languages,
                      title: widget.languageSelectionTitle,
                      subtitle: widget.languageSelectionSubtitle,
                      fontFamily: FontResourceService.familyFor(
                        widget.languageSelectionFontFamily,
                      ),
                      topicTitle: widget.topicSelectionTitle,
                      topicSubtitle: widget.topicSelectionSubtitle,
                      skipSingleTopic: widget.skipSingleTopic,
                      onSelected: _selectLanguageAndTopic,
                      onReturnToIdle: _idleGateController.enterIdle,
                      versionLabel: _versionLabel,
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
