import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WebView가 포커스를 가진 상태에서도 키오스크 전역 기능키를 처리한다.
class KioskShortcuts extends StatefulWidget {
  final Widget child;
  final VoidCallback onShowVersion;
  final VoidCallback onCheckUpdate;

  const KioskShortcuts({
    super.key,
    required this.child,
    required this.onShowVersion,
    required this.onCheckUpdate,
  });

  @override
  State<KioskShortcuts> createState() => _KioskShortcutsState();
}

class _KioskShortcutsState extends State<KioskShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.f12) {
      widget.onShowVersion();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f9) {
      widget.onCheckUpdate();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
