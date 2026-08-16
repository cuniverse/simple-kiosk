import 'dart:async';

import 'package:flutter/material.dart';

import '../model/layout_config.dart';
import '../model/menu_item.dart';
import '../service/keyboard_controller.dart';
import '../service/system_keyboard.dart';
import 'kiosk_webview.dart';
import 'material_icon_registry.dart';

/// 네비게이션 영역의 표시 방향.
enum NavigationOrientation { side, bottom }

/// 사이드 / 하단 네비게이션을 함께 처리하는 위젯.
///
/// - 좁은 화면에서는 [NavigationOrientation.bottom]을 사용한다.
/// - 터치 사이니지에서 누르기 쉽도록 버튼 최소 높이를 64dp 이상으로 한다.
class NavigationMenu extends StatelessWidget {
  /// 표시할 메뉴 항목들.
  final List<MenuItem> items;

  /// 현재 선택된 메뉴 인덱스.
  final int selectedIndex;

  /// 메뉴 탭/클릭 콜백.
  final ValueChanged<int> onSelected;

  /// 네비게이션 배치 방향.
  final NavigationOrientation orientation;

  /// [orientation]이 [NavigationOrientation.side]일 때 적용되는 폭(dp).
  final double sideWidth;

  /// [orientation]이 [NavigationOrientation.bottom]일 때 적용되는 높이(dp).
  final double barHeight;

  /// 각 버튼의 높이(dp). `0`이면 아이콘/텍스트 유무에 따라 자동 결정.
  final double buttonHeight;

  /// 하단/상단 모드에서 각 버튼의 가로 폭(dp). `0`이면 균등 분배(stretch).
  /// 사이드 모드에서는 무시된다.
  final double buttonWidth;

  /// 버튼 사이 간격(dp).
  final double buttonGap;

  /// 버튼 정렬 방식.
  final NavAlignment buttonAlignment;

  /// 네비게이션 시작(좌/상) 위치에 WebView 뒤로/앞으로 캨트롤을 표시할지.
  ///
  /// `true`이고 [historyController]가 주어지면 네비 시작에 [←] [→] 버튼 두 개를
  /// 만들어 표시한다.
  final bool showHistoryButtons;

  /// 뒤로/앞으로 이동을 수행할 WebView 컨트롤러.
  /// [showHistoryButtons]가 `true`일 때만 사용된다.
  final KioskWebViewController? historyController;

  /// 네비게이션 끝(우/하) 위치에 OS 가상 키보드 호출/닫기 토글 버튼을
  /// 표시할지 여부.
  final bool showKeyboardToggle;

  /// 네비 바 배경색. `null`이면 테마 기본값.
  final Color? barColor;

  /// 비선택 버튼 배경색.
  final Color? buttonColor;

  /// 비선택 버튼 전경색.
  final Color? buttonForegroundColor;

  /// 선택 버튼 배경색.
  final Color? selectedButtonColor;

  /// 선택 버튼 전경색.
  final Color? selectedButtonForegroundColor;

  /// 툴바를 감추는 콜백. `null`이면 숨김 버튼을 표시하지 않는다.
  final VoidCallback? onHide;

  /// 화면 보호기로 즉시 진입하는 콜백. `null`이면 버튼을 표시하지 않는다.
  final VoidCallback? onEnterIdle;

  /// PIN 보호된 설정 화면을 여는 콜백.
  final VoidCallback? onOpenAdmin;

  /// 화면 보호기 더블클릭으로 사이니지 감추기 순서를 시작하는 콜백.
  final VoidCallback? onPrepareHideKiosk;

  /// 툴바 감추기 더블클릭으로 사이니지 감추기 순서를 완료하는 콜백.
  final VoidCallback? onHideKiosk;

  const NavigationMenu({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.orientation,
    this.sideWidth = 220,
    this.barHeight = 96,
    this.buttonHeight = 0,
    this.buttonWidth = 0,
    this.buttonGap = 8,
    this.buttonAlignment = NavAlignment.stretch,
    this.showHistoryButtons = false,
    this.historyController,
    this.showKeyboardToggle = false,
    this.barColor,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
    this.onHide,
    this.onEnterIdle,
    this.onOpenAdmin,
    this.onPrepareHideKiosk,
    this.onHideKiosk,
  });

  @override
  Widget build(BuildContext context) {
    if (orientation == NavigationOrientation.side) {
      return _buildSide(context);
    }
    return _buildBottom(context);
  }

  Widget _buildSide(BuildContext context) {
    final theme = Theme.of(context);
    // 사이드 모드 기본 정렬은 start(위에서부터). stretch는 의미가 없으므로 start로.
    final align = buttonAlignment == NavAlignment.stretch
        ? NavAlignment.start
        : buttonAlignment;
    final mainAxisAlign = _toMainAxisAlignment(align);

    // 버튼들 사이 간격 처리.
    // space* 계열은 자체적으로 간격을 분배하므로 gap을 추가하지 않는다.
    final useSeparator = !_isSpaceAlignment(align);

    final children = <Widget>[];
    if (showHistoryButtons && historyController != null) {
      children.add(_HistoryControls(
        controller: historyController!,
        orientation: NavigationOrientation.side,
      ));
      if (items.isNotEmpty) {
        children.add(SizedBox(height: buttonGap + 4));
      }
    }
    for (var i = 0; i < items.length; i++) {
      if (useSeparator && i > 0) {
        children.add(SizedBox(height: buttonGap));
      }
      children.add(
        _NavButton(
          title: items[i].title,
          iconPath: items[i].icon,
          showTitle: items[i].showTitle,
          selected: i == selectedIndex,
          orientation: NavigationOrientation.side,
          fixedHeight: buttonHeight > 0 ? buttonHeight : null,
          buttonColor: buttonColor,
          buttonForegroundColor: buttonForegroundColor,
          selectedButtonColor: selectedButtonColor,
          selectedButtonForegroundColor: selectedButtonForegroundColor,
          onPressed: () => onSelected(i),
        ),
      );
    }

    return Material(
      color: barColor ?? theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: sideWidth,
          // 키보드 토글이 활성화되면 항상 맨 아래 고정으로 두기 위해
          // 메뉴 영역(스크롤) + 하단 푸터(고정) 구조로 나눈다.
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: ConstrainedBox(
                    // 항목 수가 적으면 정렬이 동작하도록 최소 높이 확보.
                    // 항목이 많아 넘치면 자연스럽게 스크롤 가능.
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height -
                          MediaQuery.of(context).padding.vertical -
                          24, // 상하 padding 근사치
                    ),
                    child: Column(
                      mainAxisAlignment: mainAxisAlign,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
              if (showKeyboardToggle ||
                  onEnterIdle != null ||
                  onOpenAdmin != null ||
                  onHide != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: buttonGap,
                    runSpacing: buttonGap,
                    children: [
                      if (showKeyboardToggle)
                        const _KeyboardToggle(
                          orientation: NavigationOrientation.side,
                        ),
                      if (onOpenAdmin != null)
                        _ToolbarVisibilityButton(
                          icon: Icons.admin_panel_settings_outlined,
                          tooltip: '설정',
                          onPressed: onOpenAdmin!,
                        ),
                      if (onEnterIdle != null)
                        _ToolbarVisibilityButton(
                          icon: Icons.wallpaper_outlined,
                          tooltip: '화면 보호기 시작',
                          onPressed: onEnterIdle!,
                          onDoublePressed: onPrepareHideKiosk,
                        ),
                      if (onHide != null)
                        _ToolbarVisibilityButton(
                          icon: Icons.visibility_off_outlined,
                          tooltip: '툴바 감추기',
                          onPressed: onHide!,
                          onDoublePressed: onHideKiosk,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    final theme = Theme.of(context);
    // 하단 모드 기본은 stretch(Expanded로 균등 분배).
    final align = buttonAlignment;
    final useStretch = align == NavAlignment.stretch && buttonWidth <= 0;

    Widget buildButton(int i) => _NavButton(
          title: items[i].title,
          iconPath: items[i].icon,
          showTitle: items[i].showTitle,
          selected: i == selectedIndex,
          orientation: NavigationOrientation.bottom,
          fixedHeight: buttonHeight > 0 ? buttonHeight : null,
          buttonColor: buttonColor,
          buttonForegroundColor: buttonForegroundColor,
          selectedButtonColor: selectedButtonColor,
          selectedButtonForegroundColor: selectedButtonForegroundColor,
          onPressed: () => onSelected(i),
        );

    final children = <Widget>[];

    // 하단 모드 공통: 좌측에 뒤/앞 버튼 삽입.
    if (showHistoryButtons && historyController != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: _HistoryControls(
            controller: historyController!,
            orientation: NavigationOrientation.bottom,
          ),
        ),
      );
      children.add(SizedBox(width: buttonGap));
    }

    if (useStretch) {
      // 기존 동작: 모든 버튼이 균등하게 공간을 차지.
      for (var i = 0; i < items.length; i++) {
        children.add(
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: buttonGap / 2,
                vertical: 8,
              ),
              child: buildButton(i),
            ),
          ),
        );
      }
      if (showKeyboardToggle) {
        children.add(SizedBox(width: buttonGap));
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: _KeyboardToggle(
              orientation: NavigationOrientation.bottom,
            ),
          ),
        );
      }
      if (onHide != null) {
        children.add(SizedBox(width: buttonGap));
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: _ToolbarVisibilityButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: '툴바 감추기',
              onPressed: onHide!,
              onDoublePressed: onHideKiosk,
            ),
          ),
        );
      }
      if (onEnterIdle != null) {
        children.add(SizedBox(width: buttonGap));
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: _ToolbarVisibilityButton(
              icon: Icons.wallpaper_outlined,
              tooltip: '화면 보호기 시작',
              onPressed: onEnterIdle!,
              onDoublePressed: onPrepareHideKiosk,
            ),
          ),
        );
      }
      if (onOpenAdmin != null) {
        children.add(SizedBox(width: buttonGap));
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: _ToolbarVisibilityButton(
              icon: Icons.admin_panel_settings_outlined,
              tooltip: '설정',
              onPressed: onOpenAdmin!,
            ),
          ),
        );
      }
      return Material(
        color: barColor ?? theme.colorScheme.surfaceContainerHighest,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: barHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: buttonGap / 2),
              child: Row(children: children),
            ),
          ),
        ),
      );
    }

    // 고정 폭 버튼 + 정렬 적용.
    // 버튼 폭이 지정되지 않은 경우는 메뉴 수와 상관없이 고정값을 쓸 수 있도록 120dp 사용.
    final btnW = buttonWidth > 0 ? buttonWidth : 120.0;
    final useSeparator = !_isSpaceAlignment(align);

    for (var i = 0; i < items.length; i++) {
      if (useSeparator && i > 0) {
        children.add(SizedBox(width: buttonGap));
      }
      children.add(
        SizedBox(
          width: btnW,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: buildButton(i),
          ),
        ),
      );
    }
    if (showKeyboardToggle) {
      // 고정폭/space 정렬 모드 모두에서 토글을 오른쪽 끝에 고정시키기 위해
      // 가변 공간(Spacer)을 끼우고 마지막에 배치.
      children.add(const Spacer());
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: _KeyboardToggle(
            orientation: NavigationOrientation.bottom,
          ),
        ),
      );
    }
    if (onHide != null) {
      if (!showKeyboardToggle) children.add(const Spacer());
      children.add(SizedBox(width: buttonGap));
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: _ToolbarVisibilityButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: '툴바 감추기',
            onPressed: onHide!,
            onDoublePressed: onHideKiosk,
          ),
        ),
      );
    }
    if (onEnterIdle != null) {
      if (!showKeyboardToggle && onHide == null) children.add(const Spacer());
      children.add(SizedBox(width: buttonGap));
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: _ToolbarVisibilityButton(
            icon: Icons.wallpaper_outlined,
            tooltip: '화면 보호기 시작',
            onPressed: onEnterIdle!,
            onDoublePressed: onPrepareHideKiosk,
          ),
        ),
      );
    }
    if (onOpenAdmin != null) {
      if (!showKeyboardToggle && onHide == null && onEnterIdle == null) {
        children.add(const Spacer());
      }
      children.add(SizedBox(width: buttonGap));
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: _ToolbarVisibilityButton(
            icon: Icons.admin_panel_settings_outlined,
            tooltip: '설정',
            onPressed: onOpenAdmin!,
          ),
        ),
      );
    }

    return Material(
      color: barColor ?? theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: _toMainAxisAlignment(align),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// WebView의 위젯 트리 위치를 유지하면서 툴바와 플로팅 컨트롤만 전환한다.
///
/// [hidden]이 바뀌어도 [webView]는 항상 첫 번째 `Positioned`의 자식으로 남으므로
/// 네이티브 WebView가 dispose/recreate되지 않는다.
class ToolbarHost extends StatefulWidget {
  final bool hidden;
  final NavPosition position;
  final double sideWidth;
  final double toolbarHeight;
  final Duration autoHideDuration;
  final VoidCallback? onAutoHide;
  final Widget webView;
  final Widget toolbar;
  final Widget overlay;

  const ToolbarHost({
    super.key,
    required this.hidden,
    this.position = NavPosition.bottom,
    this.sideWidth = 220,
    required this.toolbarHeight,
    this.autoHideDuration = Duration.zero,
    this.onAutoHide,
    required this.webView,
    required this.toolbar,
    required this.overlay,
  });

  @override
  State<ToolbarHost> createState() => _ToolbarHostState();
}

class _ToolbarHostState extends State<ToolbarHost> {
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _resetAutoHideTimer();
  }

  @override
  void didUpdateWidget(covariant ToolbarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden ||
        oldWidget.autoHideDuration != widget.autoHideDuration ||
        oldWidget.onAutoHide != widget.onAutoHide) {
      _resetAutoHideTimer();
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    if (widget.hidden ||
        widget.autoHideDuration <= Duration.zero ||
        widget.onAutoHide == null) {
      return;
    }
    _autoHideTimer = Timer(widget.autoHideDuration, () {
      if (!mounted || widget.hidden) return;
      widget.onAutoHide?.call();
    });
  }

  void _onUserActivity() {
    if (!widget.hidden) _resetAutoHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position == NavPosition.auto
        ? NavPosition.bottom
        : widget.position;
    final toolbarVisible = !widget.hidden;
    final leftInset = toolbarVisible && position == NavPosition.left
        ? widget.sideWidth + 1
        : 0.0;
    final rightInset = toolbarVisible && position == NavPosition.right
        ? widget.sideWidth + 1
        : 0.0;
    final topInset = toolbarVisible && position == NavPosition.top
        ? widget.toolbarHeight + 1
        : 0.0;
    final bottomInset = toolbarVisible && position == NavPosition.bottom
        ? widget.toolbarHeight + 1
        : 0.0;

    final toolbarWithDivider = switch (position) {
      NavPosition.left => Row(
          mainAxisSize: MainAxisSize.min,
          children: [widget.toolbar, const VerticalDivider(width: 1)],
        ),
      NavPosition.right => Row(
          mainAxisSize: MainAxisSize.min,
          children: [const VerticalDivider(width: 1), widget.toolbar],
        ),
      NavPosition.top => Column(
          mainAxisSize: MainAxisSize.min,
          children: [widget.toolbar, const Divider(height: 1)],
        ),
      NavPosition.bottom || NavPosition.auto => Column(
          mainAxisSize: MainAxisSize.min,
          children: [const Divider(height: 1), widget.toolbar],
        ),
    };

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      onPointerMove: (_) => _onUserActivity(),
      onPointerSignal: (_) => _onUserActivity(),
      child: Stack(
        children: [
          Positioned.fill(
            left: leftInset,
            right: rightInset,
            top: topInset,
            bottom: bottomInset,
            child: widget.webView,
          ),
          Positioned(
            left: position == NavPosition.right ? null : 0,
            right: position == NavPosition.left ? null : 0,
            top: position == NavPosition.bottom ? null : 0,
            bottom: position == NavPosition.top ? null : 0,
            child: Offstage(
              offstage: widget.hidden,
              child: toolbarWithDivider,
            ),
          ),
          Positioned.fill(
            child: Offstage(
              offstage: !widget.hidden,
              child: widget.overlay,
            ),
          ),
        ],
      ),
    );
  }
}

/// 툴바가 감추어진 동안 WebView 위에 남는 최소 플로팅 컨트롤.
///
/// 메뉴 버튼은 숨기되 탐색, 툴바 복원, 가상 키보드 제어는 언제든 가능하다.
class CollapsedToolbarOverlay extends StatefulWidget {
  final KioskWebViewController? historyController;
  final VoidCallback onShowToolbar;

  const CollapsedToolbarOverlay({
    super.key,
    required this.historyController,
    required this.onShowToolbar,
  });

  @override
  State<CollapsedToolbarOverlay> createState() =>
      _CollapsedToolbarOverlayState();
}

enum _OverlayCorner { topLeft, topRight, bottomLeft, bottomRight }

class _CollapsedToolbarOverlayState extends State<CollapsedToolbarOverlay> {
  static const double _margin = 16;
  static const double _controlWidth = 264;
  static const double _controlHeight = 72;

  _OverlayCorner _corner = _OverlayCorner.bottomRight;
  Offset? _dragPosition;

  Offset _cornerPosition(_OverlayCorner corner, Size size) {
    final right = (size.width - _controlWidth - _margin).clamp(
      _margin,
      double.infinity,
    );
    final bottom = (size.height - _controlHeight - _margin).clamp(
      _margin,
      double.infinity,
    );
    return switch (corner) {
      _OverlayCorner.topLeft => const Offset(_margin, _margin),
      _OverlayCorner.topRight => Offset(right, _margin),
      _OverlayCorner.bottomLeft => Offset(_margin, bottom),
      _OverlayCorner.bottomRight => Offset(right, bottom),
    };
  }

  Offset _clampPosition(Offset position, Size size) {
    final maxX = (size.width - _controlWidth - _margin).clamp(
      _margin,
      double.infinity,
    );
    final maxY = (size.height - _controlHeight - _margin).clamp(
      _margin,
      double.infinity,
    );
    return Offset(
      position.dx.clamp(_margin, maxX),
      position.dy.clamp(_margin, maxY),
    );
  }

  void _finishDrag(Size size) {
    final position = _dragPosition ?? _cornerPosition(_corner, size);
    final center = position +
        const Offset(
          _controlWidth / 2,
          _controlHeight / 2,
        );
    final horizontalLeft = center.dx < size.width / 2;
    final verticalTop = center.dy < size.height / 2;
    setState(() {
      _corner = switch ((horizontalLeft, verticalTop)) {
        (true, true) => _OverlayCorner.topLeft,
        (false, true) => _OverlayCorner.topRight,
        (true, false) => _OverlayCorner.bottomLeft,
        (false, false) => _OverlayCorner.bottomRight,
      };
      _dragPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget buildControls(WebNavState state) {
      return Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        elevation: 10,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HistoryButton(
                icon: Icons.arrow_back,
                tooltip: '뒤로',
                enabled: state.canGoBack,
                onPressed: () => widget.historyController?.goBack(),
              ),
              const SizedBox(width: 8),
              _HistoryButton(
                icon: Icons.arrow_forward,
                tooltip: '앞으로',
                enabled: state.canGoForward,
                onPressed: () => widget.historyController?.goForward(),
              ),
              const SizedBox(width: 8),
              _ToolbarVisibilityButton(
                icon: Icons.visibility_outlined,
                tooltip: '툴바 보이기',
                onPressed: widget.onShowToolbar,
              ),
              const SizedBox(width: 8),
              const _KeyboardToggle(
                orientation: NavigationOrientation.bottom,
              ),
            ],
          ),
        ),
      );
    }

    final controller = widget.historyController;
    final controls = controller == null
        ? buildControls(WebNavState.empty)
        : ValueListenableBuilder<WebNavState>(
            valueListenable: controller.navState,
            builder: (context, state, _) => buildControls(state),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final position = _clampPosition(
          _dragPosition ?? _cornerPosition(_corner, size),
          size,
        );
        return Stack(
          children: [
            AnimatedPositioned(
              duration: _dragPosition == null
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              curve: Curves.easeOut,
              left: position.dx,
              top: position.dy,
              width: _controlWidth,
              height: _controlHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) {
                  setState(() => _dragPosition = position);
                },
                onPanUpdate: (details) {
                  setState(() {
                    _dragPosition = _clampPosition(
                      (_dragPosition ?? position) + details.delta,
                      size,
                    );
                  });
                },
                onPanEnd: (_) => _finishDrag(size),
                onPanCancel: () => _finishDrag(size),
                child: controls,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ToolbarVisibilityButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final VoidCallback? onDoublePressed;

  const _ToolbarVisibilityButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onDoublePressed,
  });

  @override
  State<_ToolbarVisibilityButton> createState() =>
      _ToolbarVisibilityButtonState();
}

class _ToolbarVisibilityButtonState extends State<_ToolbarVisibilityButton> {
  Timer? _tapTimer;

  void _handlePressed() {
    final onDoublePressed = widget.onDoublePressed;
    if (onDoublePressed == null) {
      widget.onPressed();
      return;
    }
    if (_tapTimer?.isActive ?? false) {
      _tapTimer!.cancel();
      _tapTimer = null;
      onDoublePressed();
      return;
    }
    _tapTimer = Timer(const Duration(milliseconds: 300), () {
      _tapTimer = null;
      if (mounted) widget.onPressed();
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Tooltip(
        message: widget.tooltip,
        child: ElevatedButton(
          onPressed: _handlePressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            overlayColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            animationDuration: Duration.zero,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Icon(widget.icon, size: 30),
        ),
      ),
    );
  }
}

MainAxisAlignment _toMainAxisAlignment(NavAlignment a) {
  switch (a) {
    case NavAlignment.start:
      return MainAxisAlignment.start;
    case NavAlignment.center:
      return MainAxisAlignment.center;
    case NavAlignment.end:
      return MainAxisAlignment.end;
    case NavAlignment.spaceBetween:
      return MainAxisAlignment.spaceBetween;
    case NavAlignment.spaceAround:
      return MainAxisAlignment.spaceAround;
    case NavAlignment.spaceEvenly:
      return MainAxisAlignment.spaceEvenly;
    case NavAlignment.stretch:
      // Column/Row의 MainAxisAlignment에는 stretch가 없으므로 start로 대체.
      return MainAxisAlignment.start;
  }
}

bool _isSpaceAlignment(NavAlignment a) =>
    a == NavAlignment.spaceBetween ||
    a == NavAlignment.spaceAround ||
    a == NavAlignment.spaceEvenly;

/// WebView 뒤로/앞으로 이동 컨트롤.
///
/// [KioskWebViewController.navState] 를 구독해 활성/비활성 상태를 자동 갱신.
class _HistoryControls extends StatelessWidget {
  final KioskWebViewController controller;
  final NavigationOrientation orientation;

  const _HistoryControls({
    required this.controller,
    required this.orientation,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WebNavState>(
      valueListenable: controller.navState,
      builder: (context, state, _) {
        final back = _HistoryButton(
          icon: Icons.arrow_back,
          tooltip: '뒤로',
          enabled: state.canGoBack,
          onPressed: () => controller.goBack(),
        );
        final forward = _HistoryButton(
          icon: Icons.arrow_forward,
          tooltip: '앞으로',
          enabled: state.canGoForward,
          onPressed: () => controller.goForward(),
        );
        // 사이드/하단 모두 가로로 두 버튼을 나란히 배치.
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            back,
            const SizedBox(width: 8),
            forward,
          ],
        );
      },
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _HistoryButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: Tooltip(
        message: tooltip,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            disabledBackgroundColor: scheme.surface.withValues(alpha: 0.5),
            disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.35),
            elevation: enabled ? 1 : 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Icon(icon, size: 28),
        ),
      ),
    );
  }
}

/// OS 가상 키보드 호출/닫기 토글 버튼.
///
/// 키보드의 실제 표시 상태를 OS 로부터 알 수 없으므로 내부적으로 토글 상태를
/// 추적한다. 사용자가 직접 키보드를 닫더라도 다시 누르면 다시 호출된다.
class _KeyboardToggle extends StatefulWidget {
  final NavigationOrientation orientation;

  const _KeyboardToggle({required this.orientation});

  @override
  State<_KeyboardToggle> createState() => _KeyboardToggleState();
}

class _KeyboardToggleState extends State<_KeyboardToggle> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: ValueListenableBuilder<bool>(
        valueListenable: KeyboardController.instance.visible,
        builder: (context, shown, _) {
          return Tooltip(
            message: shown ? '키보드 닫기' : '키보드 열기',
            child: ElevatedButton(
              onPressed: () {
                if (shown) {
                  SystemKeyboard.hide();
                } else {
                  SystemKeyboard.show();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: shown ? scheme.primary : scheme.surface,
                foregroundColor: shown ? scheme.onPrimary : scheme.onSurface,
                elevation: 1,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Icon(
                shown ? Icons.keyboard_hide : Icons.keyboard,
                size: 28,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 사이드/하단 양쪽에서 공용으로 사용하는 큰 터치 버튼.
class _NavButton extends StatelessWidget {
  final String title;
  final String? iconPath;
  final bool showTitle;
  final bool selected;
  final NavigationOrientation orientation;

  /// 외부에서 지정하는 고정 높이. `null`이면 아이콘/텍스트 유무에 따라 자동 결정.
  final double? fixedHeight;

  /// 색상 오버라이드(테마 기본값 대신 쓸 값). `null`이면 테마 사용.
  final Color? buttonColor;
  final Color? buttonForegroundColor;
  final Color? selectedButtonColor;
  final Color? selectedButtonForegroundColor;

  final VoidCallback onPressed;

  const _NavButton({
    required this.title,
    required this.iconPath,
    required this.showTitle,
    required this.selected,
    required this.orientation,
    required this.onPressed,
    this.fixedHeight,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 선택 상태에 따른 색 결정 (설정 > 테마).
    final background = selected
        ? (selectedButtonColor ?? scheme.primary)
        : (buttonColor ?? scheme.surface);
    final foreground = selected
        ? (selectedButtonForegroundColor ?? scheme.onPrimary)
        : (buttonForegroundColor ?? scheme.onSurface);

    final hasIcon = iconPath != null && iconPath!.isNotEmpty;
    // 아이콘 없으면 텍스트는 무조건 보여줘야 빈 버튼이 안 된다.
    final showLabel = showTitle || !hasIcon;
    final iconOnly = hasIcon && !showLabel;

    // 외부 고정 높이가 있으면 그 값 사용, 아니면 자동.
    final height = fixedHeight ?? (iconOnly ? 80.0 : (hasIcon ? 88.0 : 72.0));

    final button = SizedBox(
      // 터치 사이니지를 위한 큰 버튼 (최소 64dp 이상).
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          // 큰 터치 버튼의 기본 splash/highlight와 elevation 전환은 사이니지
          // 화면에서 메뉴바 전체가 번쩍이는 것처럼 보일 수 있어 제거한다.
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          animationDuration: Duration.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        child: _buildContent(foreground, hasIcon, showLabel),
      ),
    );

    // 아이콘만 있는 경우 title을 툴팁/시맨틱 레이블로 노출(접근성).
    if (iconOnly) {
      return Tooltip(
        message: title,
        child: button,
      );
    }
    return button;
  }

  Widget _buildContent(Color foreground, bool hasIcon, bool showLabel) {
    final label = _AutoSizeTwoLineText(title: title);

    if (!hasIcon) {
      // 아이콘 없음 → 텍스트만
      return label;
    }

    final icon = _IconImage(path: iconPath!, color: foreground);

    if (!showLabel) {
      // 아이콘만 표시(텍스트 숨김) — 영역을 충분히 채우도록 한다.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: icon,
      );
    }

    // 아이콘 + 텍스트
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 30, child: icon),
        const SizedBox(height: 4),
        Flexible(child: label),
      ],
    );
  }
}

class _AutoSizeTwoLineText extends StatelessWidget {
  final String title;

  const _AutoSizeTwoLineText({required this.title});

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        var fontSize = inherited.fontSize ?? 18;
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : double.infinity;
        while (fontSize > 12) {
          final painter = TextPainter(
            text: TextSpan(
              text: title,
              style: inherited.copyWith(fontSize: fontSize, height: 1.05),
            ),
            maxLines: 2,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: maxWidth);
          if (!painter.didExceedMaxLines && painter.height <= maxHeight) break;
          fontSize -= 1;
        }
        return Text(
          title,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: inherited.copyWith(fontSize: fontSize, height: 1.05),
        );
      },
    );
  }
}

/// 메뉴 아이콘 이미지.
///
/// - `icon:<name>` (예: `icon:home`) 이면 Material 아이콘을 사용한다.
///   사용 가능한 이름은 [MaterialIconRegistry] 참조.
/// - `http(s)://` 로 시작하면 네트워크 이미지로 로드한다.
/// - 그 외에는 Flutter 에셋 경로로 간주한다.
/// - 로드 실패 시 기본 아이콘으로 대체한다.
class _IconImage extends StatelessWidget {
  final String path;
  final Color color;

  const _IconImage({required this.path, required this.color});

  @override
  Widget build(BuildContext context) {
    // 1) Material 아이콘: "icon:home" 형식.
    if (path.startsWith('icon:')) {
      final key = path.substring(5);
      final data = MaterialIconRegistry.lookup(key);
      if (data != null) {
        return FittedBox(
          fit: BoxFit.contain,
          child: Icon(data, color: color),
        );
      }
      // 등록 안 된 이름 → 기본 아이콘.
      return Icon(Icons.help_outline, color: color, size: 32);
    }

    // 2) 네트워크 이미지.
    final isNetwork = path.startsWith('http://') || path.startsWith('https://');
    final fallback = Icon(Icons.broken_image, color: color, size: 32);

    if (isNetwork) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    // 3) 에셋 이미지.
    return Image.asset(
      path,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
