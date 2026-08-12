import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../model/update_policy.dart';
import '../service/update_controller.dart';

class UpdateAdminDialog {
  static String? get _configuredHash {
    final value = Platform.environment['SIMPLE_KIOSK_ADMIN_PIN_HASH'];
    if (value == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      return null;
    }
    return value.toLowerCase();
  }

  static bool get isConfigured => _configuredHash != null;

  static Future<void> show(
    BuildContext context,
    UpdateController controller,
  ) async {
    final expected = _configuredHash;
    if (expected == null) return;
    final pinController = TextEditingController();
    final authenticated = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('관리자 PIN'),
        content: TextField(
          controller: pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    final actual = sha256.convert(utf8.encode(pinController.text)).toString();
    pinController.dispose();
    if (authenticated != true || actual != expected || !context.mounted) {
      if (authenticated == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('관리자 PIN이 올바르지 않습니다.')),
        );
      }
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _UpdateAdminPanel(controller: controller),
    );
  }
}

class _UpdateAdminPanel extends StatefulWidget {
  final UpdateController controller;

  const _UpdateAdminPanel({required this.controller});

  @override
  State<_UpdateAdminPanel> createState() => _UpdateAdminPanelState();
}

class _UpdateAdminPanelState extends State<_UpdateAdminPanel> {
  late bool _enabled;
  late bool _installWhenIdle;
  late int _checkIntervalHours;
  late int _retainVersions;
  late int _logRetentionDays;
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  @override
  void initState() {
    super.initState();
    final policy = widget.controller.policy;
    _enabled = policy.enabled;
    _installWhenIdle = policy.installWhenIdle;
    _checkIntervalHours = policy.checkIntervalHours;
    _retainVersions = policy.retainVersions;
    _logRetentionDays = policy.logRetentionDays;
    _startController = TextEditingController(text: policy.installWindow.start);
    _endController = TextEditingController(text: policy.installWindow.end);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return AlertDialog(
            title: const Text('자동 업데이트 관리'),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      );
}
