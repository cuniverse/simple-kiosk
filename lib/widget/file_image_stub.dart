import 'package:flutter/material.dart';

Widget buildFileImage(
  String path,
  BoxFit fit,
  ImageErrorWidgetBuilder? errorBuilder,
) {
  return const Center(
    child: Text(
      '웹에서는 파일 경로 이미지를 표시할 수 없습니다.',
      style: TextStyle(color: Colors.white70),
    ),
  );
}
