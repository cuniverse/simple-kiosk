class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;
  final String? prerelease;

  const SemanticVersion(this.major, this.minor, this.patch, [this.prerelease]);

  factory SemanticVersion.parse(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^v'), '');
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(normalized);
    if (match == null) throw FormatException('Semantic Version 형식 오류: $value');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    for (final pair in [
      [major, other.major],
      [minor, other.minor],
      [patch, other.patch],
    ]) {
      final result = pair[0].compareTo(pair[1]);
      if (result != 0) return result;
    }
    if (prerelease == null && other.prerelease != null) return 1;
    if (prerelease != null && other.prerelease == null) return -1;
    return (prerelease ?? '').compareTo(other.prerelease ?? '');
  }

  @override
  String toString() =>
      '$major.$minor.$patch${prerelease == null ? '' : '-$prerelease'}';
}

class UpdateManifest {
  final int schemaVersion;
  final String version;
  final String channel;
  final String minimumUpdaterVersion;
  final int configSchemaVersion;
  final String packageFile;
  final String sha256;
  final String? setupFile;
  final String? setupSha256;
  final bool authenticodeRequired;
  final String? signerThumbprint;

  const UpdateManifest({
    this.schemaVersion = 1,
    required this.version,
    required this.channel,
    this.minimumUpdaterVersion = '1.0.0',
    this.configSchemaVersion = 1,
    required this.packageFile,
    required this.sha256,
    this.setupFile,
    this.setupSha256,
    this.authenticodeRequired = false,
    this.signerThumbprint,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final channel = json['channel'];
    final package = json['package'];
    final schemaVersion = json['schemaVersion'];
    final minimumUpdaterVersion = json['minimumUpdaterVersion'];
    final configSchemaVersion = json['configSchemaVersion'];
    if (version is! String || channel is! String || package is! Map) {
      throw const FormatException('update-manifest.json 필수 필드 누락');
    }
    if (schemaVersion != null &&
        (schemaVersion is! num || schemaVersion.toInt() != 1)) {
      throw FormatException('지원하지 않는 manifest schemaVersion: $schemaVersion');
    }
    if (minimumUpdaterVersion != null && minimumUpdaterVersion is! String) {
      throw const FormatException('minimumUpdaterVersion: 문자열 필요');
    }
    if (configSchemaVersion != null &&
        (configSchemaVersion is! num || configSchemaVersion < 1)) {
      throw const FormatException('configSchemaVersion: 양의 정수 필요');
    }
    SemanticVersion.parse(version);
    SemanticVersion.parse(minimumUpdaterVersion as String? ?? '1.0.0');
    final file = package['file'];
    final sha = package['sha256'];
    final authenticodeRequired = package['authenticodeRequired'];
    final signerThumbprint = package['signerThumbprint'];
    final setup = json['setup'];
    if (file is! String ||
        sha is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) {
      throw const FormatException('update-manifest package 필드 오류');
    }
    if (authenticodeRequired != null && authenticodeRequired is! bool) {
      throw const FormatException('authenticodeRequired: bool 필요');
    }
    if (signerThumbprint != null &&
        (signerThumbprint is! String ||
            !RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(signerThumbprint))) {
      throw const FormatException('signerThumbprint 형식 오류');
    }
    if (authenticodeRequired == true && signerThumbprint == null) {
      throw const FormatException('서명 필수 패키지에는 signerThumbprint 필요');
    }
    String? setupFile;
    String? setupSha256;
    if (setup != null) {
      if (setup is! Map ||
          setup['file'] is! String ||
          setup['sha256'] is! String ||
          !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(setup['sha256'] as String)) {
        throw const FormatException('update-manifest setup 필드 오류');
      }
      setupFile = setup['file'] as String;
      setupSha256 = (setup['sha256'] as String).toLowerCase();
    }
    return UpdateManifest(
      schemaVersion: (schemaVersion as num?)?.toInt() ?? 1,
      version: version,
      channel: channel,
      minimumUpdaterVersion: minimumUpdaterVersion ?? '1.0.0',
      configSchemaVersion: (configSchemaVersion as num?)?.toInt() ?? 1,
      packageFile: file,
      sha256: sha.toLowerCase(),
      setupFile: setupFile,
      setupSha256: setupSha256,
      authenticodeRequired: authenticodeRequired as bool? ?? false,
      signerThumbprint: signerThumbprint?.toUpperCase(),
    );
  }
}
