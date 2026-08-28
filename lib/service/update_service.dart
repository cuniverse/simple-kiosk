import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../model/update_manifest.dart';
import 'runtime_paths.dart';

class AvailableUpdate {
  final UpdateManifest manifest;
  final Uri packageUrl;
  final Uri? setupUrl;
  final String? setupSha256;

  const AvailableUpdate(
    this.manifest,
    this.packageUrl, {
    this.setupUrl,
    this.setupSha256,
  });
}

class UpdateService {
  static const updaterVersion = '2.0.0';
  static const _api =
      'https://api.github.com/repos/cuniverse/simple-kiosk/releases/latest';
  static const _webLatest =
      'https://github.com/cuniverse/simple-kiosk/releases/latest';
  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'SimpleKiosk-Updater/1.0',
  };

  final http.Client _client;
  final bool _ownsClient;

  UpdateService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static void validateCompatibility(UpdateManifest manifest) {
    if (SemanticVersion.parse(manifest.minimumUpdaterVersion)
            .compareTo(SemanticVersion.parse(updaterVersion)) >
        0) {
      throw StateError(
        '업데이트 실행기 ${manifest.minimumUpdaterVersion} 이상이 필요합니다. '
        '(현재 $updaterVersion)',
      );
    }
    // configSchemaVersion은 설치될 대상 앱의 설정 형식이다. 현재 앱의 설정
    // 처리기와 비교하면 스키마를 올린 첫 릴리스를 모든 구버전이 거부하게 된다.
    // 업데이트 실행기 자체의 호환성은 minimumUpdaterVersion으로만 판단한다.
  }

  Future<AvailableUpdate?> check({String? currentVersion}) async {
    final releaseResponse = await _client
        .get(Uri.parse(_api), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (releaseResponse.statusCode == 403 ||
        releaseResponse.statusCode == 429) {
      return _checkWithoutApi(currentVersion: currentVersion);
    }
    if (releaseResponse.statusCode != 200) {
      throw http.ClientException('GitHub HTTP ${releaseResponse.statusCode}');
    }
    final release = json.decode(utf8.decode(releaseResponse.bodyBytes));
    if (release is! Map ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      return null;
    }
    final assets = release['assets'];
    if (assets is! List) {
      throw const FormatException('GitHub Release assets 누락');
    }
    Map? manifestAsset;
    for (final asset in assets.whereType<Map>()) {
      if (asset['name'] == 'update-manifest.json') manifestAsset = asset;
    }
    if (manifestAsset == null) return null;
    final manifestUrl = manifestAsset['browser_download_url'];
    if (manifestUrl is! String ||
        !manifestUrl.startsWith('https://github.com/')) {
      throw const FormatException('허용되지 않은 manifest URL');
    }
    final manifestResponse = await _client
        .get(Uri.parse(manifestUrl), headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (manifestResponse.statusCode != 200) {
      throw http.ClientException(
          'Manifest HTTP ${manifestResponse.statusCode}');
    }
    final manifest = _parseManifest(manifestResponse);
    if (!await _isNewer(manifest, currentVersion: currentVersion)) {
      return null;
    }
    final packageAsset = assets.whereType<Map>().cast<Map?>().firstWhere(
          (asset) => asset?['name'] == manifest.packageFile,
          orElse: () => null,
        );
    final packageUrl = packageAsset?['browser_download_url'];
    if (packageUrl is! String ||
        !packageUrl.startsWith('https://github.com/')) {
      throw const FormatException('업데이트 패키지 asset 누락 또는 URL 오류');
    }
    final setupName = manifest.setupFile ??
        'simple-kiosk-windows-setup-${manifest.version}.exe';
    final setupAsset = assets.whereType<Map>().cast<Map?>().firstWhere(
          (asset) => asset?['name'] == setupName,
          orElse: () => null,
        );
    final setupUrlValue = setupAsset?['browser_download_url'];
    final setupDigestValue = setupAsset?['digest'];
    final apiSetupDigest = setupDigestValue is String &&
            RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(setupDigestValue)
        ? setupDigestValue.substring('sha256:'.length).toLowerCase()
        : null;
    final setupDigest = apiSetupDigest ?? manifest.setupSha256;
    final setupUrl = setupUrlValue is String &&
            setupUrlValue.startsWith('https://github.com/') &&
            setupDigest != null
        ? Uri.parse(setupUrlValue)
        : null;
    return AvailableUpdate(
      manifest,
      Uri.parse(packageUrl),
      setupUrl: setupUrl,
      setupSha256: setupUrl == null ? null : setupDigest,
    );
  }

  Future<AvailableUpdate?> _checkWithoutApi({String? currentVersion}) async {
    final latestRequest = http.Request('GET', Uri.parse(_webLatest))
      ..followRedirects = false
      ..headers['User-Agent'] = 'SimpleKiosk-Updater/1.0';
    final latestResponse =
        await _client.send(latestRequest).timeout(const Duration(seconds: 20));
    await latestResponse.stream.drain<void>().timeout(
          const Duration(seconds: 20),
        );
    final redirect = latestResponse.headers['location'];
    if (!const {301, 302, 303, 307, 308}.contains(latestResponse.statusCode) ||
        redirect == null) {
      throw http.ClientException(
        'GitHub API HTTP 403, Release redirect HTTP '
        '${latestResponse.statusCode}',
      );
    }

    final latestUri = Uri.parse(_webLatest).resolve(redirect);
    final segments = latestUri.pathSegments;
    if (latestUri.scheme != 'https' ||
        latestUri.host != 'github.com' ||
        segments.length != 5 ||
        segments[0] != 'cuniverse' ||
        segments[1] != 'simple-kiosk' ||
        segments[2] != 'releases' ||
        segments[3] != 'tag') {
      throw const FormatException('GitHub 최신 Release 리다이렉트 URL 오류');
    }
    final tag = segments[4];
    SemanticVersion.parse(tag);

    final manifestUrl = _directReleaseAsset(tag, 'update-manifest.json');
    final manifestResponse = await _client
        .get(manifestUrl, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (manifestResponse.statusCode != 200) {
      throw http.ClientException(
        'Manifest HTTP ${manifestResponse.statusCode}',
      );
    }
    final manifest = _parseManifest(manifestResponse);
    if (SemanticVersion.parse(tag)
            .compareTo(SemanticVersion.parse(manifest.version)) !=
        0) {
      throw const FormatException('Release 태그와 manifest 버전 불일치');
    }
    if (!await _isNewer(manifest, currentVersion: currentVersion)) {
      return null;
    }

    final setupFile = manifest.setupFile;
    final setupSha256 = manifest.setupSha256;
    return AvailableUpdate(
      manifest,
      _directReleaseAsset(tag, manifest.packageFile),
      setupUrl: setupFile == null || setupSha256 == null
          ? null
          : _directReleaseAsset(tag, setupFile),
      setupSha256: setupFile == null ? null : setupSha256,
    );
  }

  UpdateManifest _parseManifest(http.Response response) {
    final manifestJson = json.decode(utf8.decode(response.bodyBytes));
    if (manifestJson is! Map<String, dynamic>) {
      throw const FormatException('update-manifest: 객체 필요');
    }
    final manifest = UpdateManifest.fromJson(manifestJson);
    if (manifest.channel != 'stable') {
      throw const FormatException('stable Release manifest가 아닙니다.');
    }
    validateCompatibility(manifest);
    return manifest;
  }

  Future<bool> _isNewer(
    UpdateManifest manifest, {
    required String? currentVersion,
  }) async {
    final installed =
        currentVersion ?? (await PackageInfo.fromPlatform()).version;
    return SemanticVersion.parse(manifest.version)
            .compareTo(SemanticVersion.parse(installed)) >
        0;
  }

  static Uri _directReleaseAsset(String tag, String fileName) {
    if (fileName.isEmpty ||
        fileName == '.' ||
        fileName == '..' ||
        fileName.contains('/') ||
        fileName.contains(r'\')) {
      throw const FormatException('Release asset 파일명 오류');
    }
    return Uri(
      scheme: 'https',
      host: 'github.com',
      pathSegments: [
        'cuniverse',
        'simple-kiosk',
        'releases',
        'download',
        tag,
        fileName,
      ],
    );
  }

  Future<File> download(AvailableUpdate update) async {
    final downloads = RuntimePaths.downloads;
    if (downloads == null) throw UnsupportedError('Windows 업데이트만 지원');
    await Directory(downloads).create(recursive: true);
    final destination = File(
        '$downloads${Platform.pathSeparator}${update.manifest.packageFile}');
    final temporary = File('${destination.path}.part');
    final request = http.Request('GET', update.packageUrl)
      ..headers.addAll(_headers);
    final existingLength =
        await temporary.exists() ? await temporary.length() : 0;
    if (existingLength > 0) {
      request.headers['Range'] = 'bytes=$existingLength-';
    }
    final response =
        await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw http.ClientException('Package HTTP ${response.statusCode}');
    }
    final sink = temporary.openWrite(
      mode: response.statusCode == 206 && existingLength > 0
          ? FileMode.append
          : FileMode.write,
    );
    await response.stream.pipe(sink);
    final digest = await sha256.bind(temporary.openRead()).first;
    if (digest.toString() != update.manifest.sha256) {
      await temporary.delete();
      throw const FormatException('업데이트 ZIP SHA-256 불일치');
    }
    if (await destination.exists()) await destination.delete();
    return temporary.rename(destination.path);
  }

  Future<File> downloadSetupInstaller(AvailableUpdate update) async {
    final downloads = RuntimePaths.downloads;
    final setupUrl = update.setupUrl;
    final expectedSha256 = update.setupSha256;
    if (downloads == null) throw UnsupportedError('Windows 업데이트만 지원');
    if (setupUrl == null || expectedSha256 == null) {
      throw StateError('검증 가능한 Setup 설치 파일이 Release에 없습니다.');
    }
    await Directory(downloads).create(recursive: true);
    final fileName = setupUrl.pathSegments.last;
    final destination = File(
      '$downloads${Platform.pathSeparator}$fileName',
    );
    final temporary = File('${destination.path}.part');
    final request = http.Request('GET', setupUrl)..headers.addAll(_headers);
    final response =
        await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw http.ClientException('Setup HTTP ${response.statusCode}');
    }
    await response.stream.pipe(temporary.openWrite());
    final digest = await sha256.bind(temporary.openRead()).first;
    if (digest.toString() != expectedSha256) {
      await temporary.delete();
      throw const FormatException('Setup EXE SHA-256 불일치');
    }
    if (await destination.exists()) await destination.delete();
    return temporary.rename(destination.path);
  }

  Future<void> launchSetupInstaller(File installer) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows만 지원');
    if (!await installer.exists()) {
      throw StateError('Setup 설치 파일을 찾을 수 없습니다: ${installer.path}');
    }
    await Process.start(
      installer.path,
      const [],
      workingDirectory: installer.parent.path,
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    final path = RuntimePaths.updateState;
    if (path == null) return;
    Map<String, dynamic> previous = const {};
    final file = File(path);
    if (await file.exists()) {
      try {
        final decoded = json.decode(await file.readAsString());
        if (decoded is Map<String, dynamic>) previous = decoded;
      } catch (_) {
        // 손상된 상태 파일은 새 상태로 교체한다.
      }
    }
    await RuntimePaths.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(mergeUpdateState(
        previous: previous,
        state: state,
        updatedAt: DateTime.now().toUtc(),
      )),
    );
  }

  @visibleForTesting
  static Map<String, dynamic> mergeUpdateState({
    required Map<String, dynamic> previous,
    required Map<String, dynamic> state,
    required DateTime updatedAt,
  }) {
    final merged = <String, dynamic>{...previous};
    final previousVersion = previous['version'];
    final nextVersion = state['version'];
    if (nextVersion is String && nextVersion != previousVersion) {
      // A failure count belongs to one exact target release. Carrying it to a
      // newly discovered version makes that version look blocked before its
      // first installation attempt.
      merged.remove('failureCount');
      merged.remove('failureWindowStartedAt');
      merged.remove('error');
    }
    return {
      ...merged,
      'schemaVersion': 1,
      ...state,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Future<File> _updaterTool(String name) async {
    // Keep the native updater inside the immutable application version.
    // A legacy updater copies only direct children of `updater`, so placing the
    // new executable in `updater/payload` also lets installations affected by
    // the self-overwrite bug upgrade without touching their running EXE.
    if (name == 'ysignage_updater.exe') {
      final bundledPayload = File(
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}updater${Platform.pathSeparator}payload'
        '${Platform.pathSeparator}$name',
      );
      if (await bundledPayload.exists()) return bundledPayload;
    }
    final fixed = RuntimePaths.child('updater/$name');
    if (fixed != null) {
      final file = File(fixed);
      if (await file.exists()) return file;
    }
    return File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}updater${Platform.pathSeparator}$name',
    );
  }

  Future<void> requestInstall(
    File package,
    UpdateManifest manifest, {
    int retainVersions = 2,
    int logRetentionDays = 30,
    bool forceRetry = false,
  }) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows 업데이트만 지원');
    final updater = await _updaterTool('ysignage_updater.exe');
    if (!await updater.exists()) {
      throw StateError('네이티브 업데이트 실행기 누락: ${updater.path}');
    }
    final fixedLauncher = RuntimePaths.child('ysignage_launcher.exe');
    final bundledLauncher = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}ysignage_launcher.exe',
    );
    final signatureVerifier =
        fixedLauncher != null && await File(fixedLauncher).exists()
            ? File(fixedLauncher)
            : bundledLauncher;
    if (!await signatureVerifier.exists()) {
      throw StateError('네이티브 서명 검증 실행기 누락: ${signatureVerifier.path}');
    }
    await writeState({
      'status': 'install-requested',
      'version': manifest.version,
      'packagePath': package.path,
      'sha256': manifest.sha256,
      'appPid': pid,
    });
    final process = await Process.start(
      updater.path,
      [
        '--package',
        package.path,
        '--version',
        manifest.version,
        '--sha256',
        manifest.sha256,
        '--app-pid',
        '$pid',
        '--data-root',
        RuntimePaths.dataRoot!,
        '--retain-versions',
        '$retainVersions',
        '--log-retention-days',
        '$logRetentionDays',
        '--signature-verifier',
        signatureVerifier.path,
        if (forceRetry) '--force-retry',
        if (manifest.authenticodeRequired) '--require-authenticode',
        if (manifest.signerThumbprint != null) ...[
          '--signer-thumbprint',
          manifest.signerThumbprint!,
        ],
      ],
      mode: ProcessStartMode.normal,
    );

    // The updater writes `installing` before waiting for this app to exit.
    // Do not terminate the kiosk until that handshake is observed; otherwise a
    // PowerShell startup/argument error leaves the app closed and the state
    // permanently stuck at `install-requested`.
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);
    process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);
    final exited = process.exitCode.then<int?>((value) => value);
    // 네이티브 업데이트 실행기는 앱 종료 전에 ZIP 해시·경로·구성·서명을
    // 모두 검증한다. 큰 패키지에서도 검증 완료 신호를 충분히 기다린다.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final state = await _readUpdateState();
      if (state?['version'] == manifest.version &&
          state?['status'] == 'installing') {
        return;
      }
      final exitCode = await Future.any<int?>([
        exited,
        Future<int?>.delayed(const Duration(milliseconds: 200), () => null),
      ]);
      if (exitCode != null) {
        final failedState = await _readUpdateState();
        throw StateError(updateStartFailureMessage(
          exitCode: exitCode,
          state: failedState,
          stdout: stdoutBuffer.toString(),
          stderr: stderrBuffer.toString(),
        ));
      }
    }
    process.kill();
    throw TimeoutException('업데이트 실행기 시작 확인 시간이 초과되었습니다.');
  }

  @visibleForTesting
  static String updateStartFailureMessage({
    required int exitCode,
    Map<String, dynamic>? state,
    String stdout = '',
    String stderr = '',
  }) {
    final stateError = state?['error'];
    final processDetail =
        stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
    final detail = stateError is String && stateError.trim().isNotEmpty
        ? stateError.trim()
        : processDetail;
    return '업데이트 실행기가 시작되지 않았습니다 (종료 코드 $exitCode)'
        '${detail.isEmpty ? '' : ': $detail'}';
  }

  Future<Map<String, dynamic>?> _readUpdateState() async {
    final path = RuntimePaths.updateState;
    if (path == null) return null;
    try {
      final decoded = json.decode(await File(path).readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> exportDiagnostics() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows만 지원');
    final script = await _updaterTool('export-diagnostics.ps1');
    if (!await script.exists()) {
      throw StateError('진단 도구 누락: ${script.path}');
    }
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
      ],
    );
    if (result.exitCode != 0) {
      throw StateError('${result.stderr}'.trim());
    }
    return '${result.stdout}'.trim().split(RegExp(r'[\r\n]+')).last;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
