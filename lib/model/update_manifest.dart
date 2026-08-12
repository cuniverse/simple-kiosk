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
  final String version;
  final String channel;
  final String packageFile;
  final String sha256;

  const UpdateManifest({
    required this.version,
    required this.channel,
    required this.packageFile,
    required this.sha256,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final channel = json['channel'];
    final package = json['package'];
    if (version is! String || channel is! String || package is! Map) {
      throw const FormatException('update-manifest.json 필수 필드 누락');
    }
    SemanticVersion.parse(version);
    final file = package['file'];
    final sha = package['sha256'];
    if (file is! String ||
        sha is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha)) {
      throw const FormatException('update-manifest package 필드 오류');
    }
    return UpdateManifest(
      version: version,
      channel: channel,
      packageFile: file,
      sha256: sha.toLowerCase(),
    );
  }
}
