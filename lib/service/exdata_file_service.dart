import 'dart:io';
import 'dart:math';

import 'runtime_paths.dart';

class ExdataFileException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ExdataFileException(this.statusCode, this.code, this.message);

  @override
  String toString() => message;
}

class ExdataFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime modifiedAt;

  const ExdataFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': isDirectory ? 'directory' : 'file',
        if (size != null) 'size': size,
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
      };
}

class ExdataDirectoryListing {
  final String path;
  final List<ExdataFileEntry> entries;

  const ExdataDirectoryListing({required this.path, required this.entries});

  Map<String, dynamic> toJson() => {
        'root': 'exdata',
        'path': path,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };
}

class ExdataDownload {
  final File file;
  final String name;
  final int size;

  const ExdataDownload({
    required this.file,
    required this.name,
    required this.size,
  });
}

class ExdataChunkUploadResult {
  final int size;
  final bool complete;

  const ExdataChunkUploadResult({required this.size, required this.complete});
}

class ExdataConfigReference {
  final String relativePath;
  final String settingPath;

  const ExdataConfigReference({
    required this.relativePath,
    required this.settingPath,
  });

  bool isAffectedBy(String targetPath) {
    final target = targetPath.toLowerCase();
    final referenced = relativePath.toLowerCase();
    return target == referenced ||
        target.isEmpty ||
        referenced.isEmpty ||
        target.startsWith('$referenced/') ||
        referenced.startsWith('$target/');
  }
}

/// Finds every `exdata/...` value in the effective configuration.
List<ExdataConfigReference> findExdataConfigReferences(
  dynamic config, {
  String? exdataRootPath,
}) {
  final references = <ExdataConfigReference>[];
  final normalizedRoot = exdataRootPath == null || exdataRootPath.isEmpty
      ? null
      : Directory(exdataRootPath)
          .absolute
          .path
          .replaceAll('\\', '/')
          .replaceFirst(
            RegExp(r'/+$'),
            '',
          );

  String? relativeExdataPath(String value) {
    var configuredPath = value.trim().replaceAll('\\', '/');
    while (configuredPath.startsWith('./')) {
      configuredPath = configuredPath.substring(2);
    }
    if (configuredPath.toLowerCase().startsWith('exdata/')) {
      return configuredPath.substring('exdata/'.length);
    }
    if (normalizedRoot == null) return null;
    final comparedPath =
        Platform.isWindows ? configuredPath.toLowerCase() : configuredPath;
    final comparedRoot =
        Platform.isWindows ? normalizedRoot.toLowerCase() : normalizedRoot;
    if (comparedPath == comparedRoot) return '';
    if (comparedPath.startsWith('$comparedRoot/')) {
      return configuredPath.substring(normalizedRoot.length + 1);
    }
    return null;
  }

  void visit(dynamic value, String settingPath) {
    if (value is Map) {
      for (final entry in value.entries) {
        final childPath =
            settingPath.isEmpty ? '${entry.key}' : '$settingPath.${entry.key}';
        visit(entry.value, childPath);
      }
      return;
    }
    if (value is List) {
      for (var index = 0; index < value.length; index++) {
        visit(value[index], '$settingPath[$index]');
      }
      return;
    }
    if (value is! String) return;

    final matched = relativeExdataPath(value);
    if (matched == null) return;
    final relative = matched.replaceFirst(RegExp(r'/+$'), '');
    try {
      references.add(ExdataConfigReference(
        relativePath: ExdataFileService.normalizeRelativePath(
          relative,
          allowRoot: true,
        ),
        settingPath: settingPath,
      ));
    } on ExdataFileException {
      // Invalid configuration paths are handled by normal config validation.
    }
  }

  visit(config, '');
  return references;
}

/// WEB 관리자에서 사용하는 `exdata` 전용 파일 시스템 경계.
///
/// 모든 외부 경로는 슬래시(`/`) 기반 상대경로로 받고, 실제 경로와 부모의
/// 심볼릭 링크를 해석한 뒤에도 `exdata` 루트 안인지 다시 확인한다.
class ExdataFileService {
  static const int defaultMaxUploadBytes = 2 * 1024 * 1024 * 1024;
  static const int maxUploadChunkBytes = 768 * 1024;
  static const Duration abandonedUploadRetention = Duration(hours: 24);
  static final RegExp _uploadIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,80}$');
  static final RegExp _directTemporaryPattern = RegExp(r'\.upload-\d+-\d+$');

  final String rootPath;
  final int maxUploadBytes;
  final Random _random = Random.secure();
  Future<void>? _ready;

  ExdataFileService(
      {String? rootPath, this.maxUploadBytes = defaultMaxUploadBytes})
      : rootPath = rootPath ?? RuntimePaths.exdata ?? '';

  bool get supported => rootPath.isNotEmpty;

  Future<void> ensureReady() => _ready ??= _initialize();

  Future<void> _initialize() async {
    if (!supported) return;
    await Directory(rootPath).create(recursive: true);
    await cleanupAbandonedUploads();
  }

  Future<int> cleanupAbandonedUploads({
    Duration maxAge = abandonedUploadRetention,
    DateTime? now,
  }) async {
    if (!supported) return 0;
    final root = Directory(rootPath);
    if (!await root.exists()) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    var removed = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !_isTemporaryUploadName(_basename(entity.path))) {
        continue;
      }
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } on FileSystemException {
        // Another upload request may have completed or removed the file.
      }
    }
    return removed;
  }

  Future<ExdataDirectoryListing> list(String relativePath) async {
    final normalized = normalizeRelativePath(relativePath, allowRoot: true);
    final directory = Directory(_join(normalized));
    await _requireWithinRoot(directory, mustExist: true);
    if (!await directory.exists()) {
      throw const ExdataFileException(
          404, 'directory-not-found', '폴더를 찾을 수 없습니다.');
    }

    final entries = <ExdataFileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link ||
          (type != FileSystemEntityType.file &&
              type != FileSystemEntityType.directory)) {
        continue;
      }
      final stat = await entity.stat();
      final name = _basename(entity.path);
      if (_isTemporaryUploadName(name)) continue;
      entries.add(ExdataFileEntry(
        name: name,
        path: normalized.isEmpty ? name : '$normalized/$name',
        isDirectory: type == FileSystemEntityType.directory,
        size: type == FileSystemEntityType.file ? stat.size : null,
        modifiedAt: stat.modified,
      ));
    }
    entries.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return ExdataDirectoryListing(path: normalized, entries: entries);
  }

  Future<void> createDirectory(String relativePath) async {
    final normalized = normalizeRelativePath(relativePath);
    final directory = Directory(_join(normalized));
    await _requireSafeParent(directory.parent);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const ExdataFileException(
          409, 'already-exists', '같은 이름의 항목이 이미 있습니다.');
    }
    await directory.create();
  }

  Future<void> move(String sourcePath, String destinationPath) async {
    final source = normalizeRelativePath(sourcePath);
    final destination = normalizeRelativePath(destinationPath);
    if (source == destination) return;

    final sourceEntity =
        FileSystemEntity.typeSync(_join(source), followLinks: false);
    if (sourceEntity == FileSystemEntityType.notFound) {
      throw const ExdataFileException(404, 'not-found', '이동할 항목을 찾을 수 없습니다.');
    }
    if (sourceEntity == FileSystemEntityType.link) {
      throw const ExdataFileException(
          400, 'link-not-supported', '링크 항목은 관리할 수 없습니다.');
    }
    await _requireWithinRoot(
      sourceEntity == FileSystemEntityType.directory
          ? Directory(_join(source))
          : File(_join(source)),
      mustExist: true,
    );

    final destinationEntity = FileSystemEntity.typeSync(
      _join(destination),
      followLinks: false,
    );
    if (destinationEntity != FileSystemEntityType.notFound) {
      throw const ExdataFileException(
          409, 'already-exists', '같은 이름의 항목이 이미 있습니다.');
    }
    await _requireSafeParent(Directory(_dirname(_join(destination))));

    if (sourceEntity == FileSystemEntityType.directory) {
      await Directory(_join(source)).rename(_join(destination));
    } else {
      await File(_join(source)).rename(_join(destination));
    }
  }

  Future<void> delete(String relativePath) async {
    final normalized = normalizeRelativePath(relativePath);
    final path = _join(normalized);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const ExdataFileException(404, 'not-found', '삭제할 항목을 찾을 수 없습니다.');
    }
    if (type == FileSystemEntityType.link) {
      throw const ExdataFileException(
          400, 'link-not-supported', '링크 항목은 관리할 수 없습니다.');
    }
    final entity =
        type == FileSystemEntityType.directory ? Directory(path) : File(path);
    await _requireWithinRoot(entity, mustExist: true);
    await entity.delete(recursive: type == FileSystemEntityType.directory);
  }

  Future<ExdataDownload> openDownload(String relativePath) async {
    final normalized = normalizeRelativePath(relativePath);
    final file = File(_join(normalized));
    await _requireWithinRoot(file, mustExist: true);
    if (!await file.exists()) {
      throw const ExdataFileException(404, 'file-not-found', '파일을 찾을 수 없습니다.');
    }
    return ExdataDownload(
      file: file,
      name: _basename(file.path),
      size: await file.length(),
    );
  }

  Future<int> upload(
    String relativePath,
    Stream<List<int>> content, {
    required bool overwrite,
    int? contentLength,
  }) async {
    final normalized = normalizeRelativePath(relativePath);
    if (contentLength != null && contentLength > maxUploadBytes) {
      throw const ExdataFileException(
          413, 'file-too-large', '업로드 파일이 허용 크기를 초과했습니다.');
    }

    final destination = File(_join(normalized));
    await _requireSafeParent(destination.parent);
    final existingType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (existingType == FileSystemEntityType.directory ||
        existingType == FileSystemEntityType.link) {
      throw const ExdataFileException(
          409, 'already-exists', '같은 이름의 폴더 또는 링크가 있습니다.');
    }
    if (existingType == FileSystemEntityType.file && !overwrite) {
      throw const ExdataFileException(
          409, 'already-exists', '같은 이름의 파일이 이미 있습니다.');
    }

    final temporary = File(
      '${destination.path}.upload-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
    );
    var written = 0;
    IOSink? sink;
    try {
      sink = temporary.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in content) {
        written += chunk.length;
        if (written > maxUploadBytes) {
          throw const ExdataFileException(
              413, 'file-too-large', '업로드 파일이 허용 크기를 초과했습니다.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      return written;
    } finally {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Appends one proxy-safe upload chunk and atomically exposes the file only
  /// after the final chunk has arrived.
  Future<ExdataChunkUploadResult> uploadChunk(
    String relativePath,
    String uploadId,
    int offset,
    Stream<List<int>> content, {
    required bool overwrite,
    required bool complete,
    int? contentLength,
  }) async {
    final normalized = normalizeRelativePath(relativePath);
    if (!_uploadIdPattern.hasMatch(uploadId)) {
      throw const ExdataFileException(
        400,
        'invalid-upload-id',
        '올바르지 않은 업로드 ID입니다.',
      );
    }
    if (offset < 0 || offset > maxUploadBytes) {
      throw const ExdataFileException(
        400,
        'invalid-upload-offset',
        '올바르지 않은 업로드 위치입니다.',
      );
    }
    if (contentLength != null &&
        (contentLength > maxUploadChunkBytes ||
            offset + contentLength > maxUploadBytes)) {
      throw const ExdataFileException(
        413,
        'file-too-large',
        '업로드 파일의 허용 크기를 초과했습니다.',
      );
    }

    final destination = File(_join(normalized));
    await _requireSafeParent(destination.parent);
    final temporary = File('${destination.path}.ys-upload-$uploadId');

    if (offset == 0) {
      final existingType = await FileSystemEntity.type(
        destination.path,
        followLinks: false,
      );
      if (existingType == FileSystemEntityType.directory ||
          existingType == FileSystemEntityType.link) {
        throw const ExdataFileException(
          409,
          'already-exists',
          '같은 이름의 폴더 또는 링크가 있습니다.',
        );
      }
      if (existingType == FileSystemEntityType.file && !overwrite) {
        throw const ExdataFileException(
          409,
          'already-exists',
          '같은 이름의 파일이 이미 있습니다.',
        );
      }
      if (await temporary.exists()) await temporary.delete();
    } else {
      if (!await temporary.exists() || await temporary.length() != offset) {
        throw const ExdataFileException(
          409,
          'upload-offset-mismatch',
          '업로드 위치가 일치하지 않습니다. 처음부터 다시 시도해 주세요.',
        );
      }
    }

    var written = 0;
    IOSink? sink;
    try {
      sink = temporary.openWrite(
        mode: offset == 0 ? FileMode.writeOnly : FileMode.append,
      );
      await for (final chunk in content) {
        written += chunk.length;
        if (written > maxUploadChunkBytes ||
            offset + written > maxUploadBytes) {
          throw const ExdataFileException(
            413,
            'file-too-large',
            '업로드 파일의 허용 크기를 초과했습니다.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final total = offset + written;
      if (complete) {
        final existingType = await FileSystemEntity.type(
          destination.path,
          followLinks: false,
        );
        if (existingType == FileSystemEntityType.file) {
          if (!overwrite) {
            throw const ExdataFileException(
              409,
              'already-exists',
              '같은 이름의 파일이 이미 있습니다.',
            );
          }
          await destination.delete();
        } else if (existingType != FileSystemEntityType.notFound) {
          throw const ExdataFileException(
            409,
            'already-exists',
            '같은 이름의 폴더 또는 링크가 있습니다.',
          );
        }
        await temporary.rename(destination.path);
      }
      return ExdataChunkUploadResult(size: total, complete: complete);
    } catch (_) {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static String normalizeRelativePath(
    String value, {
    bool allowRoot = false,
  }) {
    if (value.contains('\u0000')) {
      throw const ExdataFileException(400, 'invalid-path', '올바르지 않은 경로입니다.');
    }
    var path = value.replaceAll('\\', '/');
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    path = path.replaceAll(RegExp('/+'), '/');
    if (path == '.' || path.isEmpty) {
      if (allowRoot) return '';
      throw const ExdataFileException(
          400, 'invalid-path', '파일 또는 폴더 이름이 필요합니다.');
    }
    if (path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path) ||
        path.startsWith('//')) {
      throw const ExdataFileException(
          400, 'absolute-path', '절대경로는 사용할 수 없습니다.');
    }

    final segments = path.split('/');
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw const ExdataFileException(
            400, 'path-traversal', '상위 폴더로 이동하는 경로는 사용할 수 없습니다.');
      }
      if (RegExp(r'[<>:"|?*\x00-\x1F]').hasMatch(segment) ||
          segment.contains('.ys-upload-') ||
          segment.endsWith('.') ||
          segment.endsWith(' ')) {
        throw const ExdataFileException(
            400, 'invalid-name', 'Windows에서 사용할 수 없는 파일 이름입니다.');
      }
      final stem = segment.split('.').first.toUpperCase();
      if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
        throw const ExdataFileException(
            400, 'invalid-name', 'Windows 예약 이름은 사용할 수 없습니다.');
      }
    }
    return segments.join('/');
  }

  Future<void> _requireSafeParent(Directory parent) async {
    if (!await parent.exists()) {
      throw const ExdataFileException(
          404, 'parent-not-found', '상위 폴더를 찾을 수 없습니다.');
    }
    await _requireWithinRoot(parent, mustExist: true);
  }

  Future<void> _requireWithinRoot(
    FileSystemEntity entity, {
    required bool mustExist,
  }) async {
    await ensureReady();
    final root = await Directory(rootPath).resolveSymbolicLinks();
    String resolved;
    try {
      resolved = await entity.resolveSymbolicLinks();
    } on FileSystemException {
      if (!mustExist) return;
      throw const ExdataFileException(404, 'not-found', '경로를 찾을 수 없습니다.');
    }
    if (!_isWithin(root, resolved)) {
      throw const ExdataFileException(
          403, 'outside-root', 'exdata 폴더 밖에는 접근할 수 없습니다.');
    }
  }

  bool _isWithin(String root, String candidate) {
    var normalizedRoot = Directory(root).absolute.path;
    var normalizedCandidate = File(candidate).absolute.path;
    if (Platform.isWindows) {
      normalizedRoot = normalizedRoot.toLowerCase();
      normalizedCandidate = normalizedCandidate.toLowerCase();
    }
    return normalizedCandidate == normalizedRoot ||
        normalizedCandidate
            .startsWith('$normalizedRoot${Platform.pathSeparator}');
  }

  String _join(String relative) {
    if (!supported) {
      throw const ExdataFileException(
        501,
        'not-supported',
        'exdata 파일 관리는 Windows에서 지원됩니다.',
      );
    }
    return relative.isEmpty
        ? Directory(rootPath).absolute.path
        : '${Directory(rootPath).absolute.path}${Platform.pathSeparator}'
            '${relative.replaceAll('/', Platform.pathSeparator)}';
  }

  String _basename(String path) => path.split(Platform.pathSeparator).last;

  static bool _isTemporaryUploadName(String name) =>
      name.contains('.ys-upload-') || _directTemporaryPattern.hasMatch(name);

  String _dirname(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index <= 0
        ? Directory(rootPath).absolute.path
        : path.substring(0, index);
  }
}
