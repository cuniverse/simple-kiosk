class FileEntry {
  final String name;
  final String fullPath;
  const FileEntry({required this.name, required this.fullPath});
}

/// 웹 stub: 호출되면 예외.
Future<List<FileEntry>> listDirectoryFiles(String path) async {
  throw StateError(
    '웹에서는 파일시스템 폴더 스캔이 지원되지 않습니다. '
    '"assets/..." 경로를 사용하세요.',
  );
}

bool get isWindows => false;
