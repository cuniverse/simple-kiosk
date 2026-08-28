import 'package:flutter/material.dart';

/// 화면 콘텐츠의 터치 입력을 방해하지 않는 작은 버전 표시.
class VersionOverlay extends StatelessWidget {
  final String version;

  const VersionOverlay({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        'v$version',
        key: const ValueKey('version-overlay'),
        style: const TextStyle(
          // 웹 콘텐츠와 사용자 지정 툴바 색상 모두에서 사라지지 않도록
          // 테마 전경색 대신 고정된 중간 회색을 사용한다.
          color: Color(0xE08A8A8A),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          shadows: [
            Shadow(
              color: Color(0x66000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
