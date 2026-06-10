import 'package:flutter/material.dart';

import '../model/menu_item.dart';

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

  const NavigationMenu({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.orientation,
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
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final selected = index == selectedIndex;
              return _NavButton(
                title: items[index].title,
                selected: selected,
                onPressed: () => onSelected(index),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _NavButton(
                      title: items[i].title,
                      selected: i == selectedIndex,
                      onPressed: () => onSelected(i),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 사이드/하단 양쪽에서 공용으로 사용하는 큰 터치 버튼.
class _NavButton extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onPressed;

  const _NavButton({
    required this.title,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 선택 상태를 색상과 두께로 구분한다.
    final background =
        selected ? scheme.primary : scheme.surface;
    final foreground =
        selected ? scheme.onPrimary : scheme.onSurface;

    return SizedBox(
      // 터치 사이니지를 위한 큰 버튼 (최소 64dp 이상).
      height: 72,
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
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
