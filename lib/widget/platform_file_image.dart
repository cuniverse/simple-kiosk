import 'package:flutter/material.dart';

import 'file_image_stub.dart'
    if (dart.library.io) 'file_image_io.dart' as fi;

/// 파일시스템 경로의 이미지를 표시한다.
///
/// - io 플랫폼: `Image.file` 사용.
/// - 웹: 사용 불가 (에러 텍스트 표시).
class PlatformFileImage extends StatelessWidget {
  final String path;
  final BoxFit fit;

  const PlatformFileImage({
    super.key,
    required this.path,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) => fi.buildFileImage(path, fit);
}
