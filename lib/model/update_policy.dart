class UpdateInstallWindow {
  final String start;
  final String end;

  const UpdateInstallWindow({this.start = '02:00', this.end = '05:00'});

  factory UpdateInstallWindow.fromJson(Object? raw) {
    if (raw == null) return const UpdateInstallWindow();
    if (raw is! Map) throw const FormatException('installWindow: 객체 필요');
    final start = raw['start'];
    final end = raw['end'];
    if (start is! String ||
        end is! String ||
        !_validTime(start) ||
        !_validTime(end)) {
      throw const FormatException('installWindow: HH:mm 형식 필요');
    }
    return UpdateInstallWindow(start: start, end: end);
  }

  bool contains(DateTime time) {
    int minutes(String value) {
      final parts = value.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }

    final current = time.hour * 60 + time.minute;
    final from = minutes(start);
    final to = minutes(end);
    return from <= to
        ? current >= from && current <= to
        : current >= from || current <= to;
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

bool _validTime(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return false;
  return int.parse(match.group(1)!) < 24 && int.parse(match.group(2)!) < 60;
}

class UpdatePolicy {
  final bool enabled;
  final String channel;
  final int checkIntervalHours;
  final bool installWhenIdle;
  final UpdateInstallWindow installWindow;
  final int retainVersions;
  final int logRetentionDays;

  const UpdatePolicy({
    this.enabled = false,
    this.channel = 'stable',
    this.checkIntervalHours = 6,
    this.installWhenIdle = true,
    this.installWindow = const UpdateInstallWindow(),
    this.retainVersions = 2,
    this.logRetentionDays = 30,
  });

  factory UpdatePolicy.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'];
    final channel = json['channel'];
    final interval = json['checkIntervalHours'];
    final installWhenIdle = json['installWhenIdle'];
    final retainVersions = json['retainVersions'];
    final logRetentionDays = json['logRetentionDays'];
    if (enabled != null && enabled is! bool) {
      throw const FormatException('enabled: bool 필요');
    }
    if (channel != null && channel != 'stable') {
      throw const FormatException('channel: stable만 지원');
    }
    if (interval != null && (interval is! num || interval <= 0)) {
      throw const FormatException('checkIntervalHours: 양수 필요');
    }
    if (installWhenIdle != null && installWhenIdle is! bool) {
      throw const FormatException('installWhenIdle: bool 필요');
    }
    if (retainVersions != null &&
        (retainVersions is! num || retainVersions < 2 || retainVersions > 10)) {
      throw const FormatException('retainVersions: 2~10 필요');
    }
    if (logRetentionDays != null &&
        (logRetentionDays is! num ||
            logRetentionDays < 1 ||
            logRetentionDays > 365)) {
      throw const FormatException('logRetentionDays: 1~365 필요');
    }
    return UpdatePolicy(
      enabled: enabled as bool? ?? false,
      channel: channel as String? ?? 'stable',
      checkIntervalHours: (interval as num?)?.toInt() ?? 6,
      installWhenIdle: installWhenIdle as bool? ?? true,
      installWindow: UpdateInstallWindow.fromJson(json['installWindow']),
      retainVersions: (retainVersions as num?)?.toInt() ?? 2,
      logRetentionDays: (logRetentionDays as num?)?.toInt() ?? 30,
    );
  }

  UpdatePolicy copyWith({
    bool? enabled,
    int? checkIntervalHours,
    bool? installWhenIdle,
    UpdateInstallWindow? installWindow,
    int? retainVersions,
    int? logRetentionDays,
  }) =>
      UpdatePolicy(
        enabled: enabled ?? this.enabled,
        channel: channel,
        checkIntervalHours: checkIntervalHours ?? this.checkIntervalHours,
        installWhenIdle: installWhenIdle ?? this.installWhenIdle,
        installWindow: installWindow ?? this.installWindow,
        retainVersions: retainVersions ?? this.retainVersions,
        logRetentionDays: logRetentionDays ?? this.logRetentionDays,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'enabled': enabled,
        'channel': channel,
        'checkIntervalHours': checkIntervalHours,
        'installWhenIdle': installWhenIdle,
        'installWindow': installWindow.toJson(),
        'retainVersions': retainVersions,
        'logRetentionDays': logRetentionDays,
      };
}
