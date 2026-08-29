import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows WebView DevTools 이벤트는 유효한 등록 토큰을 사용한다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final nativeWebView = File(
      'packages/flutter_inappwebview_windows-0.6.0/'
      'windows/in_app_webview/in_app_webview.cpp',
    ).readAsStringSync();

    expect(
      pubspec,
      contains('path: packages/flutter_inappwebview_windows-0.6.0'),
    );
    expect(
      nativeWebView,
      contains('EventRegistrationToken fetchRequestPausedEventToken = {};'),
    );
    expect(
      nativeWebView,
      contains('.Get(), &fetchRequestPausedEventToken));'),
    );
  });
}
