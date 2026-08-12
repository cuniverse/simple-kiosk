import 'dart:convert';
import 'dart:io';

import '../model/update_policy.dart';
import 'runtime_paths.dart';

class UpdatePolicyStore {
  static Future<UpdatePolicy> load() async {
    await RuntimePaths.ensureStructure();
    final path = RuntimePaths.updatePolicy;
    if (path == null) return const UpdatePolicy();
    final file = File(path);
    if (!await file.exists()) {
      const policy = UpdatePolicy();
      await save(policy);
      return policy;
    }
    final decoded = json.decode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('update-policy.json: 객체 필요');
    }
    return UpdatePolicy.fromJson(decoded);
  }

  static Future<void> save(UpdatePolicy policy) async {
    final path = RuntimePaths.updatePolicy;
    if (path == null) return;
    await RuntimePaths.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(policy.toJson()),
    );
  }
}
