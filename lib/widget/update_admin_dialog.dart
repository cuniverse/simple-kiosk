import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

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
      builder: (context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => AlertDialog(
          title: const Text('자동 업데이트 관리'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('자동 업데이트'),
                  subtitle: const Text('기본값 OFF · stable 채널'),
                  value: controller.policy.enabled,
                  onChanged: controller.busy ? null : controller.setEnabled,
                ),
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
                      onPressed: controller.busy || controller.available == null
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
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
}
