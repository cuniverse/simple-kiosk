import 'package:flutter/material.dart';

import '../model/menu_language.dart';
import 'material_icon_registry.dart';

/// 화면보호기 해제 후 표시하는 터치 친화적인 언어 선택 화면.
class LanguageSelection extends StatelessWidget {
  final List<MenuLanguage> languages;
  final String title;
  final String subtitle;
  final ValueChanged<int> onSelected;
  final VoidCallback onReturnToIdle;

  const LanguageSelection({
    super.key,
    required this.languages,
    required this.title,
    required this.subtitle,
    required this.onSelected,
    required this.onReturnToIdle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final availableWidth = MediaQuery.sizeOf(context).width - 48;
    final buttonWidth = availableWidth < 360 ? availableWidth : 360.0;
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 96),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 88, color: colors.primary),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontSize: 28,
                                  color: colors.onSurfaceVariant,
                                ),
                      ),
                    ],
                    const SizedBox(height: 48),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 24,
                      runSpacing: 24,
                      children: List.generate(languages.length, (index) {
                        final language = languages[index];
                        return SizedBox(
                          width: buttonWidth,
                          height: 176,
                          child: FilledButton(
                            key: ValueKey('language-${language.id}'),
                            onPressed: () => onSelected(index),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (language.icon != null) ...[
                                  SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: _LanguageIcon(value: language.icon!),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      language.label,
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                if (language.subtitle != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    language.subtitle!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
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
                  onPressed: onReturnToIdle,
                  icon: const Icon(Icons.wallpaper_outlined, size: 28),
                  label: const Text(
                    '화면 보호기로 돌아가기',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 58),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                ),
              ),
            ),
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
