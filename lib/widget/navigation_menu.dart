import 'package:flutter/material.dart';

import '../model/layout_config.dart';
import '../model/menu_item.dart';
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
          onPressed: () => onSelected(i),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: sideWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    final theme = Theme.of(context);
    // 하단 모드 기본은 stretch(Expanded로 균등 분배).
    final align = buttonAlignment;
    final useStretch =
        align == NavAlignment.stretch && buttonWidth <= 0;

    Widget buildButton(int i) => _NavButton(
          title: items[i].title,
          iconPath: items[i].icon,
          showTitle: items[i].showTitle,
          selected: i == selectedIndex,
          orientation: NavigationOrientation.bottom,
          fixedHeight: buttonHeight > 0 ? buttonHeight : null,
          onPressed: () => onSelected(i),
        );

    final children = <Widget>[];
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
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
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

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
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

/// 사이드/하단 양쪽에서 공용으로 사용하는 큰 터치 버튼.
class _NavButton extends StatelessWidget {
  final String title;
  final String? iconPath;
  final bool showTitle;
  final bool selected;
  final NavigationOrientation orientation;

  /// 외부에서 지정하는 고정 높이. `null`이면 아이콘/텍스트 유무에 따라 자동 결정.
  final double? fixedHeight;

  final VoidCallback onPressed;

  const _NavButton({
    required this.title,
    required this.iconPath,
    required this.showTitle,
    required this.selected,
    required this.orientation,
    required this.onPressed,
    this.fixedHeight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 선택 상태를 색상과 두께로 구분한다.
    final background =
        selected ? scheme.primary : scheme.surface;
    final foreground =
        selected ? scheme.onPrimary : scheme.onSurface;

    final hasIcon = iconPath != null && iconPath!.isNotEmpty;
    // 아이콘 없으면 텍스트는 무조건 보여줘야 빈 버튼이 안 된다.
    final showLabel = showTitle || !hasIcon;
    final iconOnly = hasIcon && !showLabel;

    // 외부 고정 높이가 있으면 그 값 사용, 아니면 자동.
    final height = fixedHeight ??
        (iconOnly ? 80.0 : (hasIcon ? 88.0 : 72.0));

    final button = SizedBox(
      // 터치 사이니지를 위한 큰 버튼 (최소 64dp 이상).
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: selected ? 4 : 1,
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
    final label = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );

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
        SizedBox(height: 36, child: icon),
        const SizedBox(height: 4),
        Flexible(child: label),
      ],
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
    final isNetwork =
        path.startsWith('http://') || path.startsWith('https://');
    final fallback = Icon(Icons.broken_image, color: color, size: 32);

    if (isNetwork) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    // 3) 에셋 이미지.
    return Image.asset(
      path,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
