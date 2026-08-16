import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../model/webview_data_policy.dart';
import 'app_logger.dart';

class WebViewDataService {
  const WebViewDataService._();

  static Future<void> applyIdlePolicy(
    WebViewDataPolicy policy, {
    Iterable<String> knownUrls = const [],
  }) async {
    switch (policy.idlePolicy) {
      case IdleWebDataPolicy.keep:
        return;
      case IdleWebDataPolicy.cookiesOnly:
        await _deleteCookies(policy, knownUrls);
        return;
      case IdleWebDataPolicy.allSiteData:
        await _deleteSiteData(policy);
        return;
    }
  }

  static Future<void> _deleteCookies(
    WebViewDataPolicy policy,
    Iterable<String> knownUrls,
  ) async {
    final manager = CookieManager.instance();
    if (policy.preserveDomains.isEmpty) {
      await manager.deleteAllCookies();
      return;
    }

    try {
      final cookies = await manager.getAllCookies();
      for (final cookie in cookies) {
        final domain = cookie.domain;
        if (domain == null || policy.preserves(domain)) continue;
        final host = WebViewDataPolicy.normalizeDomain(domain);
        if (host.isEmpty) continue;
        await manager.deleteCookie(
          url: WebUri('${cookie.isSecure == true ? 'https' : 'http'}://$host/'),
          name: cookie.name,
          domain: domain,
          path: cookie.path ?? '/',
        );
      }
    } catch (error) {
      AppLogger.warning(
        LogCategory.webview,
        'Cookie enumeration unavailable; using configured URL cleanup: $error',
      );
      // Windows WebView2처럼 전체 쿠키 열거를 제공하지 않는 플랫폼에서는 설정된
      // 메뉴 URL별로 쿠키를 지운다. 예외 도메인의 URL은 건드리지 않는다.
      final visitedHosts = <String>{};
      for (final value in knownUrls) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            !uri.hasAuthority ||
            policy.preserves(uri.host) ||
            !visitedHosts.add(uri.host.toLowerCase())) {
          continue;
        }
        await manager.deleteCookies(url: WebUri(uri.origin));
      }
    }
  }

  static Future<void> _deleteSiteData(WebViewDataPolicy policy) async {
    final manager = WebStorageManager.instance();
    try {
      final records = await manager.fetchDataRecords(
        dataTypes: WebsiteDataType.ALL,
      );
      final removable = records
          .where(
            (record) =>
                record.displayName == null ||
                !policy.preserves(record.displayName!),
          )
          .toList(growable: false);
      if (removable.isNotEmpty) {
        await manager.removeDataFor(
          dataTypes: WebsiteDataType.ALL,
          dataRecords: removable,
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.webview, error, stackTrace);
      if (policy.preserveDomains.isEmpty) {
        await CookieManager.instance().deleteAllCookies();
        await InAppWebViewController.clearAllCache(includeDiskFiles: true);
        try {
          await manager.deleteAllData();
        } catch (_) {}
      }
    }
  }
}
