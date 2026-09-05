enum IdleWebDataPolicy { keep, cookiesOnly, allSiteData }

class PreservedCookieRule {
  final String domain;
  final String name;

  const PreservedCookieRule({required this.domain, required this.name});

  String get configValue => '$domain|$name';

  bool matches(String cookieDomain, String cookieName) {
    if (name != cookieName) return false;
    final host = WebViewDataPolicy.normalizeDomain(cookieDomain);
    return host == domain || host.endsWith('.$domain');
  }
}

class WebViewDataPolicy {
  final IdleWebDataPolicy idlePolicy;
  final List<String> preserveDomains;
  final List<PreservedCookieRule> preserveCookies;

  const WebViewDataPolicy({
    this.idlePolicy = IdleWebDataPolicy.cookiesOnly,
    this.preserveDomains = const [],
    this.preserveCookies = const [],
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

    final rawCookies = json['preserveCookies'];
    if (rawCookies != null && rawCookies is! List) {
      throw const FormatException(
        'menu.json webViewData.preserveCookies: "도메인|쿠키이름" 문자열 배열 필요',
      );
    }
    final cookies = <PreservedCookieRule>[];
    final cookieKeys = <String>{};
    for (final value in rawCookies as List? ?? const []) {
      if (value is! String) {
        throw const FormatException(
          'menu.json webViewData.preserveCookies: "도메인|쿠키이름" 문자열 필요',
        );
      }
      final separator = value.indexOf('|');
      if (separator <= 0 || separator == value.length - 1) {
        throw FormatException(
          'menu.json webViewData.preserveCookies: "도메인|쿠키이름" 형식 필요 ($value)',
        );
      }
      final domain = normalizeDomain(value.substring(0, separator));
      final name = value.substring(separator + 1).trim();
      if (domain.isEmpty || name.isEmpty || name.contains('|')) {
        throw FormatException(
          'menu.json webViewData.preserveCookies: 올바르지 않은 값 ($value)',
        );
      }
      final key = '$domain\u0000$name';
      if (cookieKeys.add(key)) {
        cookies.add(PreservedCookieRule(domain: domain, name: name));
      }
    }
    return WebViewDataPolicy(
      idlePolicy: policy,
      preserveDomains: List.unmodifiable(domains),
      preserveCookies: List.unmodifiable(cookies),
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

  bool preservesCookie(String domain, String name) {
    return preserves(domain) ||
        preserveCookies.any((rule) => rule.matches(domain, name));
  }
}
