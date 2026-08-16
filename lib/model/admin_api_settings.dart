import '../app_identity.dart';

class AdminApiSettings {
  static const int defaultPort = 80;

  final bool enabled;
  final int port;
  final bool mdnsEnabled;
  final String mdnsHostname;

  const AdminApiSettings({
    this.enabled = true,
    this.port = defaultPort,
    this.mdnsEnabled = true,
    this.mdnsHostname = defaultMdnsHostname,
  });

  factory AdminApiSettings.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    final port = json['port'];
    final mdnsEnabled = json['mdnsEnabled'];
    final mdnsHostname = json['mdnsHostname'];
    if (enabled != null && enabled is! bool) {
      throw const FormatException('admin-api.json enabled: bool 필요');
    }
    if (port != null && (port is! int || port < 1 || port > 65535)) {
      throw const FormatException('admin-api.json port: 1~65535 필요');
    }
    if (mdnsEnabled != null && mdnsEnabled is! bool) {
      throw const FormatException('admin-api.json mdnsEnabled: bool 필요');
    }
    if (mdnsHostname != null &&
        (mdnsHostname is! String || !isValidMdnsHostname(mdnsHostname))) {
      throw const FormatException(
        'mDNS 호스트 이름은 example.local 형식이어야 합니다.',
      );
    }
    return AdminApiSettings(
      enabled: enabled as bool? ?? true,
      port: port as int? ?? defaultPort,
      mdnsEnabled: mdnsEnabled as bool? ?? true,
      mdnsHostname:
          (mdnsHostname as String? ?? defaultMdnsHostname).trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'enabled': enabled,
        'port': port,
        'mdnsEnabled': mdnsEnabled,
        'mdnsHostname': mdnsHostname,
      };

  AdminApiSettings copyWith({
    bool? enabled,
    int? port,
    bool? mdnsEnabled,
    String? mdnsHostname,
  }) =>
      AdminApiSettings(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
        mdnsEnabled: mdnsEnabled ?? this.mdnsEnabled,
        mdnsHostname: mdnsHostname ?? this.mdnsHostname,
      );

  static bool isValidMdnsHostname(String value) {
    final hostname = value.trim().toLowerCase();
    if (!hostname.endsWith('.local') || hostname.length > 253) return false;
    final labels = hostname.split('.');
    if (labels.length < 2 || labels.last != 'local') return false;
    final labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    return labels.every((label) => labelPattern.hasMatch(label));
  }
}
