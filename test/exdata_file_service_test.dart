import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/exdata_file_service.dart';

void main() {
  late Directory temporary;
  late ExdataFileService service;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('exdata-service-test-');
    service = ExdataFileService(
      rootPath: '${temporary.path}${Platform.pathSeparator}exdata',
      maxUploadBytes: 1024,
    );
    await service.ensureReady();
  });

  tearDown(() => temporary.delete(recursive: true));

  test('exdata 안에서 폴더·업로드·목록·이름 변경·다운로드·삭제를 처리한다', () async {
    await service.createDirectory('photos');
    final written = await service.upload(
      'photos/welcome.txt',
      Stream.value('hello'.codeUnits),
      overwrite: false,
      contentLength: 5,
    );
    expect(written, 5);

    final listing = await service.list('photos');
    expect(listing.path, 'photos');
    expect(listing.entries.single.name, 'welcome.txt');
    expect(listing.entries.single.size, 5);

    await service.move('photos/welcome.txt', 'photos/renamed.txt');
    final download = await service.openDownload('photos/renamed.txt');
    expect(await download.file.readAsString(), 'hello');

    await service.delete('photos');
    expect((await service.list('')).entries, isEmpty);
  });

  test('기존 파일 덮어쓰기에는 명시적인 허용이 필요하다', () async {
    await service.upload(
      'same.txt',
      Stream.value([1]),
      overwrite: false,
      contentLength: 1,
    );

    expect(
      () => service.upload(
        'same.txt',
        Stream.value([2]),
        overwrite: false,
        contentLength: 1,
      ),
      throwsA(isA<ExdataFileException>().having(
        (error) => error.statusCode,
        'statusCode',
        409,
      )),
    );

    await service.upload(
      'same.txt',
      Stream.value([2]),
      overwrite: true,
      contentLength: 1,
    );
    expect(
      await File(
        '${service.rootPath}${Platform.pathSeparator}same.txt',
      ).readAsBytes(),
      [2],
    );
  });

  test('상위·절대·와일드카드 경로와 용량 초과 업로드를 차단한다', () async {
    for (final path in [
      '../outside.txt',
      '/outside.txt',
      r'C:\outside.txt',
      'bad*.txt',
      'CON.txt',
    ]) {
      expect(
        () => ExdataFileService.normalizeRelativePath(path),
        throwsA(isA<ExdataFileException>()),
      );
    }

    expect(
      () => service.upload(
        'large.bin',
        Stream.value(List<int>.filled(1025, 0)),
        overwrite: false,
        contentLength: 1025,
      ),
      throwsA(isA<ExdataFileException>().having(
        (error) => error.statusCode,
        'statusCode',
        413,
      )),
    );
  });

  test('분할 업로드는 마지막 조각을 받은 뒤에만 파일을 공개한다', () async {
    const uploadId = 'upload_test_1234';
    final first = await service.uploadChunk(
      'chunked.json',
      uploadId,
      0,
      Stream.value([1, 2, 3]),
      overwrite: false,
      complete: false,
      contentLength: 3,
    );
    expect(first.size, 3);
    expect(first.complete, isFalse);
    expect(() => service.openDownload('chunked.json'),
        throwsA(isA<ExdataFileException>()));
    expect((await service.list('')).entries, isEmpty);

    final last = await service.uploadChunk(
      'chunked.json',
      uploadId,
      3,
      Stream.value([4, 5]),
      overwrite: false,
      complete: true,
      contentLength: 2,
    );
    expect(last.size, 5);
    expect(last.complete, isTrue);
    expect((await service.openDownload('chunked.json')).file.readAsBytes(),
        completion([1, 2, 3, 4, 5]));
  });

  test('분할 업로드 위치가 다르면 요청을 거절한다', () async {
    const uploadId = 'upload_test_5678';
    await service.uploadChunk(
      'broken.bin',
      uploadId,
      0,
      Stream.value([1, 2]),
      overwrite: false,
      complete: false,
    );

    expect(
      () => service.uploadChunk(
        'broken.bin',
        uploadId,
        1,
        Stream.value([3]),
        overwrite: false,
        complete: true,
      ),
      throwsA(isA<ExdataFileException>().having(
        (error) => error.code,
        'code',
        'upload-offset-mismatch',
      )),
    );
  });

  test('현재 설정의 exdata 파일과 폴더 참조를 찾는다', () {
    final references = findExdataConfigReferences({
      'idle': {
        'image': r'exdata\welcome.jpg',
        'folder': {
          'paths': ['exdata/gallery/'],
        },
      },
      'unrelated': 'assets/idle/default.jpg',
    });

    expect(references.map((value) => value.relativePath),
        ['welcome.jpg', 'gallery']);
    expect(references.map((value) => value.settingPath),
        ['idle.image', 'idle.folder.paths[0]']);
    expect(references[0].isAffectedBy('welcome.jpg'), isTrue);
    expect(references[1].isAffectedBy('gallery/child.jpg'), isTrue);
    expect(references[1].isAffectedBy('other.jpg'), isFalse);
  });

  test('last-good 설정에 저장된 절대 exdata 경로도 사용 중으로 찾는다', () {
    final absolute = '${service.rootPath}${Platform.pathSeparator}photos'
        '${Platform.pathSeparator}welcome.jpg';
    final references = findExdataConfigReferences(
      {
        'idle': {'image': absolute},
      },
      exdataRootPath: service.rootPath,
    );

    expect(references, hasLength(1));
    expect(references.single.relativePath, 'photos/welcome.jpg');
    expect(references.single.isAffectedBy('photos'), isTrue);
  });

  test('24시간이 지난 중단 업로드 임시 파일을 정리하고 목록에서 숨긴다', () async {
    final now = DateTime(2026, 8, 28, 12);
    final oldChunk = File(
      '${service.rootPath}${Platform.pathSeparator}old.bin.ys-upload-oldupload1',
    );
    final recentChunk = File(
      '${service.rootPath}${Platform.pathSeparator}recent.bin.ys-upload-recent01',
    );
    final oldDirect = File(
      '${service.rootPath}${Platform.pathSeparator}old.json.upload-123-456',
    );
    await oldChunk.writeAsBytes([1]);
    await recentChunk.writeAsBytes([2]);
    await oldDirect.writeAsBytes([3]);
    await oldChunk.setLastModified(now.subtract(const Duration(hours: 25)));
    await oldDirect.setLastModified(now.subtract(const Duration(days: 2)));
    await recentChunk.setLastModified(now.subtract(const Duration(hours: 1)));

    expect(await service.cleanupAbandonedUploads(now: now), 2);
    expect(await oldChunk.exists(), isFalse);
    expect(await oldDirect.exists(), isFalse);
    expect(await recentChunk.exists(), isTrue);
    expect((await service.list('')).entries, isEmpty);
  });
}
