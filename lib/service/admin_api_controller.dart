import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../model/admin_api_settings.dart';
import 'admin_api_settings_store.dart';
import 'admin_pin_store.dart';

typedef AdminStatusProvider = Future<Map<String, dynamic>> Function();
typedef AdminActionHandler = Future<Map<String, dynamic>> Function(
  String action,
);
typedef AdminConfigReader = Future<Map<String, dynamic>> Function();
typedef AdminConfigWriter = Future<void> Function(Map<String, dynamic> config);

class AdminApiController extends ChangeNotifier {
  AdminApiController({
    required this.statusProvider,
    required this.actionHandler,
    required this.configReader,
    required this.configWriter,
    AdminPinStore? pinStore,
    AdminApiSettingsStore? settingsStore,
    Future<String> Function()? pageLoader,
  })  : _pinStore = pinStore ?? AdminPinStore(),
        _settingsStore = settingsStore ?? const AdminApiSettingsStore(),
        _pageLoader = pageLoader ?? _loadDefaultPage;

  static const int _maxBodyBytes = 1024 * 1024;
  static const Duration _sessionLifetime = Duration(hours: 12);
  static const Duration _attemptWindow = Duration(minutes: 5);
  static const int _maxFailedAttempts = 10;

  final AdminStatusProvider statusProvider;
  final AdminActionHandler actionHandler;
  final AdminConfigReader configReader;
  final AdminConfigWriter configWriter;
  final AdminPinStore _pinStore;
  final AdminApiSettingsStore _settingsStore;
  final Future<String> Function() _pageLoader;
  final Random _random = Random.secure();
  final Map<String, DateTime> _sessions = {};
  final Map<String, List<DateTime>> _failedAttempts = {};

  AdminApiSettings settings = const AdminApiSettings();
  HttpServer? _server;
  String? lastError;
  bool busy = false;

  bool get running => _server != null;
  int? get actualPort => _server?.port;
  String get address => running ? 'http://<이 PC 주소>:${_server!.port}' : '-';

  Future<void> initialize() async {
    settings = await _settingsStore.load();
    if (settings.enabled) await _start();
    notifyListeners();
  }

  Future<void> updateSettings(AdminApiSettings updated) async {
    if (updated.port < 1 || updated.port > 65535) {
      throw const FormatException('관리 API 포트는 1~65535여야 합니다.');
    }
    busy = true;
    notifyListeners();
    try {
      await _settingsStore.save(updated);
      await _stop();
      settings = updated;
      lastError = null;
      if (settings.enabled) await _start();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    await _stop();
    _sessions.clear();
    _failedAttempts.clear();
  }

  Future<void> _start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, settings.port);
      _server!.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error, StackTrace stackTrace) {
          lastError = '$error';
          notifyListeners();
        },
      );
      lastError = null;
    } catch (error) {
      _server = null;
      lastError = '포트 ${settings.port}에서 관리 API를 시작하지 못했습니다: $error';
    }
  }

  Future<void> _stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      _setSecurityHeaders(request.response);
      final path = request.uri.path;
      if (request.method == 'GET' && (path == '/' || path == '/admin')) {
        return await _sendHtml(request.response, await _pageLoader());
      }
      if (request.method == 'GET' && path == '/favicon.ico') {
        final data =
            await rootBundle.load('assets/icons/simple-kiosk-logo.png');
        return await _sendBytes(
          request.response,
          data.buffer.asUint8List(),
          ContentType('image', 'png'),
        );
      }
      if (request.method == 'POST' && path == '/api/login') {
        return await _login(request);
      }
      if (!path.startsWith('/api/')) {
        return await _sendJson(request.response, 404, {'error': 'not-found'});
      }
      final sessionToken = await _authenticate(request);
      if (sessionToken == null) return;

      if (request.method == 'POST' && path == '/api/logout') {
        _sessions.remove(sessionToken);
        return await _sendJson(request.response, 200, {'ok': true});
      }
      if (request.method == 'GET' && path == '/api/status') {
        final status = await statusProvider();
        return await _sendJson(request.response, 200, {
          ...status,
          'adminApi': {
            'enabled': settings.enabled,
            'configuredPort': settings.port,
            'actualPort': actualPort,
            'running': running,
            'error': lastError,
          },
        });
      }
      if (request.method == 'GET' && path == '/api/config') {
        return await _sendJson(request.response, 200, await configReader());
      }
      if (request.method == 'PUT' && path == '/api/config') {
        final body = await _readJsonObject(request);
        await configWriter(body);
        return await _sendJson(request.response, 200, {
          'ok': true,
          'message': '설정을 저장하고 키오스크에 적용했습니다.',
        });
      }
      if (request.method == 'GET' && path == '/api/server-settings') {
        return await _sendJson(request.response, 200, settings.toJson());
      }
      if (request.method == 'PUT' && path == '/api/server-settings') {
        final body = await _readJsonObject(request);
        final updated = AdminApiSettings.fromJson(body);
        await _sendJson(request.response, 202, {
          'ok': true,
          'message': '관리 API가 새 설정으로 다시 시작됩니다.',
          'settings': updated.toJson(),
        });
        unawaited(Future<void>.delayed(
          const Duration(milliseconds: 300),
          () => updateSettings(updated),
        ));
        return;
      }
      if (request.method == 'POST' && path.startsWith('/api/actions/')) {
        final action = path.substring('/api/actions/'.length);
        const allowed = {'show', 'hide', 'restart', 'shutdown', 'update'};
        if (!allowed.contains(action)) {
          return await _sendJson(
            request.response,
            404,
            {'error': 'unknown-action'},
          );
        }
        final result = await actionHandler(action);
        return await _sendJson(
          request.response,
          202,
          {'ok': true, ...result},
        );
      }
      return await _sendJson(
        request.response,
        405,
        {'error': 'method-not-allowed'},
      );
    } on FormatException catch (error) {
      try {
        await _sendJson(request.response, 400, {'error': error.message});
      } catch (_) {}
    } catch (error) {
      try {
        await _sendJson(request.response, 500, {'error': '$error'});
      } catch (_) {}
    }
  }

  Future<void> _login(HttpRequest request) async {
    final address = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    if (_isRateLimited(address)) {
      return _sendJson(request.response, 429, {
        'error': 'too-many-attempts',
        'message': '잠시 후 다시 시도하세요.',
      });
    }
    final body = await _readJsonObject(request, maxBytes: 4096);
    final pin = body['pin'];
    if (pin is! String || !await _pinStore.verify(pin)) {
      _recordFailedAttempt(address);
      return _sendJson(request.response, 401, {
        'error': 'invalid-pin',
        'message': '관리자 PIN이 올바르지 않습니다.',
      });
    }
    _failedAttempts.remove(address);
    _removeExpiredSessions();
    final token = base64Url.encode(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    _sessions[token] = DateTime.now().add(_sessionLifetime);
    await _sendJson(request.response, 200, {
      'ok': true,
      'token': token,
      'expiresInSeconds': _sessionLifetime.inSeconds,
    });
  }

  Future<String?> _authenticate(HttpRequest request) async {
    _removeExpiredSessions();
    final address = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    if (_isRateLimited(address)) {
      await _sendJson(request.response, 429, {
        'error': 'too-many-attempts',
        'message': '잠시 후 다시 시도하세요.',
      });
      return null;
    }
    final authorization =
        request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization != null && authorization.startsWith('Bearer ')) {
      final token = authorization.substring(7).trim();
      if (_sessions.containsKey(token)) return token;
    }

    String? pin = request.headers.value('x-admin-pin');
    if (pin == null &&
        authorization != null &&
        authorization.startsWith('Basic ')) {
      try {
        final decoded = utf8.decode(base64.decode(authorization.substring(6)));
        final separator = decoded.indexOf(':');
        if (separator >= 0) pin = decoded.substring(separator + 1);
      } catch (_) {
        pin = null;
      }
    }
    if (pin != null && await _pinStore.verify(pin)) {
      _failedAttempts.remove(address);
      return '';
    }
    _recordFailedAttempt(address);
    await _sendJson(request.response, 401, {
      'error': 'unauthorized',
      'message': '관리자 PIN 인증이 필요합니다.',
    });
    return null;
  }

  bool _isRateLimited(String address) {
    final cutoff = DateTime.now().subtract(_attemptWindow);
    final attempts = _failedAttempts[address] ?? <DateTime>[];
    attempts.removeWhere((attempt) => attempt.isBefore(cutoff));
    _failedAttempts[address] = attempts;
    return attempts.length >= _maxFailedAttempts;
  }

  void _recordFailedAttempt(String address) {
    (_failedAttempts[address] ??= <DateTime>[]).add(DateTime.now());
  }

  void _removeExpiredSessions() {
    final now = DateTime.now();
    _sessions.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  Future<Map<String, dynamic>> _readJsonObject(
    HttpRequest request, {
    int maxBytes = _maxBodyBytes,
  }) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('요청 본문이 너무 큽니다.');
      }
    }
    final decoded = json.decode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON 객체가 필요합니다.');
    }
    return decoded;
  }

  void _setSecurityHeaders(HttpResponse response) {
    response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('X-Frame-Options', 'DENY')
      ..set(
        'Content-Security-Policy',
        "default-src 'self'; style-src 'self' 'unsafe-inline'; "
            "script-src 'self' 'unsafe-inline'; connect-src 'self'",
      );
  }

  Future<void> _sendHtml(HttpResponse response, String html) async {
    response.statusCode = 200;
    response.headers.contentType = ContentType.html;
    response.write(html);
    await response.close();
  }

  Future<void> _sendBytes(
    HttpResponse response,
    List<int> bytes,
    ContentType contentType,
  ) async {
    response.statusCode = 200;
    response.headers.contentType = contentType;
    response.add(bytes);
    await response.close();
  }

  Future<void> _sendJson(
    HttpResponse response,
    int statusCode,
    Object body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(json.encode(body));
    await response.close();
  }

  static Future<String> _loadDefaultPage() =>
      rootBundle.loadString('assets/admin/index.html');
}
