enum IdleWebDataPolicy { keep, cookiesOnly, allSiteData }

class WebViewDataPolicy {
  final IdleWebDataPolicy idlePolicy;
  final List<String> preserveDomains;

  const WebViewDataPolicy({
    this.idlePolicy = IdleWebDataPolicy.cookiesOnly,
    this.preserveDomains = const [],
  });

  static const defaults = WebViewDataPolicy();

  factory WebViewDataPolicy.fromJson(Map<String, dynamic> json) {
    final rawPolicy = json['idlePolicy'];
    final policy = switch (rawPolicy) {
      null || 'cookiesOnly' => IdleWebDataPolicy.cookiesOnly,
      'keep' => IdleWebDataPolicy.keep,
      'allSiteData' => IdleWebDataPolicy.allSiteData,
      _ => throw const FormatException(
          'menu.json webViewData.idlePolicy: keep, cookiesOnly, allSiteData 중 하나 필요',
        ),
    };
    final rawDomains = json['preserveDomains'];
    if (rawDomains != null && rawDomains is! List) {
      throw const FormatException(
        'menu.json webViewData.preserveDomains: 문자열 배열 필요',
      );
    }
    final domains = <String>[];
    for (final value in rawDomains as List? ?? const []) {
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException(
          'menu.json webViewData.preserveDomains: 비어있지 않은 문자열 필요',
        );
      }
      final normalized = normalizeDomain(value);
      if (normalized.isEmpty) {
        throw FormatException(
          'menu.json webViewData.preserveDomains: 올바르지 않은 도메인 ($value)',
        );
      }
      if (!domains.contains(normalized)) domains.add(normalized);
    }
    return WebViewDataPolicy(
      idlePolicy: policy,
      preserveDomains: List.unmodifiable(domains),
    );
  }

  static String normalizeDomain(String value) {
    var candidate = value.trim().toLowerCase();
    final uri = Uri.tryParse(
      candidate.contains('://') ? candidate : 'https://$candidate',
    );
    candidate = uri?.host ?? candidate;
    return candidate
        .replaceFirst(RegExp(r'^\[\*\]\.'), '')
        .replaceFirst(RegExp(r'^\*\.'), '')
        .replaceFirst(RegExp(r'^\.+'), '')
        .replaceFirst(RegExp(r'\.+$'), '');
  }

  bool preserves(String hostOrUrl) {
    final host = normalizeDomain(hostOrUrl);
    return preserveDomains.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    );
  }
}
