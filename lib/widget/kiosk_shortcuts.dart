import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WebView가 포커스를 가진 상태에서도 사이니지 전역 기능키를 처리한다.
class KioskShortcuts extends StatefulWidget {
  final Widget child;
  final VoidCallback onShowManual;
  final VoidCallback onShowVersion;
  final VoidCallback onCheckUpdate;

  const KioskShortcuts({
    super.key,
    required this.child,
    required this.onShowManual,
    required this.onShowVersion,
    required this.onCheckUpdate,
  });

  @override
  State<KioskShortcuts> createState() => _KioskShortcutsState();
}

class _KioskShortcutsState extends State<KioskShortcuts> {
  static const _nativeChannel = MethodChannel('simple_kiosk/shortcuts');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _nativeChannel.setMethodCallHandler(_handleNativeShortcut);
  }

  @override
  void dispose() {
    _nativeChannel.setMethodCallHandler(null);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  Future<void> _handleNativeShortcut(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'showManual':
        widget.onShowManual();
        return;
      case 'showVersion':
        widget.onShowVersion();
        return;
      case 'checkUpdate':
        widget.onCheckUpdate();
        return;
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      widget.onShowManual();
      return true;
    }
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
