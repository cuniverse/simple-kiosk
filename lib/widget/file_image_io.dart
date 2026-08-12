import 'dart:io' show File;

import 'package:flutter/material.dart';

Widget buildFileImage(String path, BoxFit fit) {
  return Image.file(File(path), fit: fit);
}
