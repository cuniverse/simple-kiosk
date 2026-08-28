import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/user_manual_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('내장 Markdown 매뉴얼을 완전한 HTML 문서로 변환한다', () {
    final html = buildUserManualHtml('''
# 사용자 매뉴얼

[README](../README.md)
''');

    expect(html, contains('<title>여의도성당Signage 사용자 매뉴얼</title>'));
    expect(html, contains('<a id="사용자-매뉴얼"></a>'));
    expect(
      html,
      contains(
        'href="https://github.com/cuniverse/simple-kiosk/blob/main/README.md"',
      ),
    );
  });

  test('일반 Flutter 빌드에도 F1용 매뉴얼 원본을 포함한다', () async {
    final markdown = await rootBundle.loadString('docs/MANUAL.md');
    expect(markdown, contains('# 여의도성당Signage 사용 매뉴얼'));

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- docs/MANUAL.md'));
  });

  test('WebView 포커스에서도 F1을 매뉴얼 콜백으로 전달한다', () {
    final source = File('lib/widget/kiosk_webview.dart').readAsStringSync();
    expect(source, contains("event.key === 'F1'"));
    expect(source, contains("handlerName: 'kioskShowManual'"));
    expect(source, contains('widget.onShowManual?.call()'));
  });
}
