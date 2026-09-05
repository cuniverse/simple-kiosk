import 'dart:async';

import 'package:flutter/material.dart';

import '../model/menu_language.dart';
import '../model/menu_topic.dart';
import '../service/font_resource_service.dart';
import 'button_text_wrap.dart';
import 'material_icon_registry.dart';
import 'platform_file_image.dart';
import 'version_overlay.dart';

/// 화면보호기 해제 후 표시하는 터치 친화적인 언어 선택 화면.
class LanguageSelection extends StatefulWidget {
  final List<MenuLanguage> languages;
  final String title;
  final String subtitle;
  final String topicTitle;
  final String topicSubtitle;
  final bool skipSingleTopic;
  final bool hideTopicIcons;
  final String? fontFamily;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? secondaryForegroundColor;
  final double buttonWidth;
  final double buttonHeight;
  final Color? buttonColor;
  final Color? buttonForegroundColor;
  final Color? selectedButtonColor;
  final Color? selectedButtonForegroundColor;
  final void Function(int languageIndex, int topicIndex) onSelected;
  final VoidCallback onReturnToIdle;
  final String? versionLabel;

  const LanguageSelection({
    super.key,
    required this.languages,
    required this.title,
    required this.subtitle,
    this.topicTitle = '주제를 선택하세요',
    this.topicSubtitle = 'Please select a topic',
    this.skipSingleTopic = true,
    this.hideTopicIcons = false,
    this.fontFamily,
    this.backgroundColor,
    this.foregroundColor,
    this.secondaryForegroundColor,
    this.buttonWidth = 400,
    this.buttonHeight = 190,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
    required this.onSelected,
    required this.onReturnToIdle,
    this.versionLabel,
  });

  @override
  State<LanguageSelection> createState() => _LanguageSelectionState();
}

class _LanguageSelectionState extends State<LanguageSelection> {
  int? _selectedLanguageIndex;
  Timer? _singleTopicTimer;

  @override
  void dispose() {
    _singleTopicTimer?.cancel();
    super.dispose();
  }

  void _selectLanguage(int index) {
    if (index < 0 || index >= widget.languages.length) return;
    _singleTopicTimer?.cancel();
    setState(() => _selectedLanguageIndex = index);
    final topics = widget.languages[index].effectiveTopics;
    if (widget.skipSingleTopic && topics.length == 1) {
      // 선택한 언어 버튼이 상단으로 이동하는 애니메이션을 보여준 뒤 바로 진입한다.
      _singleTopicTimer = Timer(const Duration(milliseconds: 420), () {
        if (mounted && _selectedLanguageIndex == index) {
          widget.onSelected(index, 0);
        }
      });
    }
  }

  void _showLanguages() {
    _singleTopicTimer?.cancel();
    setState(() => _selectedLanguageIndex = null);
  }

  void _returnToIdle() {
    // 화면보호기 뒤에도 이 위젯이 유지되는 구성에서 이전 주제 화면이
    // 다시 노출되지 않도록 진입 전에 언어 선택 첫 단계로 되돌린다.
    if (_selectedLanguageIndex != null) {
      _showLanguages();
    }
    widget.onReturnToIdle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final availableWidth = MediaQuery.sizeOf(context).width - 48;
    final buttonWidth = availableWidth < widget.buttonWidth
        ? availableWidth
        : widget.buttonWidth;
    return Material(
      key: const ValueKey('language-selection-background'),
      color: widget.backgroundColor ?? colors.surface,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 360),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _selectedLanguageIndex == null
                    ? _buildLanguages(colors, buttonWidth)
                    : _buildTopics(
                        colors,
                        buttonWidth,
                        _selectedLanguageIndex!,
                      ),
              ),
            ),
            Positioned(
              left: 24,
              top: 20,
              child: Tooltip(
                message: '화면 보호기로 돌아가기',
                child: FilledButton.tonalIcon(
                  key: const ValueKey('return-to-idle'),
                  onPressed: _returnToIdle,
                  icon: const Icon(Icons.wallpaper_outlined, size: 28),
                  label: Text(
                    '화면 보호기로 돌아가기',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: widget.fontFamily,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 58),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                ),
              ),
            ),
            if (widget.versionLabel != null)
              Positioned(
                right: 12,
                bottom: 8,
                child: VersionOverlay(version: widget.versionLabel!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguages(ColorScheme colors, double buttonWidth) {
    return SingleChildScrollView(
      key: const ValueKey('language-step'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 96),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.language,
            size: 88,
            color: widget.foregroundColor ?? colors.primary,
          ),
          const SizedBox(height: 24),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  fontFamily: widget.fontFamily,
                  color: widget.foregroundColor,
                ),
          ),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 28,
                    color: widget.secondaryForegroundColor ??
                        colors.onSurfaceVariant,
                    fontFamily: widget.fontFamily,
                  ),
            ),
          ],
          const SizedBox(height: 48),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 24,
            children: List.generate(widget.languages.length, (index) {
              final language = widget.languages[index];
              return _SelectionButton(
                key: ValueKey('language-${language.id}'),
                width: buttonWidth,
                height: widget.buttonHeight,
                label: language.label,
                subtitle: language.subtitle,
                icon: language.icon,
                fontFamily: FontResourceService.familyFor(
                      language.fontFamily,
                    ) ??
                    widget.fontFamily,
                buttonColor: widget.buttonColor,
                buttonForegroundColor: widget.buttonForegroundColor,
                selectedButtonColor: widget.selectedButtonColor,
                selectedButtonForegroundColor:
                    widget.selectedButtonForegroundColor,
                onPressed: () => _selectLanguage(index),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTopics(
    ColorScheme colors,
    double buttonWidth,
    int languageIndex,
  ) {
    final language = widget.languages[languageIndex];
    final topics = language.effectiveTopics;
    final skipping = widget.skipSingleTopic && topics.length == 1;
    final topicTitle = language.topicSelectionTitle(widget.topicTitle);
    final topicSubtitle = language.topicSelectionSubtitle(widget.topicSubtitle);
    final changeLanguageLabel = language.changeLanguageLabel;
    return SingleChildScrollView(
      key: ValueKey('topic-step-${language.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 120, end: 0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, offset, child) => Transform.translate(
              offset: Offset(0, offset),
              child: child,
            ),
            child: _SelectionButton(
              key: ValueKey('selected-language-${language.id}'),
              width: buttonWidth,
              height: widget.buttonHeight,
              label: language.label,
              subtitle: language.subtitle,
              icon: language.icon,
              fontFamily: FontResourceService.familyFor(
                    language.fontFamily,
                  ) ??
                  widget.fontFamily,
              buttonColor: widget.buttonColor,
              buttonForegroundColor: widget.buttonForegroundColor,
              selectedButtonColor: widget.selectedButtonColor,
              selectedButtonForegroundColor:
                  widget.selectedButtonForegroundColor,
              selected: true,
              onPressed: _showLanguages,
            ),
          ),
          const SizedBox(height: 28),
          if (skipping) ...[
            const SizedBox(height: 28),
            const CircularProgressIndicator(),
          ] else ...[
            Text(
              topicTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    fontFamily: widget.fontFamily,
                    color: widget.foregroundColor,
                  ),
            ),
            if (topicSubtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                topicSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 25,
                      color: widget.secondaryForegroundColor ??
                          colors.onSurfaceVariant,
                      fontFamily: widget.fontFamily,
                    ),
              ),
            ],
            const SizedBox(height: 34),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 24,
              children: List.generate(topics.length, (topicIndex) {
                final topic = topics[topicIndex];
                return _TopicButton(
                  topic: topic,
                  showIcon: topic.showIcon ?? !widget.hideTopicIcons,
                  width: buttonWidth,
                  height: widget.buttonHeight,
                  fontFamily: widget.fontFamily,
                  buttonColor: widget.buttonColor,
                  buttonForegroundColor: widget.buttonForegroundColor,
                  selectedButtonColor: widget.selectedButtonColor,
                  selectedButtonForegroundColor:
                      widget.selectedButtonForegroundColor,
                  onPressed: () => widget.onSelected(
                    languageIndex,
                    topicIndex,
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            TextButton.icon(
              key: const ValueKey('change-language'),
              onPressed: _showLanguages,
              icon: const Icon(Icons.arrow_back),
              label: Text(
                keepButtonWordsTogether(changeLanguageLabel),
                semanticsLabel: changeLanguageLabel,
                style: TextStyle(fontSize: 20, fontFamily: widget.fontFamily),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopicButton extends StatelessWidget {
  final MenuTopic topic;
  final bool showIcon;
  final double width;
  final double height;
  final VoidCallback onPressed;
  final String? fontFamily;
  final Color? buttonColor;
  final Color? buttonForegroundColor;
  final Color? selectedButtonColor;
  final Color? selectedButtonForegroundColor;

  const _TopicButton({
    required this.topic,
    required this.showIcon,
    required this.width,
    required this.height,
    required this.onPressed,
    this.fontFamily,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
  });

  @override
  Widget build(BuildContext context) => _SelectionButton(
        key: ValueKey('topic-${topic.id}'),
        width: width,
        height: height,
        label: topic.label,
        subtitle: topic.subtitle,
        icon: showIcon ? topic.icon : null,
        fontFamily: fontFamily,
        buttonColor: buttonColor,
        buttonForegroundColor: buttonForegroundColor,
        selectedButtonColor: selectedButtonColor,
        selectedButtonForegroundColor: selectedButtonForegroundColor,
        onPressed: onPressed,
      );
}

class _SelectionButton extends StatelessWidget {
  final double width;
  final double height;
  final String label;
  final String? subtitle;
  final String? icon;
  final VoidCallback onPressed;
  final bool selected;
  final String? fontFamily;
  final Color? buttonColor;
  final Color? buttonForegroundColor;
  final Color? selectedButtonColor;
  final Color? selectedButtonForegroundColor;

  const _SelectionButton({
    super.key,
    required this.width,
    required this.height,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.fontFamily,
    this.buttonColor,
    this.buttonForegroundColor,
    this.selectedButtonColor,
    this.selectedButtonForegroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveForeground = selected
        ? (selectedButtonForegroundColor ?? buttonForegroundColor)
        : buttonForegroundColor;
    return SizedBox(
      width: width,
      height: height,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor:
              selected ? (selectedButtonColor ?? buttonColor) : buttonColor,
          foregroundColor: effectiveForeground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: selected
                ? BorderSide(
                    color: effectiveForeground ??
                        Theme.of(context).colorScheme.onPrimary,
                    width: 3,
                  )
                : BorderSide.none,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              SizedBox(
                width: 64,
                height: 64,
                child: _LanguageIcon(value: icon!),
              ),
              const SizedBox(height: 10),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  keepButtonWordsTogether(label),
                  key: ValueKey('selection-label-$label'),
                  semanticsLabel: label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                keepButtonWordsTogether(subtitle!),
                semanticsLabel: subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontFamily: fontFamily),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LanguageIcon extends StatelessWidget {
  final String value;

  const _LanguageIcon({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.startsWith('icon:')) {
      return FittedBox(
        child: Icon(
          MaterialIconRegistry.lookup(value.substring(5)) ?? Icons.language,
        ),
      );
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.language, size: 48),
      );
    }
    if (_isAbsoluteFilePath(value)) {
      return PlatformFileImage(
        path: value,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.language, size: 48),
      );
    }
    if (value.contains('/') || value.contains('\\')) {
      return Image.asset(
        value,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.language, size: 48),
      );
    }
    return FittedBox(child: Text(value));
  }
}

bool _isAbsoluteFilePath(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
