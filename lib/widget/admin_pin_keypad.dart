import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 터치 사이니지에서 관리자 PIN을 입력하기 위한 숫자 키패드.
class AdminPinKeypad extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  final String labelText;
  final int maxLength;

  const AdminPinKeypad({
    super.key,
    required this.controller,
    this.onSubmitted,
    this.labelText = '관리자 PIN',
    this.maxLength = 12,
  });

  @override
  State<AdminPinKeypad> createState() => _AdminPinKeypadState();
}

class _AdminPinKeypadState extends State<AdminPinKeypad> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'admin-pin-keypad');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _append(String digit) {
    if (widget.controller.text.length >= widget.maxLength) return;
    widget.controller.text += digit;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    _focusNode.requestFocus();
  }

  void _backspace() {
    final value = widget.controller.text;
    if (value.isEmpty) return;
    widget.controller.text = value.substring(0, value.length - 1);
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    _focusNode.requestFocus();
  }

  void _clear() {
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null && RegExp(r'^\d$').hasMatch(character)) {
      _append(character);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onSubmitted?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _digitButton(String digit) => FilledButton.tonal(
        onPressed: () => _append(digit),
        child: Text(digit, style: const TextStyle(fontSize: 24)),
      );

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        behavior: HitTestBehavior.translucent,
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) => InputDecorator(
                  decoration: InputDecoration(
                    labelText: widget.labelText,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    counterText:
                        '${widget.controller.text.length}/${widget.maxLength}',
                  ),
                  child: Text(
                    '●' * widget.controller.text.length,
                    style: const TextStyle(fontSize: 24, letterSpacing: 5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: 1.65,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (var digit = 1; digit <= 9; digit++)
                    _digitButton('$digit'),
                  OutlinedButton(
                    onPressed: _clear,
                    child: const Text('전체 삭제'),
                  ),
                  _digitButton('0'),
                  IconButton.outlined(
                    tooltip: '한 자리 삭제',
                    onPressed: _backspace,
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
