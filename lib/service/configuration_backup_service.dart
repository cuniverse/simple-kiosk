import 'dart:convert';
import 'dart:io';

import '../model/admin_api_settings.dart';
import '../model/update_policy.dart';
import 'admin_api_settings_store.dart';
import 'menu_config_loader.dart';
import 'runtime_paths.dart';
import 'update_policy_store.dart';

class ConfigurationBackupService {
  final MenuConfigLoader menuLoader;
  final AdminApiSettingsStore adminApiSettingsStore;

  const ConfigurationBackupService({
    this.menuLoader = const MenuConfigLoader(),
    this.adminApiSettingsStore = const AdminApiSettingsStore(),
  });

  Future<Map<String, dynamic>> export() async => _createBackup(
        menu: await menuLoader.readEffective(),
        adminApi: await adminApiSettingsStore.load(),
        updatePolicy: await UpdatePolicyStore.load(),
      );

  Future<void> saveCurrentAsPrevious() async {
    final path = RuntimePaths.previousSettingsBackup;
    if (path == null) return;
    await RuntimePaths.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(await export()),
    );
  }

  Future<AdminApiSettings> import(Map<String, dynamic> backup) async {
    final validated = await _preserveFixedId(_validate(backup));
    final previous = await export();
    await saveCurrentAsPrevious();

    try {
      await _apply(validated);
      return validated.adminApi;
    } catch (_) {
      try {
        await _apply(_validate(previous));
      } catch (_) {
        // Preserve the original import error. The previous backup file remains
        // available for a manual recovery attempt.
      }
      rethrow;
    }
  }

  Future<AdminApiSettings> restorePrevious() async {
    final path = RuntimePaths.previousSettingsBackup;
    if (path == null || !await File(path).exists()) {
      throw StateError('복원할 직전 설정이 없습니다.');
    }
    final decoded = json.decode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('직전 설정 백업 파일이 올바르지 않습니다.');
    }
    final validated = await _preserveFixedId(_validate(decoded));
    await _apply(validated);
    return validated.adminApi;
  }

  _ValidatedBackup _validate(Map<String, dynamic> backup) {
    final schemaVersion = backup['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException('지원하지 않는 설정 백업 스키마입니다: $schemaVersion');
    }
    final menu = backup['menu'];
    final adminApi = backup['adminApi'];
    final updatePolicy = backup['updatePolicy'];
    if (menu is! Map<String, dynamic> ||
        adminApi is! Map<String, dynamic> ||
        updatePolicy is! Map<String, dynamic>) {
      throw const FormatException(
        '설정 백업에는 menu, adminApi, updatePolicy 객체가 필요합니다.',
      );
    }
    MenuConfigLoader.parse(menu);
    return _ValidatedBackup(
      menu: Map<String, dynamic>.from(menu),
      adminApi: AdminApiSettings.fromJson(adminApi),
      updatePolicy: UpdatePolicy.fromJson(updatePolicy),
    );
  }

  Future<_ValidatedBackup> _preserveFixedId(_ValidatedBackup backup) async {
    final local = await adminApiSettingsStore.load();
    return _ValidatedBackup(
      menu: backup.menu,
      updatePolicy: backup.updatePolicy,
      adminApi: preserveDeviceIdentity(backup.adminApi, local),
    );
  }

  static AdminApiSettings preserveDeviceIdentity(
          AdminApiSettings imported, AdminApiSettings local) =>
      local.webAdminSshForwardingIdFixed
          ? imported.copyWith(
              webAdminSshForwardingId: local.webAdminSshForwardingId,
              webAdminSshForwardingIdFixed: true,
            )
          : imported;

  Future<void> _apply(_ValidatedBackup backup) async {
    await menuLoader.saveOverride(backup.menu);
    await UpdatePolicyStore.save(backup.updatePolicy);
    await adminApiSettingsStore.save(backup.adminApi);
  }

  static Map<String, dynamic> _createBackup({
    required Map<String, dynamic> menu,
    required AdminApiSettings adminApi,
    required UpdatePolicy updatePolicy,
  }) =>
      {
        'schemaVersion': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'application': '여의도성당Signage',
        'menu': menu,
        'adminApi': adminApi.toJson(),
        'updatePolicy': updatePolicy.toJson(),
      };
}

class _ValidatedBackup {
  final Map<String, dynamic> menu;
  final AdminApiSettings adminApi;
  final UpdatePolicy updatePolicy;

  const _ValidatedBackup({
    required this.menu,
    required this.adminApi,
    required this.updatePolicy,
  });
}
