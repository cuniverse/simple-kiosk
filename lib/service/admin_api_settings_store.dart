import 'dart:convert';
import 'dart:io';

import '../model/admin_api_settings.dart';
import 'runtime_paths.dart';

class AdminApiSettingsStore {
  final File? _file;

  const AdminApiSettingsStore({File? file}) : _file = file;

  File? get _settingsFile {
    if (_file != null) return _file;
    final path = RuntimePaths.adminApiSettings;
    return path == null ? null : File(path);
  }

  Future<AdminApiSettings> load() async {
    await RuntimePaths.ensureStructure();
    final file = _settingsFile;
    if (file == null) return const AdminApiSettings();
    if (!await file.exists()) {
      const settings = AdminApiSettings();
      await save(settings);
      return settings;
    }
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('admin-api.json: 객체 필요');
    }
    return AdminApiSettings.fromJson(decoded);
  }

  Future<void> save(AdminApiSettings settings) async {
    final file = _settingsFile;
    if (file == null) return;
    await RuntimePaths.atomicWrite(
      file.path,
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
