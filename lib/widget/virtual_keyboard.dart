import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../service/hangul_composer.dart';
import '../service/keyboard_controller.dart';

/// 플로팅 가상 키보드.
///
/// [KeyboardController.instance.visible] 가 `true` 가 되는 동안만 화면에
/// 표시되며, 화면 안에서 드래그로 위치를 옮길 수 있다.
///
/// 한/영, Shift, 숫자/특수 토글, Backspace, Space, Enter 를 지원하고
/// 한국어 모드에서는 [HangulComposer] 가 두벌식 자모를 조합해
/// `ReplaceLast`/`InsertText` 이벤트 시퀀스로 변환해 [KeyboardController] 에
/// 디스패치한다.
class VirtualKeyboardOverlay extends StatefulWidget {
  const VirtualKeyboardOverlay({super.key});

  @override
  State<VirtualKeyboardOverlay> createState() => _VirtualKeyboardOverlayState();
}

enum _KbMode { ko, en, sym }

class _VirtualKeyboardOverlayState extends State<VirtualKeyboardOverlay> {
  Offset _offset = const Offset(40, 240);
  bool _placed = false;

  _KbMode _mode = _KbMode.ko;
  bool _shift = false;
  bool _shiftLock = false;

  final HangulComposer _hangul = HangulComposer();

  static const double _kbWidth = 760;
  static const double _kbHeight = 320;

  void _onCharKey(String label) {
    final controller = KeyboardController.instance;
    if (_mode == _KbMode.ko) {
      final jamo = _shifted(label);
      for (final ev in _hangul.input(jamo)) {
        controller.dispatch(ev);
      }
    } else {
      // 영문/숫자/특수: 조합 없음.
      _hangul.commit();
      final ch = _mode == _KbMode.en ? _shiftedEn(label) : label;
      controller.dispatch(InsertText(ch));
    }
    // shift lock 이 아니면 한 번 누른 뒤 해제.
    if (_shift && !_shiftLock) {
      setState(() => _shift = false);
    }
  }

  String _shifted(String base) {
    // 한국어 두벌식 shift: ㅂ→ㅃ, ㅈ→ㅉ, ㄷ→ㄸ, ㄱ→ㄲ, ㅅ→ㅆ, ㅐ→ㅒ, ㅔ→ㅖ
    if (!_shift) return base;
    const map = {
      'ㅂ': 'ㅃ',
      'ㅈ': 'ㅉ',
      'ㄷ': 'ㄸ',
      'ㄱ': 'ㄲ',
      'ㅅ': 'ㅆ',
      'ㅐ': 'ㅒ',
      'ㅔ': 'ㅖ',
    };
    return map[base] ?? base;
  }

  String _shiftedEn(String base) {
    if (!_shift) return base;
    if (base.length != 1) return base;
    return base.toUpperCase();
  }

  void _onBackspace() {
    final controller = KeyboardController.instance;
    if (_mode == _KbMode.ko) {
      for (final ev in _hangul.backspace()) {
        controller.dispatch(ev);
      }
    } else {
      controller.dispatch(const BackspaceEvent());
    }
  }

  void _onSpace() {
    _hangul.commit();
    KeyboardController.instance.dispatch(const InsertText(' '));
  }

  void _onEnter() {
    _hangul.commit();
    KeyboardController.instance.dispatch(const EnterEvent());
  }

  void _onShift() {
    setState(() {
      // 한 번 탭: 한 글자만 대문자 (or 쌍자음)
      // 빠르게 두 번: 잠금
      if (!_shift) {
        _shift = true;
        _shiftLock = false;
      } else if (!_shiftLock) {
        _shiftLock = true;
      } else {
        _shift = false;
        _shiftLock = false;
      }
    });
  }

  void _onModeToggle() {
    setState(() {
      _hangul.commit();
      switch (_mode) {
        case _KbMode.ko:
          _mode = _KbMode.en;
          break;
        case _KbMode.en:
          _mode = _KbMode.ko;
          break;
        case _KbMode.sym:
          _mode = _KbMode.ko;
          break;
      }
      _shift = false;
      _shiftLock = false;
    });
  }

  void _onSymbolsToggle() {
    setState(() {
      _hangul.commit();
      _mode = _mode == _KbMode.sym ? _KbMode.ko : _KbMode.sym;
      _shift = false;
      _shiftLock = false;
    });
  }

  void _onClose() {
    _hangul.commit();
    KeyboardController.instance.hide();
  }

  // 키 레이아웃 — 각 모드별 row.
  List<List<String>> get _rows {
    switch (_mode) {
      case _KbMode.ko:
        return const [
          ['ㅂ', 'ㅈ', 'ㄷ', 'ㄱ', 'ㅅ', 'ㅛ', 'ㅕ', 'ㅑ', 'ㅐ', 'ㅔ'],
          ['ㅁ', 'ㄴ', 'ㅇ', 'ㄹ', 'ㅎ', 'ㅗ', 'ㅓ', 'ㅏ', 'ㅣ'],
          ['ㅋ', 'ㅌ', 'ㅊ', 'ㅍ', 'ㅠ', 'ㅜ', 'ㅡ'],
        ];
      case _KbMode.en:
        return const [
          ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
          ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
          ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
        ];
      case _KbMode.sym:
        return const [
          ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
          ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')'],
          ['-', '_', '=', '+', '/', '?', ',', '.', ':', ';'],
        ];
    }
  }

  String _displayLabel(String base) {
    if (_mode == _KbMode.ko) return _shifted(base);
    if (_mode == _KbMode.en) return _shiftedEn(base);
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardWidth =
        math.min(_kbWidth, math.max(0.0, media.size.width - 16));
    final keyboardHeight =
        math.min(_kbHeight, math.max(0.0, media.size.height - 16));
    final maxX = math.max(8.0, media.size.width - keyboardWidth - 8);
    final maxY = math.max(8.0, media.size.height - keyboardHeight - 8);
    // 첫 표시 시 화면 우하단에 가깝게 배치.
    if (!_placed) {
      final size = media.size;
      _offset = Offset(
        ((size.width - keyboardWidth) / 2).clamp(8.0, maxX),
        (size.height - keyboardHeight - 24).clamp(8.0, maxY),
      );
      _placed = true;
    }

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      width: keyboardWidth,
      height: keyboardHeight,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            _buildHandle(),
            const Divider(height: 1),
            Expanded(child: _buildKeys()),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        final media = MediaQuery.of(context);
        final keyboardWidth =
            math.min(_kbWidth, math.max(0.0, media.size.width - 16));
        final keyboardHeight =
            math.min(_kbHeight, math.max(0.0, media.size.height - 16));
        final maxX = math.max(8.0, media.size.width - keyboardWidth - 8);
        final maxY = math.max(8.0, media.size.height - keyboardHeight - 8);
        setState(() {
          _offset = Offset(
            (_offset.dx + d.delta.dx).clamp(8.0, maxX),
            (_offset.dy + d.delta.dy).clamp(8.0, maxY),
          );
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.drag_handle, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '가상 키보드',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Semantics(
              label: '가상 키보드 닫기',
              button: true,
              child: IconButton(
                onPressed: _onClose,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeys() {
    final rows = _rows;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        children: [
          for (final row in rows) Expanded(child: _buildRow(row)),
          Expanded(child: _buildBottomRow()),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> labels) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _KbKey(
                  label: _displayLabel(label),
                  onTap: () => _onCharKey(label),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomRow() {
    final shiftEnabled = _mode != _KbMode.sym;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (shiftEnabled)
            _SpecialKey(
              flex: 2,
              icon: _shiftLock ? Icons.keyboard_capslock : Icons.arrow_upward,
              highlighted: _shift,
              onTap: _onShift,
            ),
          _SpecialKey(
            flex: 2,
            label:
                _mode == _KbMode.ko ? 'EN' : (_mode == _KbMode.en ? '한' : '한'),
            onTap: _onModeToggle,
          ),
          _SpecialKey(
            flex: 2,
            label: _mode == _KbMode.sym ? 'ABC' : '!#1',
            onTap: _onSymbolsToggle,
          ),
          _SpecialKey(
            flex: 6,
            label: 'space',
            onTap: _onSpace,
          ),
          _SpecialKey(
            flex: 2,
            icon: Icons.backspace_outlined,
            onTap: _onBackspace,
          ),
          _SpecialKey(
            flex: 2,
            icon: Icons.keyboard_return,
            onTap: _onEnter,
          ),
        ],
      ),
    );
  }
}

class _KbKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KbKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        padding: EdgeInsets.zero,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _SpecialKey extends StatelessWidget {
  final int flex;
  final String? label;
  final IconData? icon;
  final bool highlighted;
  final VoidCallback onTap;

  const _SpecialKey({
    required this.flex,
    this.label,
    this.icon,
    this.highlighted = false,
    required this.onTap,
  }) : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                highlighted ? scheme.primary : scheme.surfaceContainerHigh,
            foregroundColor:
                highlighted ? scheme.onPrimary : scheme.onSurfaceVariant,
            padding: EdgeInsets.zero,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: icon != null
              ? Icon(icon, size: 22)
              : Text(
                  label!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}
