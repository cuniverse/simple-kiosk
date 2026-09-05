import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../model/update_policy.dart';
import '../model/update_manifest.dart';
import 'update_policy_store.dart';
import 'update_service.dart';
import 'app_logger.dart';

class UpdateController extends ChangeNotifier {
  final UpdateService _service;
  final Future<String> Function() _currentVersionLoader;
  final Future<UpdatePolicy> Function() _policyLoader;
  final Future<void> Function(UpdatePolicy) _policySaver;
  final void Function(int) _exitApplication;
  final bool? _supportedOverride;
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
  Future<void>? _initializing;
  Future<void> _startupUpdate = Future<void>.value();
  Timer? _uploadedInstallTimer;
  Future<void> _uploadedInstall = Future<void>.value();

  @visibleForTesting
  Future<void> get uploadedInstallDone => _uploadedInstall;

  UpdateController({
    UpdateService? service,
    Future<String> Function()? currentVersionLoader,
    Future<UpdatePolicy> Function()? policyLoader,
    Future<void> Function(UpdatePolicy)? policySaver,
    void Function(int)? exitApplication,
    bool? supportedOverride,
  })  : _service = service ?? UpdateService(),
        _currentVersionLoader = currentVersionLoader ??
            (() async => (await PackageInfo.fromPlatform()).version),
        _policyLoader = policyLoader ?? UpdatePolicyStore.load,
        _policySaver = policySaver ?? UpdatePolicyStore.save,
        _exitApplication = exitApplication ?? exit,
        _supportedOverride = supportedOverride;

  bool get supported => _supportedOverride ?? Platform.isWindows;

  @visibleForTesting
  Future<void> get startupUpdateDone => _startupUpdate;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    currentVersion = await _currentVersionLoader();
    policy = await _policyLoader();
    status = policy.enabled ? '자동 업데이트 사용' : '자동 업데이트 꺼짐';
    _schedule();
    notifyListeners();
    if (policy.enabled && supported) {
      _startupUpdate = _runStartupUpdate();
      unawaited(_startupUpdate);
    }
  }

  /// 프로그램을 처음 실행할 때는 자동 업데이트가 켜져 있으면 설치 시간대나
  /// 화면 보호기 상태를 기다리지 않고 검사, 다운로드, 설치 요청까지 진행한다.
  /// 이후 주기 검사는 기존 운영 정책을 그대로 적용한다.
  Future<void> _runStartupUpdate() async {
    try {
      final update = await check();
      if (update == null || !policy.enabled) return;
      final package = await download(allowAutoInstall: false);
      if (package == null || !policy.enabled) return;
      await installNow();
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.update, error, stackTrace);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await updatePolicy(policy.copyWith(enabled: enabled));
  }

  Future<void> updatePolicy(UpdatePolicy updated) async {
    final wasEnabled = policy.enabled;
    policy = updated;
    await _policySaver(policy);
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

  Future<AvailableUpdate?> check({
    bool automatic = false,
    bool rethrowErrors = false,
  }) async {
    if (!supported || busy) return available;
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
        return available;
      }
      return available;
    } catch (error) {
      AppLogger.error(LogCategory.update, error);
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
      if (rethrowErrors) rethrow;
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<File?> download({
    bool allowAutoInstall = true,
    bool rethrowErrors = false,
  }) async {
    final update = available;
    if (update == null || busy) return downloadedPackage;
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
      if (allowAutoInstall && canAutoInstall(isIdle: _isIdle)) {
        busy = false;
        await installNow();
        return downloadedPackage;
      }
      return downloadedPackage;
    } catch (error) {
      AppLogger.error(LogCategory.update, error);
      status = '다운로드 실패: $error';
      if (rethrowErrors) rethrow;
      return null;
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

  Future<void> installNow({
    bool manual = false,
    Future<bool> Function(Object error)? confirmSetupFallback,
  }) async {
    final package = downloadedPackage;
    final update = available;
    if (package == null || update == null || busy) return;
    busy = true;
    status = '설치 요청 중';
    notifyListeners();
    try {
      await _service.requestInstall(
        package,
        update.manifest,
        retainVersions: policy.retainVersions,
        logRetentionDays: policy.logRetentionDays,
        forceRetry: manual,
      );
      status = '앱 종료 후 설치 예정';
      notifyListeners();
      _exitApplication(0);
    } catch (nativeError, nativeStackTrace) {
      AppLogger.error(LogCategory.update, nativeError, nativeStackTrace);
      final setupApproved = manual &&
          confirmSetupFallback != null &&
          await confirmSetupFallback(nativeError);
      if (setupApproved) {
        try {
          status = '기본 업데이터 실패 / Setup 다운로드 중';
          notifyListeners();
          final installer = await _service.downloadSetupInstaller(update);
          await _service.launchSetupInstaller(installer);
          await _service.writeState({
            'status': 'setup-launched',
            'version': update.manifest.version,
            'setupPath': installer.path,
            'nativeUpdaterError': '$nativeError',
          });
          status = 'Setup 설치 프로그램 실행 / 앱 종료 예정';
          notifyListeners();
          _exitApplication(0);
          return;
        } catch (setupError, setupStackTrace) {
          AppLogger.error(LogCategory.update, setupError, setupStackTrace);
          busy = false;
          status = '설치 요청 실패: $nativeError / Setup 실패: $setupError';
          notifyListeners();
          throw StateError(status);
        }
      }
      busy = false;
      status = '설치 요청 실패: $nativeError';
      notifyListeners();
      rethrow;
    }
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
      AppLogger.error(LogCategory.update, error);
      status = '진단 자료 내보내기 실패: $error';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Reserve the updater immediately, then let the HTTP response reach the browser.
  void queueUploadedInstall(File package, UpdateManifest manifest) {
    if (!supported) throw UnsupportedError('Windows ZIP 업데이트만 지원합니다.');
    if (busy) throw StateError('다른 업데이트 작업이 진행 중입니다. 완료 후 다시 시도하세요.');
    UpdateService.validateCompatibility(manifest);
    busy = true;
    _retryTimer?.cancel();
    status = '업로드한 v${manifest.version} ZIP 설치 준비 중';
    notifyListeners();
    final done = Completer<void>();
    _uploadedInstall = done.future;
    _uploadedInstallTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _service.requestInstall(
          package,
          manifest,
          retainVersions: policy.retainVersions,
          logRetentionDays: policy.logRetentionDays,
          forceRetry: true,
        );
        status = '앱 종료 후 업로드한 ZIP 설치 예정';
        notifyListeners();
        _exitApplication(0);
      } catch (error, stackTrace) {
        AppLogger.error(LogCategory.update, error, stackTrace);
        status = 'ZIP 설치 실패: $error';
        busy = false;
        notifyListeners();
      } finally {
        done.complete();
      }
    });
  }

  @override
  void dispose() {
    _uploadedInstallTimer?.cancel();
    _timer?.cancel();
    _retryTimer?.cancel();
    _service.close();
    super.dispose();
  }
}
