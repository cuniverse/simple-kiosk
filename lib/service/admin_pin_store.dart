import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'runtime_paths.dart';

class AdminPinStore {
  static const String defaultPin = '1259';
  static const int _schemaVersion = 1;
  static const int _defaultIterations = 120000;

  final File? _file;
  final Random _random;
  final int _iterations;

  AdminPinStore({File? file, Random? random, int? iterations})
      : _file = file,
        _random = random ?? Random.secure(),
        _iterations = iterations ?? _defaultIterations;

  File? get _pinFile {
    if (_file != null) return _file;
    final path = RuntimePaths.adminPin;
    return path == null ? null : File(path);
  }

  Future<bool> get hasCustomPin async {
    final file = _pinFile;
    return file != null && await file.exists();
  }

  Future<bool> verify(String pin) async {
    final file = _pinFile;
    if (file == null || !await file.exists()) {
      return _constantTimeEquals(
        utf8.encode(pin),
        utf8.encode(defaultPin),
      );
    }

    try {
      final decoded = json.decode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != _schemaVersion ||
          decoded['algorithm'] != 'PBKDF2-HMAC-SHA256' ||
          decoded['iterations'] is! int ||
          decoded['salt'] is! String ||
          decoded['hash'] is! String) {
        return false;
      }
      final iterations = decoded['iterations'] as int;
      if (iterations < 1) return false;
      final salt = base64.decode(decoded['salt'] as String);
      final expected = base64.decode(decoded['hash'] as String);
      final actual = _deriveKey(pin, salt, iterations, expected.length);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  Future<void> changePin(String pin) async {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw const FormatException('관리자 PIN은 숫자 4~12자리여야 합니다.');
    }
    final file = _pinFile;
    if (file == null) {
      throw UnsupportedError('관리자 PIN 저장 경로를 사용할 수 없습니다.');
    }
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    final hash = _deriveKey(pin, salt, _iterations, 32);
    await RuntimePaths.atomicWrite(
      file.path,
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': _schemaVersion,
        'algorithm': 'PBKDF2-HMAC-SHA256',
        'iterations': _iterations,
        'salt': base64.encode(salt),
        'hash': base64.encode(hash),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Uint8List _deriveKey(
    String pin,
    List<int> salt,
    int iterations,
    int length,
  ) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final output = BytesBuilder(copy: false);
    var blockIndex = 1;
    while (output.length < length) {
      final blockSalt = <int>[
        ...salt,
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ];
      var u = hmac.convert(blockSalt).bytes;
      final block = Uint8List.fromList(u);
      for (var round = 1; round < iterations; round++) {
        u = hmac.convert(u).bytes;
        for (var i = 0; i < block.length; i++) {
          block[i] ^= u[i];
        }
      }
      output.add(block);
      blockIndex++;
    }
    return Uint8List.fromList(output.toBytes().take(length).toList());
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var i = 0; i < length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}
