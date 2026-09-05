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
    if (policy.preserveDomains.isEmpty && policy.preserveCookies.isEmpty) {
      await manager.deleteAllCookies();
      return;
    }

    try {
      final cookies = await manager.getAllCookies();
      for (final cookie in cookies) {
        final domain = cookie.domain;
        if (domain == null || policy.preservesCookie(domain, cookie.name)) {
          continue;
        }
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
      // 메뉴 URL별 쿠키를 열거해 보존 규칙에 없는 쿠키만 지운다.
      final visitedUrls = <String>{};
      final deletedCookies = <String>{};
      for (final value in knownUrls) {
        final uri = Uri.tryParse(value);
        if (uri == null ||
            !uri.hasAuthority ||
            policy.preserves(uri.host) ||
            !visitedUrls.add(uri.toString())) {
          continue;
        }
        try {
          final cookies = await manager.getCookies(url: WebUri(uri.toString()));
          for (final cookie in cookies) {
            final domain = cookie.domain ?? uri.host;
            if (policy.preservesCookie(domain, cookie.name)) continue;
            final key = '${WebViewDataPolicy.normalizeDomain(domain)}\u0000'
                '${cookie.path ?? '/'}\u0000${cookie.name}';
            if (!deletedCookies.add(key)) continue;
            await manager.deleteCookie(
              url: WebUri(uri.origin),
              name: cookie.name,
              domain: cookie.domain,
              path: cookie.path ?? '/',
            );
          }
        } catch (urlError) {
          // 개별 열거도 불가능하면 보안 정책을 우선해 해당 URL의 쿠키를 모두
          // 삭제한다. 이 경우 동의 배너가 다시 나타날 수 있다.
          AppLogger.warning(
            LogCategory.webview,
            'Cookie cleanup fallback failed for ${uri.origin}; '
            'deleting all URL cookies: $urlError',
          );
          await manager.deleteCookies(url: WebUri(uri.origin));
        }
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
