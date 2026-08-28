import 'dart:convert';
import 'dart:io';

import '../model/admin_api_settings.dart';
import 'app_logger.dart';
import 'runtime_paths.dart';

enum WindowsFirewallSyncResult {
  unsupported,
  unchanged,
  installed,
  removed,
  declinedOrFailed,
}

typedef FirewallProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Keeps the Setup-managed Windows Firewall rules aligned with WEB admin
/// settings. Elevation is requested only when the persisted rule plan is
/// missing or no longer matches the active settings.
class WindowsFirewallService {
  WindowsFirewallService({
    bool? supportedOverride,
    String? installRootOverride,
    FirewallProcessRunner? processRunner,
  })  : _supportedOverride = supportedOverride,
        _installRootOverride = installRootOverride,
        _processRunner = processRunner ?? Process.run;

  final bool? _supportedOverride;
  final String? _installRootOverride;
  final FirewallProcessRunner _processRunner;
  Future<WindowsFirewallSyncResult>? _running;

  bool get supported => _supportedOverride ?? Platform.isWindows;

  Future<WindowsFirewallSyncResult> reconcile(
    AdminApiSettings settings,
  ) {
    final previous = _running;
    final operation = previous == null
        ? _guardedReconcile(settings)
        : previous.then((_) => _guardedReconcile(settings));
    _running = operation;
    return operation.whenComplete(() {
      if (identical(_running, operation)) _running = null;
    });
  }

  Future<WindowsFirewallSyncResult> _guardedReconcile(
    AdminApiSettings settings,
  ) async {
    try {
      return await _reconcile(settings);
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.api, error, stackTrace);
      return WindowsFirewallSyncResult.declinedOrFailed;
    }
  }

  Future<WindowsFirewallSyncResult> _reconcile(
    AdminApiSettings settings,
  ) async {
    if (!supported) return WindowsFirewallSyncResult.unsupported;
    final root = _installRootOverride ?? RuntimePaths.dataRoot;
    if (root == null || root.trim().isEmpty) {
      return WindowsFirewallSyncResult.unsupported;
    }

    final script = File(_child(root, 'updater/configure-firewall.ps1'));
    if (!await script.exists()) {
      return WindowsFirewallSyncResult.unsupported;
    }

    final state = File(_child(root, 'state/firewall.json'));
    final action = await _requiredAction(settings, state);
    if (action == null) return WindowsFirewallSyncResult.unchanged;

    final arguments = '-NoProfile -ExecutionPolicy Bypass '
        '-File "${script.path}" -Action $action -InstallRoot "$root"';
    final command = r'& { try { $process = Start-Process '
        r'-FilePath "powershell.exe" -Verb RunAs -WindowStyle Hidden '
        "-ArgumentList ${_powerShellLiteral(arguments)} "
        r'-Wait -PassThru -ErrorAction Stop; exit $process.ExitCode '
        r'} catch { Write-Error $_; exit 1 } }';

    try {
      final result = await _processRunner('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ]);
      if (result.exitCode != 0) {
        AppLogger.warning(
          LogCategory.api,
          'Windows Firewall $action was declined or failed '
          '(exit ${result.exitCode}): ${result.stderr}',
        );
        return WindowsFirewallSyncResult.declinedOrFailed;
      }

      final remainingAction = await _requiredAction(settings, state);
      if (remainingAction != null) {
        AppLogger.warning(
          LogCategory.api,
          'Windows Firewall $action completed without the expected state.',
        );
        return WindowsFirewallSyncResult.declinedOrFailed;
      }
      return action == 'Install'
          ? WindowsFirewallSyncResult.installed
          : WindowsFirewallSyncResult.removed;
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.api, error, stackTrace);
      return WindowsFirewallSyncResult.declinedOrFailed;
    }
  }

  Future<String?> _requiredAction(
    AdminApiSettings settings,
    File state,
  ) async {
    if (!settings.enabled) {
      return await state.exists() ? 'Remove' : null;
    }
    if (!await state.exists()) return 'Install';
    try {
      final source = (await state.readAsString()).replaceFirst('\ufeff', '');
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return 'Install';
      final webAdmin = decoded['webAdmin'];
      final mdns = decoded['mdns'];
      final profiles = decoded['profile'];
      final matches = decoded['remoteAddress'] == 'LocalSubnet' &&
          profiles is List &&
          profiles.length == 2 &&
          profiles.contains('Domain') &&
          profiles.contains('Private') &&
          webAdmin is Map &&
          webAdmin['enabled'] == true &&
          webAdmin['protocol'] == 'TCP' &&
          webAdmin['port'] == settings.port &&
          mdns is Map &&
          mdns['enabled'] == settings.mdnsEnabled &&
          mdns['protocol'] == 'UDP' &&
          mdns['port'] == 5353;
      return matches ? null : 'Install';
    } catch (_) {
      return 'Install';
    }
  }

  static String _child(String root, String relative) =>
      '$root${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}';

  static String _powerShellLiteral(String value) =>
      "'${value.replaceAll("'", "''")}'";
}
