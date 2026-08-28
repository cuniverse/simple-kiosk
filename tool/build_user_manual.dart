import 'dart:io';

import 'package:simple_kiosk/service/user_manual_service.dart';

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
  final output = File(arguments[1]);
  await output.parent.create(recursive: true);
  await output.writeAsString(buildUserManualHtml(markdownSource), flush: true);
  stdout.writeln('Created user manual: ${output.path}');
}
