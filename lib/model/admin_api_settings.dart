import '../app_identity.dart';

const _notProvided = Object();

class AdminApiSettings {
  static const int defaultPort = 80;

  final bool enabled;
  final int port;
  final bool mdnsEnabled;
  final String mdnsHostname;
  final bool webAdminSshForwardingEnabled;
  final String? webAdminSshForwardingId;

  const AdminApiSettings({
    this.enabled = true,
    this.port = defaultPort,
    this.mdnsEnabled = true,
    this.mdnsHostname = defaultMdnsHostname,
    this.webAdminSshForwardingEnabled = true,
    this.webAdminSshForwardingId,
  });

  factory AdminApiSettings.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    final port = json['port'];
    final mdnsEnabled = json['mdnsEnabled'];
    final mdnsHostname = json['mdnsHostname'];
    final sshEnabled = json['webAdminSshForwardingEnabled'];
    final sshId = json['webAdminSshForwardingId'];
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
    if (sshEnabled != null && sshEnabled is! bool) {
      throw const FormatException(
        'admin-api.json webAdminSshForwardingEnabled: bool 필요',
      );
    }
    if (sshId != null &&
        (sshId is! String || !isValidWebAdminSshForwardingId(sshId))) {
      throw const FormatException(
        'admin-api.json webAdminSshForwardingId: ysignage{숫자} 형식 필요',
      );
    }
    return AdminApiSettings(
      enabled: enabled as bool? ?? true,
      port: port as int? ?? defaultPort,
      mdnsEnabled: mdnsEnabled as bool? ?? true,
      mdnsHostname:
          (mdnsHostname as String? ?? defaultMdnsHostname).trim().toLowerCase(),
      webAdminSshForwardingEnabled: sshEnabled as bool? ?? true,
      webAdminSshForwardingId: (sshId as String?)?.trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 3,
        'enabled': enabled,
        'port': port,
        'mdnsEnabled': mdnsEnabled,
        'mdnsHostname': mdnsHostname,
        'webAdminSshForwardingEnabled': webAdminSshForwardingEnabled,
        if (webAdminSshForwardingId != null)
          'webAdminSshForwardingId': webAdminSshForwardingId,
      };

  AdminApiSettings copyWith({
    bool? enabled,
    int? port,
    bool? mdnsEnabled,
    String? mdnsHostname,
    bool? webAdminSshForwardingEnabled,
    Object? webAdminSshForwardingId = _notProvided,
  }) =>
      AdminApiSettings(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
        mdnsEnabled: mdnsEnabled ?? this.mdnsEnabled,
        mdnsHostname: mdnsHostname ?? this.mdnsHostname,
        webAdminSshForwardingEnabled:
            webAdminSshForwardingEnabled ?? this.webAdminSshForwardingEnabled,
        webAdminSshForwardingId:
            identical(webAdminSshForwardingId, _notProvided)
                ? this.webAdminSshForwardingId
                : webAdminSshForwardingId as String?,
      );

  static bool isValidMdnsHostname(String value) {
    final hostname = value.trim().toLowerCase();
    if (!hostname.endsWith('.local') || hostname.length > 253) return false;
    final labels = hostname.split('.');
    if (labels.length < 2 || labels.last != 'local') return false;
    final labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
    return labels.every((label) => labelPattern.hasMatch(label));
  }

  static bool isValidWebAdminSshForwardingId(String value) =>
      RegExp(r'^ysignage[1-9][0-9]*$').hasMatch(value.trim().toLowerCase());
}
