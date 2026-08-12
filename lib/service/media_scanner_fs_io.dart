import 'dart:io' show Directory, File, FileSystemEntity, Platform;

class FileEntry {
  final String name;
  final String fullPath;
  const FileEntry({required this.name, required this.fullPath});
}

Future<List<FileEntry>> listDirectoryFiles(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    throw StateError('대기화면 폴더가 없습니다: $path');
  }
  final result = <FileEntry>[];
  final entries = dir.listSync(followLinks: false);
  for (final FileSystemEntity entity in entries) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isNotEmpty
        ? entity.uri.pathSegments.last
        : entity.path;
    result.add(FileEntry(name: name, fullPath: entity.path));
  }
  return result;
}

bool get isWindows => Platform.isWindows;
