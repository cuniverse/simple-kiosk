import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/runtime_paths.dart';

void main() {
  test('atomicWrite는 기존 파일을 유지한 채 교체하고 임시 파일을 남기지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp('atomic-write-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File(
      '${directory.path}${Platform.pathSeparator}settings.json',
    );
    await target.writeAsString('old');

    await RuntimePaths.atomicWrite(target.path, 'new');

    expect(await target.readAsString(), 'new');
    expect(
      await directory
          .list()
          .where((entity) => entity.path.contains('.tmp-'))
          .isEmpty,
      isTrue,
    );
  });

  test('동시 atomicWrite도 완성된 내용 하나만 남긴다', () async {
    final directory = await Directory.systemTemp.createTemp('atomic-race-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File(
      '${directory.path}${Platform.pathSeparator}settings.json',
    );
    final values = List.generate(12, (index) => 'value-$index');

    await Future.wait(
      values.map((value) => RuntimePaths.atomicWrite(target.path, value)),
    );

    expect(values, contains(await target.readAsString()));
    expect(
      await directory
          .list()
          .where((entity) => entity.path.contains('.tmp-'))
          .isEmpty,
      isTrue,
    );
  });
}
