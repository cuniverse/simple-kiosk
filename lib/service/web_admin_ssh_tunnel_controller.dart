import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app_logger.dart';

enum WebAdminSshTunnelStatus {
  disabled,
  keyMissing,
  connecting,
  connected,
  reconnecting,
  error,
}

class WebAdminSshTunnelController extends ChangeNotifier {
  static const host = '115.68.223.143';
  static const port = 22;
  static const username = 'tunnel';
  static const socketDirectory = '/run/signage';
  static const idPrefix = 'ysignage';
  static const domainSuffix = 'signage.cuniverse.net';
  static const privateKeyAsset = 'assets/ssh/web-admin-tunnel-key';
  static const _retryDelay = Duration(seconds: 10);
  static const _connectTimeout = Duration(seconds: 12);
  static const _initialHealthCheckDelay = Duration(seconds: 2);
  static const _healthCheckInterval = Duration(seconds: 30);
  static const _healthCheckTimeout = Duration(seconds: 8);
  static const _maximumId = 9999;

  WebAdminSshTunnelStatus status = WebAdminSshTunnelStatus.disabled;
  String? assignedId;
  String? lastError;
  bool forwardingVerified = false;
  DateTime? lastForwardingVerifiedAt;

  SSHClient? _client;
  StreamSubscription<SSHForwardChannel>? _forwardSubscription;
  Timer? _retryTimer;
  Timer? _healthCheckTimer;
  int _generation = 0;
  int _localPort = 80;
  String? _preferredId;
  Future<void> Function(String id)? _onIdAssigned;

  bool get connected => status == WebAdminSshTunnelStatus.connected;

  Uri? get remoteUri {
    final id = assignedId;
    return id == null ? null : Uri.parse('http://$id.$domainSuffix/');
  }

  String get statusText => switch (status) {
        WebAdminSshTunnelStatus.disabled => '사용 안 함',
        WebAdminSshTunnelStatus.keyMissing => 'SSH 접속 키가 포함되지 않음',
        WebAdminSshTunnelStatus.connecting => '접속 및 주소 배정 중',
        WebAdminSshTunnelStatus.connected => '연결됨',
        WebAdminSshTunnelStatus.reconnecting => '연결 재시도 중',
        WebAdminSshTunnelStatus.error => lastError ?? '연결 실패',
      };

  String get forwardingStateText {
    if (status != WebAdminSshTunnelStatus.connected) {
      return '실제 reverse forwarding: 끊김 · $statusText';
    }
    if (!forwardingVerified) {
      return '실제 reverse forwarding: 외부 접속 확인 중';
    }
    final verifiedAt = lastForwardingVerifiedAt?.toLocal();
    return verifiedAt == null
        ? '실제 reverse forwarding: 정상'
        : '실제 reverse forwarding: 정상 · 마지막 확인 $verifiedAt';
  }

  @visibleForTesting
  static Iterable<String> candidateIds(String? preferredId) sync* {
    if (preferredId != null &&
        RegExp(r'^ysignage[1-9][0-9]*$').hasMatch(preferredId)) {
      yield preferredId;
    }
    for (var number = 1; number <= _maximumId; number++) {
      final candidate = '$idPrefix$number';
      if (candidate != preferredId) yield candidate;
    }
  }

  Future<void> start({
    required int localPort,
    required String? preferredId,
    required Future<void> Function(String id) onIdAssigned,
  }) async {
    await stop(notify: false);
    _localPort = localPort;
    _preferredId = preferredId;
    assignedId = preferredId;
    _onIdAssigned = onIdAssigned;
    status = WebAdminSshTunnelStatus.connecting;
    lastError = null;
    notifyListeners();
    final generation = _generation;
    unawaited(_connect(generation, reconnecting: false));
  }

  Future<void> stop({bool notify = true}) async {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    final forwardSubscription = _forwardSubscription;
    _forwardSubscription = null;
    final client = _client;
    _client = null;
    status = WebAdminSshTunnelStatus.disabled;
    lastError = null;
    forwardingVerified = false;
    if (notify) notifyListeners();
    await forwardSubscription?.cancel();
    if (client != null && !client.isClosed) await client.close();
  }

  Future<void> _connect(int generation, {required bool reconnecting}) async {
    if (generation != _generation) return;
    status = reconnecting
        ? WebAdminSshTunnelStatus.reconnecting
        : WebAdminSshTunnelStatus.connecting;
    lastError = null;
    notifyListeners();

    String privateKey;
    try {
      privateKey = await rootBundle.loadString(privateKeyAsset);
    } on FlutterError catch (error) {
      if (generation != _generation) return;
      status = WebAdminSshTunnelStatus.keyMissing;
      lastError = '$error';
      forwardingVerified = false;
      notifyListeners();
      _retryTimer = Timer(_retryDelay, () {
        _retryTimer = null;
        unawaited(_connect(generation, reconnecting: true));
      });
      return;
    }

    SSHClient? client;
    try {
      final identities = SSHKeyPair.fromPem(privateKey);
      if (identities.isEmpty) throw const FormatException('SSH 개인 키가 비어 있습니다.');
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: _connectTimeout,
      );
      client = SSHClient(
        socket,
        username: username,
        identities: identities,
        keepAliveInterval: const Duration(seconds: 30),
        handshakeTimeout: _connectTimeout,
        authTimeout: _connectTimeout,
        ident: 'YSignage',
      );
      await client.authenticated;
      if (generation != _generation) {
        await client.close();
        return;
      }

      SSHRemoteUnixForward? forward;
      String? selectedId;
      for (final id in candidateIds(_preferredId)) {
        final candidate = await client.forwardRemoteUnix(
          '$socketDirectory/$id.sock',
        );
        if (candidate != null) {
          forward = candidate;
          selectedId = id;
          break;
        }
      }
      if (forward == null || selectedId == null) {
        throw StateError('사용 가능한 원격 WEB 관리자 ID가 없습니다.');
      }
      if (generation != _generation) {
        await client.close();
        return;
      }

      _client = client;
      assignedId = selectedId;
      _preferredId = selectedId;
      status = WebAdminSshTunnelStatus.connected;
      lastError = null;
      forwardingVerified = false;
      _forwardSubscription = forward.connections.listen(
        _forwardConnection,
        onError: (Object error, StackTrace stackTrace) =>
            AppLogger.error(LogCategory.api, error, stackTrace),
      );
      notifyListeners();
      await _onIdAssigned?.call(selectedId);
      _scheduleHealthCheck(generation, _initialHealthCheckDelay);

      client.done.then(
        (_) => _scheduleReconnect(generation, 'SSH 연결이 종료되었습니다.'),
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.error(LogCategory.api, error, stackTrace);
          _scheduleReconnect(generation, '$error');
        },
      );
    } catch (error, stackTrace) {
      if (client != null) await client.close();
      if (generation != _generation) return;
      AppLogger.error(LogCategory.api, error, stackTrace);
      _scheduleReconnect(generation, '$error');
    }
  }

  void _forwardConnection(SSHForwardChannel channel) {
    unawaited(_bridgeToLocalAdmin(channel));
  }

  Future<void> _bridgeToLocalAdmin(SSHForwardChannel channel) async {
    Socket? local;
    try {
      local = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _localPort,
        timeout: const Duration(seconds: 5),
      );
      await Future.wait<void>([
        channel.stream.cast<List<int>>().pipe(local),
        local.cast<List<int>>().pipe(channel.sink),
      ]);
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.api, error, stackTrace);
    } finally {
      local?.destroy();
      channel.destroy();
    }
  }

  void _scheduleReconnect(int generation, String error) {
    if (generation != _generation || _retryTimer != null) return;
    _client = null;
    final forwardSubscription = _forwardSubscription;
    _forwardSubscription = null;
    unawaited(forwardSubscription?.cancel());
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    status = WebAdminSshTunnelStatus.reconnecting;
    lastError = error;
    forwardingVerified = false;
    notifyListeners();
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      unawaited(_connect(generation, reconnecting: true));
    });
  }

  void _scheduleHealthCheck(int generation, Duration delay) {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer(delay, () {
      _healthCheckTimer = null;
      unawaited(_verifyForwarding(generation));
    });
  }

  Future<void> _verifyForwarding(int generation) async {
    if (generation != _generation ||
        status != WebAdminSshTunnelStatus.connected) {
      return;
    }
    final uri = remoteUri;
    final sshClient = _client;
    if (uri == null || sshClient == null || sshClient.isClosed) {
      _scheduleReconnect(generation, 'SSH forwarding 연결이 없습니다.');
      return;
    }

    Socket? probeSocket;
    try {
      probeSocket = await Socket.connect(
        uri.host,
        uri.hasPort ? uri.port : 80,
        timeout: _healthCheckTimeout,
      );
      final requestPath = uri.hasQuery
          ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}'
          : (uri.path.isEmpty ? '/' : uri.path);
      probeSocket.write(
        'GET $requestPath HTTP/1.1\r\n'
        'Host: ${uri.host}\r\n'
        'Connection: close\r\n\r\n',
      );
      await probeSocket.flush().timeout(_healthCheckTimeout);
      final statusLine =
          await readHttpStatusLine(probeSocket).timeout(_healthCheckTimeout);
      final statusMatch =
          RegExp(r'^HTTP/1\.[01] ([0-9]{3})').firstMatch(statusLine);
      final statusCode = int.tryParse(statusMatch?.group(1) ?? '');
      if (statusCode != HttpStatus.ok) {
        throw HttpException(
          'forwarding 확인 HTTP ${statusCode ?? statusLine}',
          uri: uri,
        );
      }
      if (generation != _generation) return;
      forwardingVerified = true;
      lastForwardingVerifiedAt = DateTime.now();
      lastError = null;
      notifyListeners();
      _scheduleHealthCheck(generation, _healthCheckInterval);
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      AppLogger.error(LogCategory.api, error, stackTrace);
      _scheduleReconnect(generation, '실제 forwarding 확인 실패: $error');
      if (!sshClient.isClosed) await sshClient.close();
    } finally {
      probeSocket?.destroy();
    }
  }

  @override
  void dispose() {
    unawaited(stop(notify: false));
    super.dispose();
  }
}

/// HTTP 응답의 첫 줄만 바이트 단위로 읽는다.
///
/// 응답 본문의 UTF-8 문자가 소켓 청크 경계에서 잘려도 상태 확인이 실패하거나
/// 정상 포워딩을 재연결하지 않도록 본문을 문자열로 디코딩하지 않는다.
Future<String> readHttpStatusLine(Stream<List<int>> stream) async {
  final iterator = StreamIterator<List<int>>(stream);
  final bytes = <int>[];
  try {
    while (await iterator.moveNext()) {
      for (final byte in iterator.current) {
        if (byte == 0x0a) return latin1.decode(bytes).trimRight();
        if (byte != 0x0d) bytes.add(byte);
        if (bytes.length > 1024) {
          throw const FormatException('HTTP 상태 줄이 너무 깁니다.');
        }
      }
    }
    throw const FormatException('HTTP 상태 줄을 받지 못했습니다.');
  } finally {
    await iterator.cancel();
  }
}
