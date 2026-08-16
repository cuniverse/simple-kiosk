import 'dart:io';

import 'package:markdown/markdown.dart';

const _repositoryBase = 'https://github.com/cuniverse/simple-kiosk/blob/main/';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/build_user_manual.dart <input.md> <output.html>',
    );
    exitCode = 64;
    return;
  }

  final input = File(arguments[0]);
  if (!await input.exists()) {
    stderr.writeln('Manual source not found: ${input.path}');
    exitCode = 66;
    return;
  }

  final markdownSource = await input.readAsString();
  final anchoredSource = _addHeadingAnchors(markdownSource);
  var body = markdownToHtml(
    anchoredSource,
    extensionSet: ExtensionSet.gitHubFlavored,
    enableTagfilter: true,
  );
  body = body.replaceAllMapped(
    RegExp(r'href="\.\./([^"#]+)(#[^"]*)?"'),
    (match) =>
        'href="$_repositoryBase${match.group(1)}${match.group(2) ?? ''}"',
  );

  final output = File(arguments[1]);
  await output.parent.create(recursive: true);
  await output.writeAsString(_htmlDocument(body), flush: true);
  stdout.writeln('Created user manual: ${output.path}');
}

String _addHeadingAnchors(String source) {
  final counts = <String, int>{};
  final heading = RegExp(r'^(#{1,6})\s+(.+?)\s*#*\s*$');
  return source.split('\n').map((line) {
    final match = heading.firstMatch(line);
    if (match == null) return line;
    final base = _headingSlug(match.group(2)!);
    if (base.isEmpty) return line;
    final duplicate =
        counts.update(base, (value) => value + 1, ifAbsent: () => 0);
    final slug = duplicate == 0 ? base : '$base-$duplicate';
    return '<a id="$slug"></a>\n\n$line';
  }).join('\n');
}

String _headingSlug(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[`*_~]'), '')
    .replaceAll(RegExp(r'[^a-z0-9_\-\u3131-\u318e\uac00-\ud7a3 ]'), '')
    .replaceAll(' ', '-');

String _htmlDocument(String body) => '''<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>여의도성당Signage 사용자 매뉴얼</title>
  <style>
    :root { color-scheme: light dark; font-family: "Malgun Gothic", "Segoe UI", sans-serif; }
    body { max-width: 980px; margin: 0 auto; padding: 32px 40px 72px; line-height: 1.72; color: #1f2937; background: #fff; }
    h1, h2, h3, h4 { line-height: 1.3; margin-top: 1.7em; scroll-margin-top: 20px; }
    h1 { margin-top: 0; padding-bottom: .35em; border-bottom: 2px solid #d1d5db; }
    h2 { padding-bottom: .25em; border-bottom: 1px solid #d1d5db; }
    a { color: #155eef; text-decoration-thickness: 1px; text-underline-offset: 3px; }
    table { width: 100%; border-collapse: collapse; display: block; overflow-x: auto; margin: 1em 0; }
    th, td { border: 1px solid #cbd5e1; padding: 8px 10px; text-align: left; vertical-align: top; }
    th { background: #f1f5f9; }
    code { font-family: Consolas, monospace; background: #f1f5f9; border-radius: 4px; padding: .12em .32em; }
    pre { overflow-x: auto; padding: 16px; border: 1px solid #d1d5db; border-radius: 8px; background: #f8fafc; }
    pre code { padding: 0; background: transparent; }
    blockquote { margin-left: 0; padding: 4px 16px; border-left: 4px solid #94a3b8; color: #475569; }
    img { max-width: 100%; height: auto; }
    @media (prefers-color-scheme: dark) {
      body { color: #e5e7eb; background: #111827; }
      th, code { background: #1f2937; }
      pre { background: #0f172a; border-color: #475569; }
      th, td { border-color: #475569; }
      a { color: #7db4ff; }
      blockquote { color: #cbd5e1; }
    }
    @media (max-width: 640px) { body { padding: 20px 18px 48px; } }
    @media print { body { max-width: none; padding: 0; color: #000; background: #fff; } a { color: #000; } }
  </style>
</head>
<body>
$body
</body>
</html>
''';
