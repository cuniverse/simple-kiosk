import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/layout_config.dart';
import '../model/menu_item.dart';
import '../service/keyboard_controller.dart';
import '../service/font_resource_service.dart';
import '../service/system_keyboard.dart';
import 'kiosk_webview.dart';
import 'icon_path_candidates.dart';
import 'material_icon_registry.dart';
import 'platform_file_image.dart';
import 'version_overlay.dart';

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

  /// 항목별 재정의가 없을 때 메뉴 아이콘을 기본적으로 감출지 여부.
  final bool hideItemIcons;

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

  /// 현재 선택된 주제 이름. `null`이면 상태 라벨을 표시하지 않는다.
  final String? selectedTopicLabel;

  /// 현재 선택된 주제 라벨의 글자색.
  final Color selectedTopicLabelColor;

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

  /// 툴바 메뉴 버튼 전체 글꼴. 항목별 글꼴이 있으면 그 값이 우선한다.
  final String? fontFamily;

  /// 툴바를 감추는 콜백. `null`이면 숨김 버튼을 표시하지 않는다.
  final VoidCallback? onHide;

  /// 화면 보호기로 즉시 진입하는 콜백. `null`이면 버튼을 표시하지 않는다.
  final VoidCallback? onEnterIdle;

  /// PIN 보호된 설정 화면을 여는 콜백.
  final VoidCallback? onOpenAdmin;

  /// 언어 선택 화면으로 돌아가는 콜백.
  final VoidCallback? onSelectLanguage;

  /// 화면 보호기 더블클릭으로 사이니지 감추기 순서를 시작하는 콜백.
  final VoidCallback? onPrepareHideKiosk;

  /// 사이드 툴바의 하단 기능 버튼 아래에 표시할 앱 버전.
  final String? versionLabel;

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
    this.hideItemIcons = false,
    this.buttonAlignment = NavAlignment.stretch,
    this.showHistoryButtons = false,
    this.historyController,
    this.showKeyboardToggle = false,
    this.selectedTopicLabel,
    this.selectedTopicLabelColor = const Color(0xFFF8FAFC),
    this.barColor,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
    this.fontFamily,
    this.onHide,
    this.onEnterIdle,
    this.onOpenAdmin,
    this.onSelectLanguage,
    this.onPrepareHideKiosk,
    this.onHideKiosk,
    this.versionLabel,
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
    final align = buttonAlignment == NavAlignment.stretch
        ? NavAlignment.start
        : buttonAlignment;
    final mainAxisAlign = _toMainAxisAlignment(align);
    final useSeparator = !_isSpaceAlignment(align);
    final actionCount = (showHistoryButtons ? 2 : 0) +
        [
          showKeyboardToggle,
          onOpenAdmin != null,
          onEnterIdle != null,
          onHide != null,
        ].where((visible) => visible).length;

    return Material(
      color: barColor ?? theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: sideWidth,
          // 키보드 토글이 활성화되면 항상 맨 아래 고정으로 두기 위해
          // 메뉴 영역(스크롤) + 하단 푸터(고정) 구조로 나눈다.
          child: Stack(
            children: [
              Column(
                children: [
                  if (onSelectLanguage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                      child: _LanguageSelectionBackButton(
                        orientation: NavigationOrientation.side,
                        onPressed: onSelectLanguage!,
                      ),
                    ),
                  if (selectedTopicLabel != null)
                    _SelectedTopicLabel(
                      label: selectedTopicLabel!,
                      orientation: NavigationOrientation.side,
                      color: selectedTopicLabelColor,
                      fontFamily: fontFamily,
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const verticalPadding = 24.0;
                        const minimumButtonHeight = 56.0;
                        const automaticButtonHeight = 88.0;
                        final available =
                            (constraints.maxHeight - verticalPadding)
                                .clamp(0.0, double.infinity);
                        final gapCount = useSeparator
                            ? (items.length - 1).clamp(0, items.length)
                            : 0;
                        final gaps = gapCount * buttonGap;
                        final preferred = buttonHeight > 0
                            ? buttonHeight
                            : automaticButtonHeight;
                        final fitted = items.isEmpty
                            ? preferred
                            : ((available - gaps) / items.length)
                                .clamp(minimumButtonHeight, preferred);
                        final overflow =
                            items.length * minimumButtonHeight + gaps >
                                available;

                        Widget menuColumn(double height) {
                          final children = <Widget>[];
                          for (var i = 0; i < items.length; i++) {
                            if (useSeparator && i > 0) {
                              children.add(SizedBox(height: buttonGap));
                            }
                            children.add(
                              _NavButton(
                                title: items[i].title,
                                iconPath: items[i].icon,
                                selectedIconPath: items[i].selectedIcon,
                                showIcon: items[i].showIcon ?? !hideItemIcons,
                                showTitle: items[i].showTitle,
                                selected: i == selectedIndex,
                                orientation: NavigationOrientation.side,
                                fixedHeight: height,
                                buttonColor: buttonColor,
                                buttonForegroundColor: buttonForegroundColor,
                                selectedButtonColor: selectedButtonColor,
                                selectedButtonForegroundColor:
                                    selectedButtonForegroundColor,
                                fontFamily: FontResourceService.familyFor(
                                      items[i].fontFamily,
                                    ) ??
                                    fontFamily,
                                onPressed: () => onSelected(i),
                              ),
                            );
                          }
                          return Column(
                            mainAxisAlignment: mainAxisAlign,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          );
                        }

                        final content = Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          child: menuColumn(
                            overflow ? minimumButtonHeight : fitted,
                          ),
                        );
                        if (!overflow) return content;
                        return _ExplicitScrollViewport(
                          axis: Axis.vertical,
                          child: content,
                        );
                      },
                    ),
                  ),
                  if (showHistoryButtons ||
                      showKeyboardToggle ||
                      onEnterIdle != null ||
                      onOpenAdmin != null ||
                      onHide != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        4,
                        8,
                        versionLabel == null ? 12 : 22,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final metrics = _sideActionMetrics(
                            constraints.maxWidth,
                            actionCount,
                            buttonGap,
                          );
                          return Center(
                            child: SizedBox(
                              width: metrics.rowWidth,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: metrics.gap,
                                runSpacing: metrics.gap,
                                children: [
                                  if (showHistoryButtons)
                                    _HistoryControls(
                                      controller: historyController,
                                      orientation: NavigationOrientation.side,
                                      buttonSize: metrics.size,
                                      gap: metrics.gap,
                                    ),
                                  if (showKeyboardToggle)
                                    _KeyboardToggle(size: metrics.size),
                                  if (onOpenAdmin != null)
                                    _ToolbarVisibilityButton(
                                      icon: Icons.admin_panel_settings_outlined,
                                      tooltip: '설정',
                                      size: metrics.size,
                                      onPressed: onOpenAdmin!,
                                    ),
                                  if (onEnterIdle != null)
                                    _ToolbarVisibilityButton(
                                      icon: Icons.wallpaper_outlined,
                                      tooltip: '화면 보호기 시작',
                                      size: metrics.size,
                                      onPressed: onEnterIdle!,
                                      onDoublePressed: onPrepareHideKiosk,
                                    ),
                                  if (onHide != null)
                                    _ToolbarVisibilityButton(
                                      icon: Icons.visibility_off_outlined,
                                      tooltip: '툴바 감추기',
                                      size: metrics.size,
                                      onPressed: onHide!,
                                      onDoublePressed: onHideKiosk,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              if (versionLabel != null)
                Positioned(
                  right: 8,
                  bottom: 4,
                  child: VersionOverlay(version: versionLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    final theme = Theme.of(context);
    final align = buttonAlignment;
    final actionCount = (showHistoryButtons ? 2 : 0) +
        [
          showKeyboardToggle,
          onHide != null,
          onEnterIdle != null,
          onOpenAdmin != null,
        ].where((visible) => visible).length;
    final actionMetrics = _horizontalActionMetrics(
      MediaQuery.sizeOf(context).width,
      barHeight,
      actionCount,
      buttonGap,
    );
    final controls = <Widget>[];
    void addControl(Widget control) {
      if (controls.isNotEmpty) {
        controls.add(SizedBox(width: actionMetrics.gap));
      }
      controls.add(control);
    }

    if (showHistoryButtons) {
      addControl(
        _HistoryControls(
          controller: historyController,
          orientation: NavigationOrientation.bottom,
          buttonSize: actionMetrics.size,
          gap: actionMetrics.gap,
        ),
      );
    }
    if (showKeyboardToggle) {
      addControl(
        _KeyboardToggle(size: actionMetrics.size),
      );
    }
    if (onHide != null) {
      addControl(
        _ToolbarVisibilityButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: '툴바 감추기',
          size: actionMetrics.size,
          onPressed: onHide!,
          onDoublePressed: onHideKiosk,
        ),
      );
    }
    if (onEnterIdle != null) {
      addControl(
        _ToolbarVisibilityButton(
          icon: Icons.wallpaper_outlined,
          tooltip: '화면 보호기 시작',
          size: actionMetrics.size,
          onPressed: onEnterIdle!,
          onDoublePressed: onPrepareHideKiosk,
        ),
      );
    }
    if (onOpenAdmin != null) {
      addControl(
        _ToolbarVisibilityButton(
          icon: Icons.admin_panel_settings_outlined,
          tooltip: '설정',
          size: actionMetrics.size,
          onPressed: onOpenAdmin!,
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
              children: [
                if (onSelectLanguage != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _LanguageSelectionBackButton(
                      orientation: NavigationOrientation.bottom,
                      onPressed: onSelectLanguage!,
                    ),
                  ),
                  SizedBox(width: buttonGap),
                ],
                if (selectedTopicLabel != null) ...[
                  _SelectedTopicLabel(
                    label: selectedTopicLabel!,
                    orientation: NavigationOrientation.bottom,
                    color: selectedTopicLabelColor,
                    fontFamily: fontFamily,
                  ),
                  SizedBox(width: buttonGap),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const minimumWidth = 72.0;
                      const preferredWidth = 120.0;
                      final gaps =
                          (items.length - 1).clamp(0, items.length) * buttonGap;
                      final requested =
                          buttonWidth > 0 ? buttonWidth : preferredWidth;
                      final fitted = items.isEmpty
                          ? requested
                          : ((constraints.maxWidth - gaps) / items.length)
                              .clamp(minimumWidth, requested);
                      final overflow = items.length * minimumWidth + gaps >
                          constraints.maxWidth;
                      final width = overflow ? preferredWidth : fitted;
                      final menuButtons = <Widget>[];
                      for (var i = 0; i < items.length; i++) {
                        if (i > 0) {
                          menuButtons.add(SizedBox(width: buttonGap));
                        }
                        menuButtons.add(
                          SizedBox(
                            width: width,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: _NavButton(
                                title: items[i].title,
                                iconPath: items[i].icon,
                                selectedIconPath: items[i].selectedIcon,
                                showIcon: items[i].showIcon ?? !hideItemIcons,
                                showTitle: items[i].showTitle,
                                selected: i == selectedIndex,
                                orientation: NavigationOrientation.bottom,
                                fixedHeight: buttonHeight > 0
                                    ? buttonHeight
                                    : barHeight - 16,
                                buttonColor: buttonColor,
                                buttonForegroundColor: buttonForegroundColor,
                                selectedButtonColor: selectedButtonColor,
                                selectedButtonForegroundColor:
                                    selectedButtonForegroundColor,
                                fontFamily: FontResourceService.familyFor(
                                      items[i].fontFamily,
                                    ) ??
                                    fontFamily,
                                onPressed: () => onSelected(i),
                              ),
                            ),
                          ),
                        );
                      }
                      final row = Row(
                        mainAxisSize:
                            overflow ? MainAxisSize.min : MainAxisSize.max,
                        mainAxisAlignment: overflow
                            ? MainAxisAlignment.start
                            : _toMainAxisAlignment(align),
                        children: menuButtons,
                      );
                      return overflow
                          ? _ExplicitScrollViewport(
                              axis: Axis.horizontal,
                              child: row,
                            )
                          : row;
                    },
                  ),
                ),
                if (controls.isNotEmpty) ...[
                  SizedBox(width: buttonGap),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: controls,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 메뉴 버튼과 혼동되지 않는 읽기 전용 현재 주제 라벨.
class _SelectedTopicLabel extends StatelessWidget {
  final String label;
  final NavigationOrientation orientation;
  final Color color;
  final String? fontFamily;

  const _SelectedTopicLabel({
    required this.label,
    required this.orientation,
    required this.color,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final side = orientation == NavigationOrientation.side;
    final content = Row(
      mainAxisSize: side ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 24,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            key: const ValueKey('selected-topic-label'),
            maxLines: side ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: side ? 14 : 13,
              fontWeight: FontWeight.w600,
              fontFamily: fontFamily,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      label: '현재 주제: $label',
      child: Tooltip(
        message: '현재 주제: $label',
        child: side
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SizedBox(height: 36, child: content),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: content,
                ),
              ),
      ),
    );
  }
}

/// 공간이 실제로 부족할 때만 명시적인 스크롤바와 스크롤 동작을 제공한다.
class _ExplicitScrollViewport extends StatefulWidget {
  final Axis axis;
  final Widget child;

  const _ExplicitScrollViewport({required this.axis, required this.child});

  @override
  State<_ExplicitScrollViewport> createState() =>
      _ExplicitScrollViewportState();
}

class _ExplicitScrollViewportState extends State<_ExplicitScrollViewport> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: widget.axis,
        child: widget.child,
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
  final String? versionLabel;

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
    this.versionLabel,
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
    final isSide =
        position == NavPosition.left || position == NavPosition.right;

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
              child: RepaintBoundary(
                key: const ValueKey('persistent-toolbar-layer'),
                child: toolbarWithDivider,
              ),
            ),
          ),
          Positioned.fill(
            child: Offstage(
              offstage: !widget.hidden,
              child: widget.overlay,
            ),
          ),
          if (widget.versionLabel != null && (!toolbarVisible || !isSide))
            Positioned(
              right: 12,
              bottom: toolbarVisible && position == NavPosition.bottom
                  ? bottomInset + 8
                  : 8,
              child: VersionOverlay(version: widget.versionLabel!),
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
              const _KeyboardToggle(size: 56),
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

class _LanguageSelectionBackButton extends StatelessWidget {
  final NavigationOrientation orientation;
  final VoidCallback onPressed;

  const _LanguageSelectionBackButton({
    required this.orientation,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = orientation == NavigationOrientation.side;
    return SizedBox(
      key: const ValueKey('language-selection-back-button'),
      width: side ? double.infinity : 108,
      height: 56,
      child: Tooltip(
        message: '언어 선택으로 돌아가기',
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primaryContainer.withValues(alpha: 0.82),
            foregroundColor: scheme.onPrimaryContainer,
            elevation: 0,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: side ? 16 : 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: scheme.primary.withValues(alpha: 0.22),
              ),
            ),
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 24),
          label: Text(
            side ? '언어 선택으로 돌아가기' : '언어 선택',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: side ? 14 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionMetrics {
  final double size;
  final double gap;
  final int columns;

  const _ActionMetrics(this.size, this.gap, this.columns);

  double get rowWidth => size * columns + gap * (columns - 1);
}

_ActionMetrics _sideActionMetrics(
  double availableWidth,
  int count,
  double requestedGap,
) {
  if (count <= 0 || !availableWidth.isFinite) {
    return const _ActionMetrics(56, 8, 1);
  }
  const minimumSize = 40.0;
  final gap = requestedGap.clamp(2.0, count >= 5 ? 4.0 : 10.0);
  final singleRowSize = (availableWidth - gap * (count - 1)) / count;
  final maximumColumns =
      ((availableWidth + gap) / (minimumSize + gap)).floor().clamp(1, count);
  final columns = singleRowSize >= minimumSize
      ? count
      : (count / (count / maximumColumns).ceil()).ceil();
  final fitted = (availableWidth - gap * (columns - 1)) / columns;
  return _ActionMetrics(fitted.clamp(minimumSize, 60.0), gap, columns);
}

_ActionMetrics _horizontalActionMetrics(
  double toolbarWidth,
  double toolbarHeight,
  int count,
  double requestedGap,
) {
  if (count <= 0) return const _ActionMetrics(56, 8, 1);
  final gap = requestedGap.clamp(4.0, count >= 4 ? 7.0 : 10.0);
  final heightLimit = (toolbarHeight - 16).clamp(40.0, 60.0);
  final widthBudget = (toolbarWidth * 0.30).clamp(120.0, 280.0);
  final fitted = (widthBudget - gap * (count - 1)) / count;
  return _ActionMetrics(
    math.min(heightLimit, fitted.clamp(40.0, 60.0)),
    gap,
    count,
  );
}

class _ToolbarVisibilityButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback onPressed;
  final VoidCallback? onDoublePressed;

  const _ToolbarVisibilityButton({
    required this.icon,
    required this.tooltip,
    this.size = 56,
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
    final radius = (widget.size * 0.27).clamp(12.0, 16.0);
    final iconSize = (widget.size * 0.48).clamp(21.0, 29.0);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Tooltip(
        message: widget.tooltip,
        child: ElevatedButton(
          onPressed: _handlePressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.surface.withValues(alpha: 0.88),
            foregroundColor: scheme.onSurface,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            overlayColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            animationDuration: Duration.zero,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.72),
              ),
            ),
          ),
          child: Icon(widget.icon, size: iconSize),
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
  final KioskWebViewController? controller;
  final NavigationOrientation orientation;
  final double buttonSize;
  final double gap;

  const _HistoryControls({
    required this.controller,
    required this.orientation,
    this.buttonSize = 56,
    this.gap = 8,
  });

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return _buildButtons(WebNavState.empty, null);
    }
    return ValueListenableBuilder<WebNavState>(
      valueListenable: controller.navState,
      builder: (context, state, _) => _buildButtons(state, controller),
    );
  }

  Widget _buildButtons(
    WebNavState state,
    KioskWebViewController? controller,
  ) {
    final back = _HistoryButton(
      icon: Icons.arrow_back,
      tooltip: '뒤로',
      enabled: controller != null && state.canGoBack,
      size: buttonSize,
      onPressed: () => controller?.goBack(),
    );
    final forward = _HistoryButton(
      icon: Icons.arrow_forward,
      tooltip: '앞으로',
      enabled: controller != null && state.canGoForward,
      size: buttonSize,
      onPressed: () => controller?.goForward(),
    );
    // 컨트롤러 준비 전에도 같은 크기의 비활성 버튼을 유지해 메뉴가 움직이지 않는다.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        back,
        SizedBox(width: gap),
        forward,
      ],
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final double size;
  final VoidCallback onPressed;

  const _HistoryButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    this.size = 56,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = (size * 0.27).clamp(11.0, 15.0);
    final iconSize = (size * 0.50).clamp(21.0, 28.0);
    return SizedBox(
      width: size,
      height: size,
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
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.70),
              ),
            ),
          ),
          child: Icon(icon, size: iconSize),
        ),
      ),
    );
  }
}

/// OS 가상 키보드 호출/닫기 토글 버튼.
///
/// 실제 Windows 키보드 창 상태를 확인해 표시/감춤을 전환한다.
class _KeyboardToggle extends StatefulWidget {
  final double size;

  const _KeyboardToggle({this.size = 56});

  @override
  State<_KeyboardToggle> createState() => _KeyboardToggleState();
}

class _KeyboardToggleState extends State<_KeyboardToggle> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = (widget.size * 0.27).clamp(12.0, 16.0);
    final iconSize = (widget.size * 0.48).clamp(21.0, 29.0);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ValueListenableBuilder<bool>(
        valueListenable: KeyboardController.instance.visible,
        builder: (context, shown, _) {
          return Tooltip(
            message: shown ? '키보드 닫기' : '키보드 열기',
            child: ElevatedButton(
              onPressed: SystemKeyboard.toggle,
              style: ElevatedButton.styleFrom(
                backgroundColor: shown ? scheme.primary : scheme.surface,
                foregroundColor: shown ? scheme.onPrimary : scheme.onSurface,
                elevation: 1,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                  side: BorderSide(
                    color: shown
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.72),
                  ),
                ),
              ),
              child: Icon(
                shown ? Icons.keyboard_hide : Icons.keyboard,
                size: iconSize,
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
  final String? selectedIconPath;
  final bool showIcon;
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
  final String? fontFamily;

  final VoidCallback onPressed;

  const _NavButton({
    required this.title,
    required this.iconPath,
    required this.selectedIconPath,
    required this.showIcon,
    required this.showTitle,
    required this.selected,
    required this.orientation,
    required this.onPressed,
    this.fixedHeight,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 선택 상태에 따른 색 결정 (설정 > 테마).
    final background = selected
        ? (selectedButtonColor ?? scheme.primaryContainer)
        : (buttonColor ?? scheme.surface.withValues(alpha: 0.78));
    final foreground = selected
        ? (selectedButtonForegroundColor ?? scheme.onPrimaryContainer)
        : (buttonForegroundColor ?? scheme.onSurface);
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.62)
        : scheme.outlineVariant.withValues(alpha: 0.68);

    final effectiveIconPath = !showIcon
        ? null
        : selected && selectedIconPath?.isNotEmpty == true
            ? selectedIconPath
            : iconPath;
    final hasIcon = effectiveIconPath != null && effectiveIconPath.isNotEmpty;
    // 아이콘 없으면 텍스트는 무조건 보여줘야 빈 버튼이 안 된다.
    final showLabel = showTitle || !hasIcon;
    final iconOnly = hasIcon && !showLabel;

    // 외부 고정 높이가 있으면 그 값 사용, 아니면 자동.
    final height = fixedHeight ?? (iconOnly ? 80.0 : (hasIcon ? 88.0 : 72.0));

    final button = SizedBox(
      // 터치 사이니지를 위한 큰 버튼 (최소 64dp 이상).
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: background,
              foregroundColor: foreground,
              // 큰 터치 버튼의 기본 splash/highlight와 elevation 전환은 사이니지
              // 화면에서 메뉴바 전체가 번쩍이는 것처럼 보일 수 있어 제거한다.
              elevation: selected ? 1 : 0,
              shadowColor: scheme.shadow.withValues(alpha: 0.20),
              surfaceTintColor: Colors.transparent,
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              animationDuration: Duration.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: borderColor,
                  width: selected ? 1.5 : 1,
                ),
              ),
              textStyle: TextStyle(
                fontSize: 18,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontFamily: fontFamily,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: _buildContent(
              foreground,
              effectiveIconPath,
              hasIcon,
              showLabel,
            ),
          ),
          if (selected)
            Positioned(
              left: orientation == NavigationOrientation.side ? 4 : 18,
              right: orientation == NavigationOrientation.side ? null : 18,
              top: orientation == NavigationOrientation.side ? 14 : null,
              bottom: orientation == NavigationOrientation.side ? 14 : 4,
              width: orientation == NavigationOrientation.side ? 4 : null,
              height: orientation == NavigationOrientation.side ? null : 4,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('selected-navigation-indicator'),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
        ],
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

  Widget _buildContent(
    Color foreground,
    String? effectiveIconPath,
    bool hasIcon,
    bool showLabel,
  ) {
    final label = _AutoSizeTwoLineText(
      title: title,
      maxFontSize: hasIcon
          ? 18
          : orientation == NavigationOrientation.side
              ? 28
              : 24,
    );

    if (!hasIcon) {
      // 아이콘 없음 → 텍스트만
      return label;
    }

    final icon = _IconImage(path: effectiveIconPath!, color: foreground);

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
  final double maxFontSize;

  const _AutoSizeTwoLineText({
    required this.title,
    this.maxFontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        var fontSize = maxFontSize;
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

    final candidates = buildIconPathCandidates(
      path,
      Theme.of(context).brightness,
    );
    return _buildLocalImage(candidates, 0, fallback);
  }

  Widget _buildLocalImage(
    List<String> candidates,
    int index,
    Widget fallback,
  ) {
    if (index >= candidates.length) return fallback;
    final candidate = candidates[index];
    Widget onError(Object _, StackTrace? __) =>
        _buildLocalImage(candidates, index + 1, fallback);

    // 3) 데이터 루트의 외부 파일 이미지.
    if (_isAbsoluteFilePath(candidate)) {
      return PlatformFileImage(
        path: candidate,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            onError(error, stackTrace),
      );
    }

    // 4) 에셋 이미지.
    return Image.asset(
      candidate,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => onError(error, stackTrace),
    );
  }
}

bool _isAbsoluteFilePath(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
