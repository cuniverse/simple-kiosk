import 'package:flutter/material.dart';

class WebViewLoadingOverlay extends StatelessWidget {
  final String title;
  final bool timedOut;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  const WebViewLoadingOverlay({
    super.key,
    required this.title,
    required this.timedOut,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      builder: (context, opacity, child) => Opacity(
        opacity: opacity,
        child: child,
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Color(0x52000000)),
            ),
          ),
          Center(
            child: Material(
              key: const ValueKey('webview-loading-overlay'),
              color: colors.surface.withValues(alpha: 0.96),
              elevation: 12,
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!timedOut)
                        const SizedBox(
                          width: 42,
                          height: 42,
                          child: CircularProgressIndicator(strokeWidth: 4),
                        )
                      else
                        Icon(
                          Icons.hourglass_disabled_outlined,
                          size: 48,
                          color: colors.error,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timedOut ? '페이지 응답이 늦어지고 있습니다.' : '페이지를 불러오고 있습니다…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (timedOut) ...[
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: onCancel,
                              child: const Text('취소'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
