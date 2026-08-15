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
    return Material(
      color: colors.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language, size: 72, color: colors.primary),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 40),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 24,
                  runSpacing: 24,
                  children: List.generate(languages.length, (index) {
                    final language = languages[index];
                    return SizedBox(
                      width: 300,
                      height: 140,
                      child: FilledButton(
                        key: ValueKey('language-${language.id}'),
                        onPressed: () => onSelected(index),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              language.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (language.subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                language.subtitle!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 18),
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
