import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/admin_api_settings.dart';
import '../model/layout_config.dart';
import '../model/update_policy.dart';
import '../service/admin_api_controller.dart';
import '../service/admin_pin_store.dart';
import '../service/update_controller.dart';
import '../service/windows_startup_service.dart';
import 'admin_pin_keypad.dart';

class UpdateAdminDialog {
  static final AdminPinStore _pinStore = AdminPinStore();

  static bool get isConfigured => true;

  static Uri? _webAdminUri(AdminApiController? controller) {
    if (controller == null || !controller.running) return null;
    final port = controller.actualPort;
    if (port == null) return null;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port == 80 ? null : port,
    );
  }

  static Future<void> _openWebAdmin(
    BuildContext context,
    Uri uri,
  ) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('기본 브라우저를 실행할 수 없습니다.');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('웹 관리자를 열지 못했습니다: $error')),
      );
    }
  }

  static Future<void> show(
    BuildContext context,
    UpdateController controller, {
    AdminApiController? adminApiController,
    Future<void> Function()? onExit,
    KeyboardMode keyboardMode = KeyboardMode.windows,
    Future<void> Function(KeyboardMode mode)? onKeyboardModeChanged,
  }) async {
    final pinController = TextEditingController();
    final webAdminUri = _webAdminUri(adminApiController);
    final authenticated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('관리자 PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminPinKeypad(
              controller: pinController,
              onSubmitted: () => Navigator.pop(dialogContext, true),
            ),
            if (webAdminUri != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                key: const ValueKey('open-web-admin'),
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                  unawaited(_openWebAdmin(context, webAdminUri));
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('웹 관리자 열기'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    final validPin = authenticated == true &&
        await _pinStore.verify(pinController.text.trim());
    pinController.dispose();
    if (!validPin || !context.mounted) {
      if (authenticated == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('관리자 PIN이 올바르지 않습니다.')),
        );
      }
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _UpdateAdminPanel(
        controller: controller,
        pinStore: _pinStore,
        adminApiController: adminApiController,
        onExit: onExit,
        keyboardMode: keyboardMode,
        onKeyboardModeChanged: onKeyboardModeChanged,
      ),
    );
  }
}

class _UpdateAdminPanel extends StatefulWidget {
  final UpdateController controller;
  final AdminPinStore pinStore;
  final AdminApiController? adminApiController;
  final Future<void> Function()? onExit;
  final KeyboardMode keyboardMode;
  final Future<void> Function(KeyboardMode mode)? onKeyboardModeChanged;

  const _UpdateAdminPanel({
    required this.controller,
    required this.pinStore,
    this.adminApiController,
    this.onExit,
    required this.keyboardMode,
    this.onKeyboardModeChanged,
  });

  @override
  State<_UpdateAdminPanel> createState() => _UpdateAdminPanelState();
}

class _UpdateAdminPanelState extends State<_UpdateAdminPanel> {
  late bool _enabled;
  late bool _installWhenIdle;
  late int _checkIntervalHours;
  late int _retainVersions;
  late int _logRetentionDays;
  late bool _adminApiEnabled;
  late bool _mdnsEnabled;
  late KeyboardMode _keyboardMode;
  final WindowsStartupService _startupService = WindowsStartupService();
  WindowsStartupStatus? _startupStatus;
  StartupLaunchMode _startupMode = StartupLaunchMode.signage;
  bool _startupBusy = false;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _adminApiPortController;
  late final TextEditingController _mdnsHostnameController;

  @override
  void initState() {
    super.initState();
    final policy = widget.controller.policy;
    _enabled = policy.enabled;
    _installWhenIdle = policy.installWhenIdle;
    _checkIntervalHours = policy.checkIntervalHours;
    _retainVersions = policy.retainVersions;
    _logRetentionDays = policy.logRetentionDays;
    _adminApiEnabled = widget.adminApiController?.settings.enabled ?? true;
    _mdnsEnabled = widget.adminApiController?.settings.mdnsEnabled ?? true;
    _keyboardMode = widget.keyboardMode;
    _startController = TextEditingController(text: policy.installWindow.start);
    _endController = TextEditingController(text: policy.installWindow.end);
    _adminApiPortController = TextEditingController(
      text:
          '${widget.adminApiController?.settings.port ?? AdminApiSettings.defaultPort}',
    );
    _mdnsHostnameController = TextEditingController(
      text:
          widget.adminApiController?.settings.mdnsHostname ?? 'ysignage.local',
    );
    unawaited(_refreshStartupStatus());
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _adminApiPortController.dispose();
    _mdnsHostnameController.dispose();
    super.dispose();
  }

  Future<void> _saveKeyboardMode() async {
    final callback = widget.onKeyboardModeChanged;
    if (callback == null) return;
    try {
      await callback(_keyboardMode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('키보드 방식을 저장했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('키보드 설정 저장 실패: $error')),
      );
    }
  }

  Future<void> _refreshStartupStatus() async {
    if (!_startupService.supported) return;
    try {
      final status = await _startupService.getStatus();
      if (!mounted) return;
      setState(() {
        _startupStatus = status;
        _startupMode = status.mode;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('시작프로그램 상태 확인 실패: $error')),
      );
    }
  }

  Future<void> _registerStartup() async {
    setState(() => _startupBusy = true);
    try {
      final status = await _startupService.register(_startupMode);
      if (!mounted) return;
      setState(() => _startupStatus = status);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Windows 시작프로그램에 등록했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('시작프로그램 등록 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _startupBusy = false);
    }
  }

  Future<void> _unregisterStartup() async {
    setState(() => _startupBusy = true);
    try {
      final status = await _startupService.unregister();
      if (!mounted) return;
      setState(() => _startupStatus = status);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Windows 시작프로그램 등록을 삭제했습니다.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('시작프로그램 삭제 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _startupBusy = false);
    }
  }

  String get _startupStatusText {
    final status = _startupStatus;
    if (status == null) return '상태 확인 중…';
    if (!status.registered) return '등록 안 됨';
    final mode = status.mode == StartupLaunchMode.hidden ? '숨김 모드' : '사이니지 모드';
    return status.targetMatches ? '등록됨 · $mode' : '기존 등록 발견 · 설치 위치 불일치';
  }

  bool _validTime(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
    return match != null &&
        int.parse(match.group(1)!) < 24 &&
        int.parse(match.group(2)!) < 60;
  }

  List<int> _options(int current, List<int> defaults) {
    final values = <int>{...defaults, current}.toList()..sort();
    return values;
  }

  Future<void> _save() async {
    final start = _startController.text.trim();
    final end = _endController.text.trim();
    if (!_validTime(start) || !_validTime(end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설치 시간은 HH:mm 형식으로 입력하세요.')),
      );
      return;
    }
    await widget.controller.updatePolicy(
      widget.controller.policy.copyWith(
        enabled: _enabled,
        checkIntervalHours: _checkIntervalHours,
        installWhenIdle: _installWhenIdle,
        installWindow: UpdateInstallWindow(start: start, end: end),
        retainVersions: _retainVersions,
        logRetentionDays: _logRetentionDays,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('업데이트 정책을 저장했습니다.')),
      );
    }
  }

  Future<void> _changePin() async {
    final newPinController = TextEditingController();
    final confirmController = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('관리자 PIN 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '새 PIN (숫자 4~12자리)'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '새 PIN 확인'),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    final newPin = newPinController.text.trim();
    final confirmation = confirmController.text.trim();
    newPinController.dispose();
    confirmController.dispose();
    if (approved != true || !mounted) return;
    if (newPin != confirmation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 PIN이 서로 일치하지 않습니다.')),
      );
      return;
    }
    try {
      await widget.pinStore.changePin(newPin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('관리자 PIN을 변경했습니다.')),
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('관리자 PIN 저장에 실패했습니다: $error')),
        );
      }
    }
  }

  Future<void> _saveAdminApi() async {
    final controller = widget.adminApiController;
    if (controller == null) return;
    final port = int.tryParse(_adminApiPortController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('관리 API 포트는 1~65535로 입력하세요.')),
      );
      return;
    }
    final mdnsHostname = _mdnsHostnameController.text.trim().toLowerCase();
    if (!AdminApiSettings.isValidMdnsHostname(mdnsHostname)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('mDNS 호스트 이름을 example.local 형식으로 입력하세요.'),
        ),
      );
      return;
    }
    try {
      await controller.updateSettings(
        AdminApiSettings(
          enabled: _adminApiEnabled,
          port: port,
          mdnsEnabled: _mdnsEnabled,
          mdnsHostname: mdnsHostname,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.running
                  ? '관리 API 설정을 저장했습니다. 포트: ${controller.actualPort}'
                  : controller.lastError ?? '관리 API를 사용하지 않습니다.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('관리 API 설정 저장 실패: $error')),
        );
      }
    }
  }

  Future<void> _confirmExit() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('완전 종료'),
        content: const Text('여의도성당Signage를 완전히 종료하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('완전 종료'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || widget.onExit == null) return;
    Navigator.pop(context);
    await widget.onExit!();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          widget.controller,
          if (widget.adminApiController != null) widget.adminApiController!,
        ]),
        builder: (context, _) {
          final controller = widget.controller;
          return AlertDialog(
            title: const Text('설정'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('자동 업데이트'),
                      subtitle: const Text('기본값 OFF · stable 채널'),
                      value: _enabled,
                      onChanged: controller.busy
                          ? null
                          : (value) => setState(() => _enabled = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('화면 보호기 진입 후 설치'),
                      value: _installWhenIdle,
                      onChanged: controller.busy
                          ? null
                          : (value) => setState(() => _installWhenIdle = value),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: _checkIntervalHours,
                      decoration: const InputDecoration(labelText: '확인 주기'),
                      items: _options(
                        _checkIntervalHours,
                        const [1, 3, 6, 12, 24],
                      )
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value시간'),
                              ))
                          .toList(),
                      onChanged: controller.busy
                          ? null
                          : (value) => setState(
                                () => _checkIntervalHours = value!,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startController,
                            decoration: const InputDecoration(
                              labelText: '설치 시작 (HH:mm)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _endController,
                            decoration: const InputDecoration(
                              labelText: '설치 종료 (HH:mm)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _retainVersions,
                            decoration:
                                const InputDecoration(labelText: '버전 보관 수'),
                            items: _options(
                              _retainVersions,
                              const [2, 3, 4, 5],
                            )
                                .map((value) => DropdownMenuItem(
                                      value: value,
                                      child: Text('$value개'),
                                    ))
                                .toList(),
                            onChanged: (value) => setState(
                              () => _retainVersions = value!,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _logRetentionDays,
                            decoration:
                                const InputDecoration(labelText: '로그 보관'),
                            items: _options(
                              _logRetentionDays,
                              const [7, 14, 30, 60, 90],
                            )
                                .map((value) => DropdownMenuItem(
                                      value: value,
                                      child: Text('$value일'),
                                    ))
                                .toList(),
                            onChanged: (value) => setState(
                              () => _logRetentionDays = value!,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: controller.busy ? null : _save,
                        child: const Text('정책 저장'),
                      ),
                    ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('관리자 PIN'),
                      subtitle: const Text(
                        '변경 PIN은 PBKDF2 솔트 해시 파일로 저장됩니다. '
                        '파일 삭제 시 기본 PIN으로 복원됩니다.',
                      ),
                      trailing: OutlinedButton(
                        onPressed: controller.busy ? null : _changePin,
                        child: const Text('PIN 변경'),
                      ),
                    ),
                    const Divider(height: 28),
                    DropdownButtonFormField<KeyboardMode>(
                      initialValue: _keyboardMode,
                      decoration: const InputDecoration(
                        labelText: '가상 키보드 방식',
                        helperText: '기본값은 Windows 키보드입니다.',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: KeyboardMode.windows,
                          child: Text('Windows 키보드'),
                        ),
                        DropdownMenuItem(
                          value: KeyboardMode.builtIn,
                          child: Text('내장 키보드'),
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _keyboardMode = value!,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: widget.onKeyboardModeChanged == null
                            ? null
                            : _saveKeyboardMode,
                        child: const Text('키보드 설정 저장'),
                      ),
                    ),
                    if (_startupService.supported) ...[
                      const Divider(height: 28),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Windows 시작프로그램'),
                        subtitle: Text(_startupStatusText),
                        trailing: IconButton(
                          tooltip: '상태 새로고침',
                          onPressed:
                              _startupBusy ? null : _refreshStartupStatus,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                      DropdownButtonFormField<StartupLaunchMode>(
                        key: ValueKey(_startupStatus?.mode),
                        initialValue: _startupMode,
                        decoration: const InputDecoration(
                          labelText: '시작프로그램 실행 방식',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: StartupLaunchMode.signage,
                            child: Text('사이니지 모드로 표시'),
                          ),
                          DropdownMenuItem(
                            value: StartupLaunchMode.hidden,
                            child: Text('숨김 모드로 시작'),
                          ),
                        ],
                        onChanged: _startupBusy
                            ? null
                            : (value) => setState(
                                  () => _startupMode = value!,
                                ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: _startupBusy ? null : _registerStartup,
                            child: Text(
                              _startupStatus?.registered == true
                                  ? '등록 정보 저장'
                                  : '시작프로그램 등록',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _startupBusy ||
                                    _startupStatus?.registered != true
                                ? null
                                : _unregisterStartup,
                            child: const Text('등록 삭제'),
                          ),
                        ],
                      ),
                    ],
                    if (widget.adminApiController != null) ...[
                      const Divider(height: 28),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('관리 API / 관리자 페이지'),
                        subtitle: Text(
                          widget.adminApiController!.running
                              ? '실행 중 · ${widget.adminApiController!.address}'
                              : widget.adminApiController!.lastError ??
                                  '사용 안 함',
                        ),
                        value: _adminApiEnabled,
                        onChanged: widget.adminApiController!.busy
                            ? null
                            : (value) =>
                                setState(() => _adminApiEnabled = value),
                      ),
                      TextField(
                        controller: _adminApiPortController,
                        enabled: !widget.adminApiController!.busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '관리 API 포트',
                          helperText: '기본값 80 · 변경 시 서버가 즉시 재시작됩니다.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('mDNS 자동 발견'),
                        subtitle: Text(
                          widget.adminApiController!.mdnsError ??
                              (_mdnsEnabled
                                  ? 'http://${_mdnsHostnameController.text.trim()}'
                                  : '사용 안 함'),
                        ),
                        value: _mdnsEnabled,
                        onChanged: widget.adminApiController!.busy
                            ? null
                            : (value) => setState(() => _mdnsEnabled = value),
                      ),
                      TextField(
                        controller: _mdnsHostnameController,
                        enabled:
                            _mdnsEnabled && !widget.adminApiController!.busy,
                        decoration: const InputDecoration(
                          labelText: 'mDNS 호스트 이름',
                          helperText: '기본값 ysignage.local · 같은 네트워크에서 접속할 주소',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: widget.adminApiController!.busy
                              ? null
                              : _saveAdminApi,
                          child: const Text('관리 API 설정 저장'),
                        ),
                      ),
                    ],
                    const Divider(height: 28),
                    Text('현재 버전: ${controller.currentVersion}'),
                    Text(
                      '사용 가능한 버전: '
                      '${controller.available?.manifest.version ?? '-'}',
                    ),
                    Text(
                      '마지막 확인: '
                      '${controller.lastCheckedAt?.toLocal().toString() ?? '-'}',
                    ),
                    Text('상태: ${controller.status}'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: controller.busy ? null : controller.check,
                          child: const Text('지금 업데이트 확인'),
                        ),
                        FilledButton.tonal(
                          onPressed:
                              controller.busy || controller.available == null
                                  ? null
                                  : controller.download,
                          child: const Text('다운로드'),
                        ),
                        FilledButton(
                          onPressed: controller.busy ||
                                  controller.downloadedPackage == null
                              ? null
                              : controller.installNow,
                          child: const Text('지금 설치'),
                        ),
                        OutlinedButton(
                          onPressed: controller.busy
                              ? null
                              : controller.exportDiagnostics,
                          child: const Text('진단 자료 내보내기'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton.icon(
                onPressed: widget.onExit == null ? null : _confirmExit,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('완전 종료'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      );
}
