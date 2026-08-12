import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../model/update_policy.dart';
import 'update_policy_store.dart';
import 'update_service.dart';

class UpdateController extends ChangeNotifier {
  final UpdateService _service;
  UpdatePolicy policy = const UpdatePolicy();
  AvailableUpdate? available;
  File? downloadedPackage;
  String currentVersion = '-';
  String status = '초기화 중';
  DateTime? lastCheckedAt;
  bool busy = false;
  bool _isIdle = false;
  Timer? _timer;
  Timer? _retryTimer;
  int _consecutiveFailures = 0;

  UpdateController({UpdateService? service})
      : _service = service ?? UpdateService();

  bool get supported => Platform.isWindows;

  Future<void> initialize() async {
    currentVersion = (await PackageInfo.fromPlatform()).version;
    policy = await UpdatePolicyStore.load();
    status = policy.enabled ? '자동 업데이트 사용' : '자동 업데이트 꺼짐';
    _schedule();
    notifyListeners();
    if (policy.enabled) unawaited(check(automatic: true));
  }

  Future<void> setEnabled(bool enabled) async {
    await updatePolicy(policy.copyWith(enabled: enabled));
  }

  Future<void> updatePolicy(UpdatePolicy updated) async {
    final wasEnabled = policy.enabled;
    policy = updated;
    await UpdatePolicyStore.save(policy);
    if (!policy.enabled) {
      _timer?.cancel();
      status = '자동 업데이트 꺼짐';
      await _service.writeState({'status': 'automatic-disabled'});
    } else {
      status = '자동 업데이트 사용';
      _schedule();
      if (!wasEnabled) unawaited(check(automatic: true));
    }
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (!policy.enabled || !supported) return;
    _timer = Timer.periodic(
      Duration(hours: policy.checkIntervalHours),
      (_) => check(automatic: true),
    );
  }

  Future<void> check({bool automatic = false}) async {
    if (!supported || busy) return;
    busy = true;
    status = '업데이트 확인 중';
    notifyListeners();
    try {
      available = await _service.check(currentVersion: currentVersion);
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
      lastCheckedAt = DateTime.now();
      status = available == null
          ? '최신 버전 사용 중'
          : '새 버전 ${available!.manifest.version} 사용 가능';
      await _service.writeState({
        'status': available == null ? 'up-to-date' : 'available',
        if (available != null) 'version': available!.manifest.version,
        'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
      });
      if (automatic && policy.enabled && available != null) {
        busy = false;
        await download();
        return;
      }
    } catch (error) {
      _consecutiveFailures++;
      status = '확인 실패: $error';
      await _service.writeState({'status': 'check-failed', 'error': '$error'});
      if (policy.enabled) {
        final exponent = _consecutiveFailures.clamp(1, 8) - 1;
        _retryTimer?.cancel();
        _retryTimer = Timer(
          Duration(minutes: 1 << exponent),
          () => check(automatic: true),
        );
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final update = available;
    if (update == null || busy) return;
    busy = true;
    status = '다운로드 중';
    notifyListeners();
    try {
      downloadedPackage = await _service.download(update);
      status = '다운로드 완료 / 설치 대기';
      await _service.writeState({
        'status': 'downloaded',
        'version': update.manifest.version,
        'packagePath': downloadedPackage!.path,
      });
      if (canAutoInstall(isIdle: _isIdle)) {
        busy = false;
        await installNow();
        return;
      }
    } catch (error) {
      status = '다운로드 실패: $error';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  bool canAutoInstall({required bool isIdle, DateTime? now}) {
    if (!policy.enabled || downloadedPackage == null) return false;
    if (policy.installWhenIdle && !isIdle) return false;
    return policy.installWindow.contains(now ?? DateTime.now());
  }

  void setIdle(bool value) {
    _isIdle = value;
    if (value && canAutoInstall(isIdle: true) && !busy) {
      unawaited(installNow());
    }
  }

  Future<void> installNow() async {
    final package = downloadedPackage;
    final update = available;
    if (package == null || update == null || busy) return;
    busy = true;
    status = '설치 요청 중';
    notifyListeners();
    await _service.requestInstall(
      package,
      update.manifest,
      retainVersions: policy.retainVersions,
      logRetentionDays: policy.logRetentionDays,
    );
    status = '앱 종료 후 설치 예정';
    notifyListeners();
    exit(0);
  }

  Future<String> exportDiagnostics() async {
    if (!supported || busy) return '';
    busy = true;
    status = '진단 자료 내보내는 중';
    notifyListeners();
    try {
      final path = await _service.exportDiagnostics();
      status = '진단 자료 저장 완료: $path';
      return path;
    } catch (error) {
      status = '진단 자료 내보내기 실패: $error';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryTimer?.cancel();
    _service.close();
    super.dispose();
  }
}
