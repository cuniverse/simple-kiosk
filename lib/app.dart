import 'package:flutter/material.dart';

import 'model/layout_config.dart';
import 'model/menu_config.dart';
import 'model/menu_item.dart';
import 'service/menu_config_loader.dart';
import 'widget/kiosk_webview.dart';
import 'widget/navigation_menu.dart';

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

  @override
  void initState() {
    super.initState();
    _future = const MenuConfigLoader().load();
  }

  void _retry() {
    setState(() {
      _future = const MenuConfigLoader().load();
    });
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
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('다시 시도',
                            style: TextStyle(fontSize: 18)),
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
  const _KioskHome({required this.items, required this.layout});

  @override
  State<_KioskHome> createState() => _KioskHomeState();
}

class _KioskHomeState extends State<_KioskHome> {
  int _selectedIndex = 0;
  KioskWebViewController? _webController;

  void _onSelect(int index) {
    if (index < 0 || index >= widget.items.length) return;
    setState(() => _selectedIndex = index);
    final url = widget.items[index].url;
    _webController?.loadUrl(url);
  }

  Future<bool> _onWillPop() async {
    // WebView 뒤로가기 우선.
    final controller = _webController;
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
    // WebView는 한 번만 생성되므로 초기 URL은 항상 첫 번째 메뉴(홈) URL을 사용.
    // 이후 메뉴 전환은 _webController.loadUrl()로 처리한다.
    final initialUrl = widget.items.first.url;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final position = _effectivePosition(constraints.maxWidth);
              final webView = KioskWebView(
                // WebView는 한 번만 생성되며, 이후 URL 변경은 컨트롤러로 수행.
                key: const ValueKey('kiosk-webview'),
                initialUrl: initialUrl,
                onReady: (c) => _webController = c,
              );

              final isSide =
                  position == NavPosition.left || position == NavPosition.right;
              final nav = NavigationMenu(
                items: widget.items,
                selectedIndex: _selectedIndex,
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
              );

              switch (position) {
                case NavPosition.left:
                  return Row(
                    children: [
                      nav,
                      const VerticalDivider(width: 1),
                      Expanded(child: webView),
                    ],
                  );
                case NavPosition.right:
                  return Row(
                    children: [
                      Expanded(child: webView),
                      const VerticalDivider(width: 1),
                      nav,
                    ],
                  );
                case NavPosition.top:
                  return Column(
                    children: [
                      nav,
                      const Divider(height: 1),
                      Expanded(child: webView),
                    ],
                  );
                case NavPosition.bottom:
                case NavPosition.auto: // 이론상 도달 불가 — 안전망.
                  return Column(
                    children: [
                      Expanded(child: webView),
                      const Divider(height: 1),
                      nav,
                    ],
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}
