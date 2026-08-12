import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../model/update_manifest.dart';
import 'runtime_paths.dart';

class AvailableUpdate {
  final UpdateManifest manifest;
  final Uri packageUrl;

  const AvailableUpdate(this.manifest, this.packageUrl);
}

class UpdateService {
  static const _api =
      'https://api.github.com/repos/cuniverse/simple-kiosk/releases/latest';
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

  Future<AvailableUpdate?> check({String? currentVersion}) async {
    final releaseResponse = await _client
        .get(Uri.parse(_api), headers: _headers)
        .timeout(const Duration(seconds: 20));
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
    final manifestJson = json.decode(utf8.decode(manifestResponse.bodyBytes));
    if (manifestJson is! Map<String, dynamic>) {
      throw const FormatException('update-manifest: 객체 필요');
    }
    final manifest = UpdateManifest.fromJson(manifestJson);
    if (manifest.channel != 'stable') return null;
    final installed =
        currentVersion ?? (await PackageInfo.fromPlatform()).version;
    if (SemanticVersion.parse(manifest.version)
            .compareTo(SemanticVersion.parse(installed)) <=
        0) {
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
    return AvailableUpdate(manifest, Uri.parse(packageUrl));
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
      const JsonEncoder.withIndent('  ').convert({
        ...previous,
        'schemaVersion': 1,
        ...state,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> requestInstall(File package, UpdateManifest manifest) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows 업데이트만 지원');
    final script = File(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}updater${Platform.pathSeparator}update.ps1',
    );
    if (!await script.exists()) throw StateError('업데이트 실행기 누락: ${script.path}');
    await writeState({
      'status': 'install-requested',
      'version': manifest.version,
      'packagePath': package.path,
      'sha256': manifest.sha256,
      'appPid': pid,
    });
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-PackagePath',
        package.path,
        '-Version',
        manifest.version,
        '-ExpectedSha256',
        manifest.sha256,
        '-AppPid',
        '$pid',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
