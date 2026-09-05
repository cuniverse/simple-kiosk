import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../model/update_manifest.dart';
import 'exdata_file_service.dart';
import 'runtime_paths.dart';

class UploadedUpdate {
  final File file;
  final UpdateManifest manifest;
  const UploadedUpdate(this.file, this.manifest);
}

/// Separate from exdata: uploaded executable packages are never publicly served.
class ManualUpdateService {
  final ExdataFileService _files;
  final Map<String, UploadedUpdate> _ready = {};
  final Set<String> _sealed = {};
  bool _busy = false;

  ManualUpdateService({String? rootPath})
      : _files = ExdataFileService(
          rootPath:
              rootPath ?? RuntimePaths.child('downloads/manual-upload') ?? '',
        );

  Future<Map<String, dynamic>> upload({
    required String filename,
    required String uploadId,
    required int offset,
    required int total,
    required bool complete,
    required Stream<List<int>> content,
    int? contentLength,
  }) async {
    if (_busy || _sealed.contains(uploadId)) {
      throw const ExdataFileException(
          409, 'upload-busy', '진행 중이거나 완료된 업로드입니다. 새로 업로드해 주세요.');
    }
    final version = versionFromFilename(filename);
    if (total < 1 ||
        total > _files.maxUploadBytes ||
        offset < 0 ||
        offset >= total) {
      throw const FormatException('ZIP 크기 또는 업로드 위치가 올바르지 않습니다. (최대 2GB)');
    }
    _busy = true;
    try {
      await _files.ensureReady();
      final path = '$uploadId-$filename';
      final result = await _files.uploadChunk(path, uploadId, offset, content,
          overwrite: false, complete: complete, contentLength: contentLength);
      if (result.size > total || (complete && result.size != total)) {
        if (complete) await _files.delete(path);
        throw const FormatException('업로드한 ZIP 크기가 일치하지 않습니다. 다시 업로드해 주세요.');
      }
      if (!complete) {
        return {'ok': true, 'size': result.size, 'complete': false};
      }
      _sealed.add(uploadId);
      final file = (await _files.openDownload(path)).file;
      try {
        final filePath = file.path;
        await Isolate.run(() => validateUploadedArchive(filePath, filename));
        final hash = (await sha256.bind(file.openRead()).first).toString();
        _ready[uploadId] = UploadedUpdate(
            file,
            UpdateManifest(
              version: version,
              channel: 'stable',
              packageFile: filename,
              sha256: hash,
            ));
        return {
          'ok': true,
          'complete': true,
          'uploadId': uploadId,
          'version': version,
          'size': result.size,
          'sha256': hash
        };
      } catch (_) {
        await _files.delete(path);
        rethrow;
      }
    } finally {
      _busy = false;
    }
  }

  UploadedUpdate prepared(String uploadId) {
    final update = _ready[uploadId];
    if (update == null) {
      throw const ExdataFileException(
          404, 'upload-not-ready', '검증을 마친 ZIP을 먼저 업로드해 주세요.');
    }
    return update;
  }

  void markInstalling(String uploadId) => _ready.remove(uploadId);

  static String versionFromFilename(String name) {
    final match = RegExp(
            r'^simple-kiosk-windows-(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\.zip$')
        .firstMatch(name);
    if (match == null || name.contains('..')) {
      throw const FormatException(
          '릴리스의 simple-kiosk-windows-버전.zip 파일을 선택하세요.');
    }
    final version = match.group(1)!;
    SemanticVersion.parse(version);
    return version;
  }
}

/// Reads ZIP headers without decompressing untrusted entries in the UI isolate.
void validateUploadedArchive(String path, String filename) {
  final input = InputFileStream(path);
  try {
    final directory = ZipDirectory()..read(input);
    final names = <String>{};
    final files = <String>{};
    final root = filename.substring(0, filename.length - 4);
    var expandedBytes = 0;
    if (directory.fileHeaders.isEmpty || directory.fileHeaders.length > 50000) {
      throw const FormatException('ZIP 항목 수가 올바르지 않습니다.');
    }
    for (final header in directory.fileHeaders) {
      final name = header.filename.replaceAll('\\', '/');
      final parts = name.split('/');
      if (header.uncompressedSize > 0 && !name.endsWith('/')) {
        files.add(name.toLowerCase());
      }
      expandedBytes += header.uncompressedSize;
      if (parts.first != root ||
          name.contains('//') ||
          parts.any((part) =>
              part == '..' ||
              part == '.' ||
              part.contains(RegExp(r'[\x00-\x1f:<>"|?*]')) ||
              part.endsWith(' ') ||
              part.endsWith('.') ||
              RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
                      caseSensitive: false)
                  .hasMatch(part)) ||
          !names.add(name.toLowerCase()) ||
          (header.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
          header.generalPurposeBitFlag & 1 != 0 ||
          header.file?.filename.replaceAll('\\', '/') != name ||
          expandedBytes > 4 * 1024 * 1024 * 1024) {
        throw const FormatException('ZIP 경로·구성·압축 해제 크기가 올바르지 않습니다.');
      }
    }
    for (final required in [
      'ysignage.exe',
      'ysignage_launcher.exe',
      'flutter_windows.dll',
      'data/app.so',
    ]) {
      if (!files.contains('$root/$required'.toLowerCase())) {
        throw FormatException('Windows 릴리스 ZIP의 필수 파일이 없습니다: $required');
      }
    }
    if (!files.contains('$root/updater/ysignage_updater.exe'.toLowerCase()) &&
        !files.contains(
            '$root/updater/payload/ysignage_updater.exe'.toLowerCase())) {
      throw const FormatException('Windows 릴리스 ZIP에 네이티브 업데이터가 없습니다.');
    }
  } finally {
    input.closeSync();
  }
}
