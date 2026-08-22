import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:win32/win32.dart';

const nativeUpdaterVersion = '2.0.0';

Future<void> main(List<String> arguments) async {
  if (!Platform.isWindows) {
    exitCode = 2;
    return;
  }
  try {
    final options = NativeUpdateOptions.parse(arguments);
    await NativeUpdateInstaller(options).run();
  } catch (_) {
    // 배포 파일은 GUI 서브시스템으로 실행되어 콘솔을 만들지 않는다.
    // 세부 오류는 NativeUpdateInstaller가 update-state.json과 로그에 기록한다.
    exitCode = 1;
  }
}

class NativeUpdateOptions {
  final String packagePath;
  final String version;
  final String expectedSha256;
  final int appPid;
  final String dataRoot;
  final int retainVersions;
  final int logRetentionDays;
  final bool requireAuthenticode;
  final String? expectedSignerThumbprint;
  final String signatureVerifierPath;

  const NativeUpdateOptions({
    required this.packagePath,
    required this.version,
    required this.expectedSha256,
    required this.appPid,
    required this.dataRoot,
    required this.retainVersions,
    required this.logRetentionDays,
    required this.requireAuthenticode,
    required this.expectedSignerThumbprint,
    required this.signatureVerifierPath,
  });

  factory NativeUpdateOptions.parse(List<String> arguments) {
    final values = <String, String>{};
    var requireAuthenticode = false;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--require-authenticode') {
        requireAuthenticode = true;
        continue;
      }
      if (!argument.startsWith('--') || index + 1 >= arguments.length) {
        throw FormatException('잘못된 업데이트 인수: $argument');
      }
      values[argument] = arguments[++index];
    }

    String requiredValue(String name) {
      final value = values[name]?.trim();
      if (value == null || value.isEmpty) {
        throw FormatException('필수 업데이트 인수가 없습니다: $name');
      }
      return value;
    }

    int rangedInt(String name, int minimum, int maximum) {
      final value = int.tryParse(requiredValue(name));
      if (value == null || value < minimum || value > maximum) {
        throw FormatException('$name 값은 $minimum~$maximum 범위여야 합니다.');
      }
      return value;
    }

    final version = requiredValue('--version');
    if (!RegExp(r'^[0-9A-Za-z.+-]+$').hasMatch(version) ||
        version.contains('..')) {
      throw FormatException('안전하지 않은 버전 값입니다: $version');
    }
    final expectedSha256 = requiredValue('--sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw const FormatException('SHA-256 값 형식이 올바르지 않습니다.');
    }
    final thumbprint = values['--signer-thumbprint']
        ?.replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (requireAuthenticode &&
        (thumbprint == null ||
            !RegExp(r'^[0-9A-F]{40,64}$').hasMatch(thumbprint))) {
      throw const FormatException('서명 검증용 인증서 지문이 필요합니다.');
    }

    return NativeUpdateOptions(
      packagePath: requiredValue('--package'),
      version: version,
      expectedSha256: expectedSha256,
      appPid: rangedInt('--app-pid', 1, 0x7fffffff),
      dataRoot: requiredValue('--data-root'),
      retainVersions: rangedInt('--retain-versions', 2, 10),
      logRetentionDays: rangedInt('--log-retention-days', 1, 365),
      requireAuthenticode: requireAuthenticode,
      expectedSignerThumbprint: thumbprint,
      signatureVerifierPath: requiredValue('--signature-verifier'),
    );
  }
}

bool isSafeArchiveEntry(String name) {
  final normalized = name.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.contains('\u0000') ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    return false;
  }
  final parts = normalized.split('/').where((part) => part.isNotEmpty);
  for (final part in parts) {
    if (part == '..' || part.contains(':')) return false;
    final deviceName = part.split('.').first.toUpperCase();
    if (const {'CON', 'PRN', 'AUX', 'NUL'}.contains(deviceName) ||
        RegExp(r'^(COM|LPT)[1-9]$').hasMatch(deviceName)) {
      return false;
    }
  }
  return true;
}

class NativeUpdateInstaller {
  final NativeUpdateOptions options;

  late final Directory _root = Directory(options.dataRoot).absolute;
  late final File _logFile = File(_join(_root.path, 'logs', 'updater.log'));
  late final File _stateFile =
      File(_join(_root.path, 'state', 'update-state.json'));
  late final File _pointerFile = File(_join(_root.path, 'current.json'));

  NativeUpdateInstaller(this.options);

  Future<void> run() async {
    Directory(_join(_root.path, 'logs')).createSync(recursive: true);
    Directory(_join(_root.path, 'state')).createSync(recursive: true);
    await _rotateLog();
    Directory? temporary;
    try {
      final previousState = await _readJson(_stateFile);
      if (previousState?['version'] == options.version &&
          _asInt(previousState?['failureCount']) >= 3) {
        throw StateError('세 번 설치에 실패한 버전이므로 자동 설치를 차단했습니다.');
      }
      await _verifyPackage();
      temporary = await Directory(
        _join(
          _root.path,
          'downloads',
          'extract-${DateTime.now().microsecondsSinceEpoch}-$pid',
        ),
      ).create(recursive: true);
      final packageRoot = await _extractPackage(temporary);
      final executable = _applicationExecutable(packageRoot);
      if (executable == null ||
          !Directory(_join(packageRoot.path, 'data')).existsSync()) {
        throw const FormatException(
          '업데이트 패키지에 ysignage.exe 또는 data 폴더가 없습니다.',
        );
      }
      await _verifyAuthenticode(executable);

      // 앱은 이 신호를 확인한 뒤에만 종료한다. 패키지 검증을 먼저 끝내야
      // 손상되거나 신뢰할 수 없는 패키지 때문에 현재 앱까지 종료되지 않는다.
      await _writeState('installing');
      await _waitForApplication();

      final versionsRoot = await Directory(_join(_root.path, 'versions'))
          .create(recursive: true);
      final versionRoot = Directory(_join(versionsRoot.path, options.version));
      if (versionRoot.existsSync()) versionRoot.deleteSync(recursive: true);
      await packageRoot.rename(versionRoot.path);

      final previous = await _currentVersion();
      await _synchronizeRuntimeFiles(versionRoot);
      await _writePointer(options.version, previous);
      final appState = File(_join(_root.path, 'state', 'app-state.json'));
      if (appState.existsSync()) appState.deleteSync();
      await _launchCurrent();

      if (!await _waitForReady(options.version)) {
        await _log(
          'Version ${options.version} health check failed; rolling back to $previous',
        );
        if (previous == null || previous.isEmpty) {
          throw StateError('정상 실행 확인에 실패했고 복구할 이전 버전이 없습니다.');
        }
        await _writePointer(previous, options.version);
        await _launchCurrent();
        throw StateError('새 버전 정상 실행 확인 실패로 이전 버전을 복구했습니다.');
      }

      await _removeLegacyLaunchers();
      await _writeState('installed');
      await _log('Version ${options.version} installed successfully');
      await _maintenance(options.version, previous);
    } catch (error) {
      await _writeState('failed', error: '$error');
      await _log('FAILED: $error');
      rethrow;
    } finally {
      if (temporary != null && temporary.existsSync()) {
        temporary.deleteSync(recursive: true);
      }
    }
  }

  Future<void> _verifyPackage() async {
    final package = File(options.packagePath);
    if (!package.existsSync()) throw StateError('업데이트 ZIP을 찾을 수 없습니다.');
    final actual = await sha256.bind(package.openRead()).first;
    if (actual.toString().toLowerCase() != options.expectedSha256) {
      throw const FormatException('업데이트 ZIP SHA-256이 일치하지 않습니다.');
    }
  }

  Future<void> _waitForApplication() async {
    final handle = OpenProcess(SYNCHRONIZE, FALSE, options.appPid);
    if (handle == 0) return;
    try {
      await _log('Waiting for app PID ${options.appPid}');
      final result = WaitForSingleObject(handle, 30000);
      if (result == WAIT_TIMEOUT) {
        throw TimeoutException('프로그램이 30초 이내 종료되지 않았습니다.');
      }
      if (result != WAIT_OBJECT_0) {
        throw StateError('프로그램 종료 대기 실패: $result');
      }
    } finally {
      CloseHandle(handle);
    }
  }

  Future<Directory> _extractPackage(Directory temporary) async {
    final input = InputFileStream(options.packagePath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        if (!isSafeArchiveEntry(entry.name) || entry.isSymbolicLink) {
          throw FormatException('안전하지 않은 ZIP 항목을 거부했습니다: ${entry.name}');
        }
      }
      await extractArchiveToDisk(archive, temporary.path);
    } finally {
      input.closeSync();
    }
    final children = temporary.listSync(followLinks: false);
    final directories = children.whereType<Directory>().toList();
    if (children.length == 1 && directories.length == 1) {
      return directories.single;
    }
    return temporary;
  }

  File? _applicationExecutable(Directory packageRoot) {
    for (final name in const ['ysignage.exe', 'simple_kiosk.exe']) {
      final candidate = File(_join(packageRoot.path, name));
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }

  Future<void> _verifyAuthenticode(File executable) async {
    if (!options.requireAuthenticode) return;
    final verifier = File(options.signatureVerifierPath);
    if (!verifier.existsSync()) {
      throw StateError('서명 검증 실행 파일이 없습니다: ${verifier.path}');
    }
    final result = await Process.run(verifier.path, [
      '--verify-signature',
      executable.path,
      options.expectedSignerThumbprint!,
    ]);
    if (result.exitCode != 0) {
      throw StateError('실행 파일 Authenticode 서명 또는 인증서 지문 검증 실패');
    }
    await _log('Authenticode signature and signer thumbprint verified');
  }

  Future<String?> _currentVersion() async {
    final pointer = await _readJson(_pointerFile);
    final value = pointer?['currentVersion'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  Future<void> _synchronizeRuntimeFiles(Directory versionRoot) async {
    final packagedLauncher =
        File(_join(versionRoot.path, 'ysignage_launcher.exe'));
    if (!packagedLauncher.existsSync()) {
      throw StateError('패키지에 ysignage_launcher.exe가 없습니다.');
    }
    packagedLauncher.copySync(_join(_root.path, 'ysignage_launcher.exe'));

    final sourceUpdater = Directory(_join(versionRoot.path, 'updater'));
    final targetUpdater =
        await Directory(_join(_root.path, 'updater')).create(recursive: true);
    if (!sourceUpdater.existsSync()) {
      throw StateError('패키지에 updater 폴더가 없습니다.');
    }
    for (final entity in sourceUpdater.listSync(followLinks: false)) {
      if (entity is File) {
        entity.copySync(_join(targetUpdater.path, _fileName(entity.path)));
      }
    }

    for (final name in const [
      'USER_MANUAL.html',
      'INSTALL_GUIDE.md',
      'MENU_CONFIG_GUIDE.md',
      'RELEASE_NOTES.md',
    ]) {
      final source = File(_join(versionRoot.path, name));
      if (source.existsSync()) source.copySync(_join(_root.path, name));
    }
    final legacyManual = File(_join(_root.path, 'USER_MANUAL.md'));
    if (legacyManual.existsSync()) legacyManual.deleteSync();
  }

  Future<void> _launchCurrent() async {
    final launcher = File(_join(_root.path, 'ysignage_launcher.exe'));
    if (!launcher.existsSync()) throw StateError('네이티브 실행기가 없습니다.');
    await Process.start(
      launcher.path,
      ['--data-root', _root.path, '--skip-updater-sync'],
      workingDirectory: _root.path,
      mode: ProcessStartMode.detached,
    );
  }

  Future<bool> _waitForReady(String version) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    final appState = File(_join(_root.path, 'state', 'app-state.json'));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final state = await _readJson(appState);
      if (state?['status'] == 'ready' && state?['version'] == version) {
        return true;
      }
    }
    return false;
  }

  Future<void> _removeLegacyLaunchers() async {
    for (final path in [
      _join(_root.path, 'launcher.ps1'),
      _join(_root.path, 'SimpleKiosk.cmd'),
      _join(_root.path, 'updater', 'update.ps1'),
      _join(_root.path, 'updater', 'launcher.ps1'),
      _join(_root.path, 'updater', 'launcher.cmd'),
    ]) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
    await _log('Legacy PowerShell updater and launcher entry points removed');
  }

  Future<void> _maintenance(String current, String? previous) async {
    final protected = {current, if (previous != null) previous};
    final versions = Directory(_join(_root.path, 'versions'))
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((directory) => !protected.contains(_fileName(directory.path)))
        .toList()
      ..sort(
        (left, right) =>
            right.statSync().modified.compareTo(left.statSync().modified),
      );
    final extraSlots = options.retainVersions - protected.length;
    for (final directory in versions.skip(extraSlots < 0 ? 0 : extraSlots)) {
      await _log('Removing old version ${_fileName(directory.path)}');
      directory.deleteSync(recursive: true);
    }

    final logCutoff =
        DateTime.now().subtract(Duration(days: options.logRetentionDays));
    final logs = Directory(_join(_root.path, 'logs'));
    if (logs.existsSync()) {
      for (final file in logs.listSync().whereType<File>()) {
        if (file.path != _logFile.path &&
            file.statSync().modified.isBefore(logCutoff)) {
          file.deleteSync();
        }
      }
    }
    final downloadCutoff = DateTime.now().subtract(const Duration(days: 7));
    final downloads = Directory(_join(_root.path, 'downloads'));
    if (downloads.existsSync()) {
      for (final file in downloads.listSync().whereType<File>()) {
        if (file.absolute.path != File(options.packagePath).absolute.path &&
            file.statSync().modified.isBefore(downloadCutoff)) {
          file.deleteSync();
        }
      }
    }
  }

  Future<void> _writeState(String status, {String? error}) async {
    var failureCount = 0;
    final previous = await _readJson(_stateFile);
    if (previous?['version'] == options.version) {
      failureCount = _asInt(previous?['failureCount']);
    }
    if (status == 'failed') failureCount++;
    if (status == 'installed') failureCount = 0;
    await _atomicJson(_stateFile, {
      'schemaVersion': 1,
      'status': status,
      'version': options.version,
      'failureCount': failureCount,
      if (error != null && error.isNotEmpty) 'error': error,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _writePointer(String current, String? previous) => _atomicJson(
        _pointerFile,
        {
          'schemaVersion': 1,
          'currentVersion': current,
          'previousVersion': previous,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );

  Future<void> _atomicJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    if (file.existsSync()) file.deleteSync();
    await temporary.rename(file.path);
  }

  Future<Map<String, dynamic>?> _readJson(File file) async {
    if (!file.existsSync()) return null;
    try {
      final decoded = json.decode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rotateLog() async {
    if (!_logFile.existsSync() || _logFile.lengthSync() <= 5 * 1024 * 1024) {
      return;
    }
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    await _logFile
        .rename(_join(_logFile.parent.path, 'updater-$timestamp.log'));
  }

  Future<void> _log(String message) async {
    await _logFile.writeAsString(
      '${DateTime.now().toIso8601String()} [native-updater] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;

String _fileName(String path) =>
    path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).last;

String _join(String first, String second, [String? third]) {
  final separator = Platform.pathSeparator;
  return [first, second, if (third != null) third]
      .map((part) => part.replaceAll(RegExp(r'[\\/]+$'), ''))
      .join(separator);
}
