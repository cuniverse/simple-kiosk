class AdminApiSettings {
  static const int defaultPort = 80;

  final bool enabled;
  final int port;

  const AdminApiSettings({
    this.enabled = true,
    this.port = defaultPort,
  });

  factory AdminApiSettings.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    final port = json['port'];
    if (enabled != null && enabled is! bool) {
      throw const FormatException('admin-api.json enabled: bool 필요');
    }
    if (port != null && (port is! int || port < 1 || port > 65535)) {
      throw const FormatException('admin-api.json port: 1~65535 필요');
    }
    return AdminApiSettings(
      enabled: enabled as bool? ?? true,
      port: port as int? ?? defaultPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'enabled': enabled,
        'port': port,
      };

  AdminApiSettings copyWith({bool? enabled, int? port}) => AdminApiSettings(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
      );
}
