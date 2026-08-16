import 'package:flutter/material.dart';

import '../model/menu_language.dart';

/// 화면보호기 해제 후 표시하는 터치 친화적인 언어 선택 화면.
class LanguageSelection extends StatelessWidget {
  final List<MenuLanguage> languages;
  final String title;
  final String subtitle;
  final ValueChanged<int> onSelected;

  const LanguageSelection({
    super.key,
    required this.languages,
    required this.title,
    required this.subtitle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final availableWidth = MediaQuery.sizeOf(context).width - 48;
    final buttonWidth = availableWidth < 360 ? availableWidth : 360.0;
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                            Text(
                              language.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
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
      ),
    );
  }
}
