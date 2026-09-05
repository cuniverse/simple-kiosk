import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/exdata_file_service.dart';
import 'package:simple_kiosk/service/manual_update_service.dart';

List<int> releaseZip(
    {String? extraPath, bool missingApp = false, bool payload = false}) {
  const root = 'simple-kiosk-windows-1.2.36';
  final archive = Archive();
  for (final name in [
    if (!missingApp) 'ysignage.exe',
    'ysignage_launcher.exe',
    'flutter_windows.dll',
    'data/app.so',
    payload
        ? 'updater/payload/ysignage_updater.exe'
        : 'updater/ysignage_updater.exe',
    if (extraPath != null) extraPath,
  ]) {
    archive.addFile(ArchiveFile('$root/$name', 3, [1, 2, 3]));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  const name = 'simple-kiosk-windows-1.2.36.zip';
  const id = 'test-upload-123';
  late Directory directory;
  late ManualUpdateService service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('manual-update-test-');
    service = ManualUpdateService(rootPath: directory.path);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
      'chunked ZIP is prepared only on completion, without downloading a manifest',
      () async {
    final bytes = releaseZip();
    final half = bytes.length ~/ 2;
    final partial = await service.upload(
        filename: name,
        uploadId: id,
        offset: 0,
        total: bytes.length,
        complete: false,
        content: Stream.value(bytes.sublist(0, half)));
    expect(partial['complete'], isFalse);
    expect(() => service.prepared(id), throwsA(isA<ExdataFileException>()));
    final complete = await service.upload(
        filename: name,
        uploadId: id,
        offset: half,
        total: bytes.length,
        complete: true,
        content: Stream.value(bytes.sublist(half)));
    expect(complete['version'], '1.2.36');
    expect(complete['sha256'], sha256.convert(bytes).toString());
    expect(await service.prepared(id).file.readAsBytes(), bytes);
    service.markInstalling(id);
    expect(() => service.prepared(id), throwsA(isA<ExdataFileException>()));
    await expectLater(
        service.upload(
            filename: name,
            uploadId: id,
            offset: 0,
            total: bytes.length,
            complete: true,
            content: Stream.value(bytes)),
        throwsA(isA<ExdataFileException>()));
  });

  for (final bad in [
    '../outside.exe',
    'data/CON.txt',
    'data/file:stream',
    'data/../app.so'
  ]) {
    test('rejects unsafe ZIP entry $bad and removes completed upload',
        () async {
      final bytes = releaseZip(extraPath: bad);
      await expectLater(
          service.upload(
              filename: name,
              uploadId: id,
              offset: 0,
              total: bytes.length,
              complete: true,
              content: Stream.value(bytes)),
          throwsFormatException);
      expect(() => service.prepared(id), throwsA(isA<ExdataFileException>()));
      expect(await directory.list().toList(), isEmpty);
    });
  }

  test('rejects incomplete runtime package', () async {
    final bytes = releaseZip(missingApp: true);
    await expectLater(
        service.upload(
            filename: name,
            uploadId: id,
            offset: 0,
            total: bytes.length,
            complete: true,
            content: Stream.value(bytes)),
        throwsFormatException);
  });

  test('accepts the current release updater payload layout', () async {
    final bytes = releaseZip(payload: true);
    final result = await service.upload(
        filename: name,
        uploadId: id,
        offset: 0,
        total: bytes.length,
        complete: true,
        content: Stream.value(bytes));
    expect(result['complete'], isTrue);
  });

  test('rejects wrong chunk offsets and declared file size', () async {
    final bytes = releaseZip();
    await expectLater(
        service.upload(
            filename: name,
            uploadId: id,
            offset: 5,
            total: bytes.length,
            complete: true,
            content: Stream.value(bytes)),
        throwsA(isA<ExdataFileException>()));
    await expectLater(
        service.upload(
            filename: name,
            uploadId: id,
            offset: 0,
            total: bytes.length + 1,
            complete: true,
            content: Stream.value(bytes)),
        throwsFormatException);
    expect(() => service.prepared(id), throwsA(isA<ExdataFileException>()));
  });

  test('rejects upload ID traversal and non-release ZIP names', () async {
    expect(() => ManualUpdateService.versionFromFilename('../1.2.36.zip'),
        throwsFormatException);
    expect(() => ManualUpdateService.versionFromFilename('Source code.zip'),
        throwsFormatException);
    final bytes = releaseZip();
    await expectLater(
        service.upload(
            filename: name,
            uploadId: '../traversal',
            offset: 0,
            total: bytes.length,
            complete: true,
            content: Stream.value(bytes)),
        throwsA(isA<ExdataFileException>()));
  });
}
