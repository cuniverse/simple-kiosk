import 'dart:io' show File;

import 'package:flutter/material.dart';

Widget buildFileImage(
  String path,
  BoxFit fit,
  ImageErrorWidgetBuilder? errorBuilder,
) {
  return Image.file(File(path), fit: fit, errorBuilder: errorBuilder);
}
