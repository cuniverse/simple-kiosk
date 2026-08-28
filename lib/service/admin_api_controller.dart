import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../model/admin_api_settings.dart';
import 'admin_api_settings_store.dart';
import 'admin_pin_store.dart';
import 'app_logger.dart';
import 'configuration_backup_service.dart';
import 'diagnostics_service.dart';
import 'exdata_file_service.dart';
import 'menu_config_loader.dart';
import 'mdns_service_controller.dart';
import 'screen_preview_service.dart';
import 'ui_theme_service.dart';
import 'web_admin_ssh_tunnel_controller.dart';

typedef AdminStatusProvider = Future<Map<String, dynamic>> Function();
typedef AdminActionHandler = Future<Map<String, dynamic>> Function(
  String action,
);
typedef AdminConfigReader = Future<Map<String, dynamic>> Function();
typedef AdminConfigWriter = Future<void> Function(Map<String, dynamic> config);
typedef AdminNetworkSettingsSynchronizer = Future<void> Function(
  AdminApiSettings settings,
);

class AdminApiController extends ChangeNotifier {
  AdminApiController({
    required this.statusProvider,
    required this.actionHandler,
    required this.configReader,
    required this.configWriter,
    AdminConfigReader? effectiveConfigReader,
    AdminConfigReader? defaultConfigReader,
    AdminPinStore? pinStore,
    AdminApiSettingsStore? settingsStore,
    Future<String> Function()? pageLoader,
    MdnsPublisher? mdnsPublisher,
    ConfigurationBackupService? backupService,
    DiagnosticsService? diagnosticsService,
    ExdataFileService? exdataFileService,
    UiThemeService? uiThemeService,
    WebAdminSshTunnelController? webAdminSshTunnelController,
    Future<void> Function()? onConfigurationImported,
    AdminNetworkSettingsSynchronizer? beforeNetworkStart,
    ScreenPreviewService? screenPreviewService,
  })  : _effectiveConfigReader = effectiveConfigReader ?? configReader,
        _defaultConfigReader =
            defaultConfigReader ?? effectiveConfigReader ?? configReader,
        _pinStore = pinStore ?? AdminPinStore(),
        _settingsStore = settingsStore ?? const AdminApiSettingsStore(),
        _pageLoader = pageLoader ?? _loadDefaultPage,
        _mdnsPublisher = mdnsPublisher ?? MdnsServiceController(),
        _backupService = backupService,
        _diagnosticsService = diagnosticsService ?? const DiagnosticsService(),
        _exdataFileService = exdataFileService ?? ExdataFileService(),
        _uiThemeService = uiThemeService ?? UiThemeService(),
        _webAdminSshTunnelController =
            webAdminSshTunnelController ?? WebAdminSshTunnelController(),
        _onConfigurationImported = onConfigurationImported,
        _beforeNetworkStart = beforeNetworkStart,
        _screenPreviewService = screenPreviewService ?? ScreenPreviewService() {
    _webAdminSshTunnelController.addListener(_handleSshTunnelChanged);
  }

  static const int _maxBodyBytes = 1024 * 1024;
  static const Duration _sessionLifetime = Duration(minutes: 30);
  static const Duration _attemptWindow = Duration(minutes: 5);
  static const int _maxFailedAttempts = 10;
  // 설정 재적용으로 컨트롤러가 교체될 때 이전 인스턴스의 SSH/mDNS/HTTP
  // 종료가 끝난 뒤 새 인스턴스가 같은 포트를 열도록 프로세스 전체에서
  // 네트워크 생명주기를 직렬화한다.
  static Future<void> _networkLifecycleQueue = Future<void>.value();

  final AdminStatusProvider statusProvider;
  final AdminActionHandler actionHandler;
  final AdminConfigReader configReader;
  final AdminConfigWriter configWriter;
  final AdminConfigReader _effectiveConfigReader;
  final AdminConfigReader _defaultConfigReader;
  final AdminPinStore _pinStore;
  final AdminApiSettingsStore _settingsStore;
  final Future<String> Function() _pageLoader;
  final MdnsPublisher _mdnsPublisher;
  final ConfigurationBackupService? _backupService;
  final DiagnosticsService _diagnosticsService;
  final ExdataFileService _exdataFileService;
  final UiThemeService _uiThemeService;
  final WebAdminSshTunnelController _webAdminSshTunnelController;
  final Future<void> Function()? _onConfigurationImported;
  final AdminNetworkSettingsSynchronizer? _beforeNetworkStart;
  final ScreenPreviewService _screenPreviewService;
  final Random _random = Random.secure();
  // 메뉴 설정 적용 시 KioskHome과 API 컨트롤러가 재생성되더라도 같은 프로그램
  // 프로세스 안에서는 로그인 세션과 시도 제한을 유지한다.
  static final Map<String, DateTime> _sessions = {};
  static final Map<String, List<DateTime>> _failedAttempts = {};

  AdminApiSettings settings = const AdminApiSettings();
  HttpServer? _server;
  String? lastError;
  String? mdnsError;
  bool busy = false;

  bool get running => _server != null;
  int? get actualPort => _server?.port;
  bool get mdnsRunning => _mdnsPublisher.running;
  WebAdminSshTunnelController get webAdminSshTunnel =>
      _webAdminSshTunnelController;
  Uri? get webAdminSshRemoteUri {
    final liveUri = _webAdminSshTunnelController.remoteUri;
    if (liveUri != null) return liveUri;
    final id = settings.webAdminSshForwardingId;
    return id == null
        ? null
        : Uri.parse(
            'http://$id.${WebAdminSshTunnelController.domainSuffix}/',
          );
  }

  String get address {
    if (!running) return '-';
    final portSuffix = _server!.port == 80 ? '' : ':${_server!.port}';
    return settings.mdnsEnabled && mdnsRunning
        ? 'http://${settings.mdnsHostname}$portSuffix'
        : 'http://<이 PC 주소>$portSuffix';
  }

  Future<void> initialize() async {
    await _exdataFileService.ensureReady();
    await _uiThemeService.ensureReady();
    settings = await _settingsStore.load();
    await _beforeNetworkStart?.call(settings);
    await _serializeNetworkLifecycle(() async {
      if (settings.enabled) await _start();
    });
    notifyListeners();
  }

  Future<void> updateSettings(AdminApiSettings updated) async {
    await _validateSettings(updated);
    await _serializeNetworkLifecycle(() async {
      final previous = settings;
      busy = true;
      notifyListeners();
      try {
        await _settingsStore.save(updated);
        settings = updated;
        await _beforeNetworkStart?.call(settings);
        await _stop();
        lastError = null;
        if (settings.enabled) await _start(throwOnFailure: true);
      } catch (error, stackTrace) {
        try {
          await _stop();
        } catch (stopError, stopStackTrace) {
          AppLogger.error(LogCategory.api, stopError, stopStackTrace);
        }
        settings = previous;
        try {
          await _settingsStore.save(previous);
          await _beforeNetworkStart?.call(previous);
          if (previous.enabled) await _start(throwOnFailure: true);
        } catch (rollbackError, rollbackStackTrace) {
          AppLogger.error(LogCategory.api, rollbackError, rollbackStackTrace);
          lastError = '관리 API 설정 복구 실패: $rollbackError';
        }
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        busy = false;
        notifyListeners();
      }
    });
  }

  Future<void> _validateSettings(AdminApiSettings updated) async {
    if (updated.port < 1 || updated.port > 65535) {
      throw const FormatException('관리 API 포트는 1~65535여야 합니다.');
    }
    if (!AdminApiSettings.isValidMdnsHostname(updated.mdnsHostname)) {
      throw const FormatException(
        'mDNS 호스트 이름은 example.local 형식이어야 합니다.',
      );
    }
    if (!updated.enabled || (running && actualPort == updated.port)) return;
    ServerSocket? probe;
    try {
      probe = await ServerSocket.bind(InternetAddress.anyIPv4, updated.port);
    } on SocketException catch (error) {
      throw FormatException(
        '관리 API 포트 ${updated.port}을 사용할 수 없습니다: $error',
      );
    } finally {
      await probe?.close();
    }
  }

  Future<void> updateWebAdminSshForwardingEnabled(bool enabled) async {
    if (busy || settings.webAdminSshForwardingEnabled == enabled) return;
    busy = true;
    notifyListeners();
    try {
      settings = settings.copyWith(webAdminSshForwardingEnabled: enabled);
      await _settingsStore.save(settings);
      if (enabled && running) {
        await _startWebAdminSshTunnel();
      } else {
        await _webAdminSshTunnelController.stop();
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    await _serializeNetworkLifecycle(_stop);
  }

  Future<void> _serializeNetworkLifecycle(
    Future<void> Function() action,
  ) {
    final previous = _networkLifecycleQueue;
    final operation = () async {
      try {
        await previous;
      } catch (_) {
        // 앞선 컨트롤러의 실패가 다음 인스턴스의 복구 시작을 막지 않게 한다.
      }
      await action();
    }();
    _networkLifecycleQueue = () async {
      try {
        await operation;
      } catch (_) {
        // 호출자에게는 원래 오류를 전달하되 공유 큐는 계속 진행 가능하게 한다.
      }
    }();
    return operation;
  }

  Future<void> _start({bool throwOnFailure = false}) async {
    HttpServer? startedServer;
    try {
      startedServer =
          await HttpServer.bind(InternetAddress.anyIPv4, settings.port);
      _server = startedServer;
      _server!.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.error(LogCategory.api, error, stackTrace);
          lastError = '$error';
          notifyListeners();
        },
      );
      lastError = null;
      mdnsError = null;
      if (settings.mdnsEnabled) {
        try {
          await _mdnsPublisher.start(
            hostname: settings.mdnsHostname,
            port: _server!.port,
          );
        } catch (error) {
          mdnsError = 'mDNS를 시작하지 못했습니다: $error';
        }
      }
      if (settings.webAdminSshForwardingEnabled) {
        unawaited(_startWebAdminSshTunnel());
      }
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.api, error, stackTrace);
      await startedServer?.close(force: true);
      _server = null;
      lastError = '포트 ${settings.port}에서 관리 API를 시작하지 못했습니다: $error';
      if (throwOnFailure) rethrow;
    }
  }

  void _applySettingsLater(
    AdminApiSettings updated, {
    Future<void> Function()? afterApply,
  }) {
    unawaited(Future<void>.delayed(
      const Duration(milliseconds: 300),
      () async {
        try {
          await updateSettings(updated);
          await afterApply?.call();
        } catch (error, stackTrace) {
          AppLogger.error(LogCategory.api, error, stackTrace);
        }
      },
    ));
  }

  Future<void> _stop() async {
    await _webAdminSshTunnelController.stop();
    await _mdnsPublisher.stop();
    mdnsError = null;
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
  }

  Future<void> _startWebAdminSshTunnel() async {
    final port = actualPort;
    if (port == null || !settings.webAdminSshForwardingEnabled) return;
    await _webAdminSshTunnelController.start(
      localPort: port,
      preferredId: settings.webAdminSshForwardingId,
      onIdAssigned: (id) async {
        if (!settings.webAdminSshForwardingEnabled ||
            settings.webAdminSshForwardingId == id) {
          return;
        }
        settings = settings.copyWith(webAdminSshForwardingId: id);
        await _settingsStore.save(settings);
        notifyListeners();
      },
    );
  }

  void _handleSshTunnelChanged() => notifyListeners();

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
      if (request.method == 'POST' && path == '/api/session/refresh') {
        return await _sendJson(request.response, 200, {
          'ok': true,
          'expiresInSeconds': _sessionLifetime.inSeconds,
        });
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
            'mdnsEnabled': settings.mdnsEnabled,
            'mdnsHostname': settings.mdnsHostname,
            'mdnsRunning': mdnsRunning,
            'mdnsError': mdnsError,
            'webAdminSshForwarding': {
              'enabled': settings.webAdminSshForwardingEnabled,
              'id': settings.webAdminSshForwardingId,
              'status': _webAdminSshTunnelController.status.name,
              'url': _webAdminSshTunnelController.remoteUri?.toString(),
              'forwardingVerified':
                  _webAdminSshTunnelController.forwardingVerified,
              'forwardingState':
                  _webAdminSshTunnelController.forwardingStateText,
              'lastForwardingVerifiedAt': _webAdminSshTunnelController
                  .lastForwardingVerifiedAt
                  ?.toUtc()
                  .toIso8601String(),
              'error': _webAdminSshTunnelController.lastError,
            },
          },
        });
      }
      if (request.method == 'GET' && path == '/api/screen-preview') {
        try {
          final frame = await _screenPreviewService.capture(
            maxFramesPerSecond: settings.screenPreviewFps,
            maximumWidth: settings.screenPreviewWidth,
            jpegQuality: settings.screenPreviewJpegQuality,
          );
          request.response.headers
            ..set('X-Screen-Width', frame.width)
            ..set('X-Screen-Height', frame.height)
            ..set('X-Signage-State', frame.windowState.name)
            ..set('X-Captured-At', frame.capturedAt.toUtc().toIso8601String());
          return await _sendBytes(
            request.response,
            frame.jpegBytes,
            ContentType('image', 'jpeg'),
          );
        } on ScreenPreviewException catch (error) {
          final statusCode = error.code == 'unsupported' ? 501 : 409;
          if (error.windowState != null) {
            request.response.headers.set(
              'X-Signage-State',
              error.windowState!.name,
            );
          }
          return await _sendJson(request.response, statusCode, {
            'error': error.code,
            'message': error.message,
          });
        }
      }
      if (request.method == 'PUT' && path == '/api/screen-preview/settings') {
        final body = await _readJsonObject(request, maxBytes: 4096);
        final fps = body['fps'] ?? settings.screenPreviewFps;
        final width = body['width'] ?? settings.screenPreviewWidth;
        final quality = body['quality'] ?? settings.screenPreviewJpegQuality;
        if (fps is! int ||
            fps < 1 ||
            fps > AdminApiSettings.maxScreenPreviewFps) {
          return await _sendJson(request.response, 400, {
            'error': 'invalid-screen-preview-fps',
            'message': '화면 미리보기 FPS는 1~5 사이의 정수여야 합니다.',
          });
        }
        if (width is! int ||
            width < AdminApiSettings.minScreenPreviewWidth ||
            width > AdminApiSettings.maxScreenPreviewWidth) {
          return await _sendJson(request.response, 400, {
            'error': 'invalid-screen-preview-width',
            'message': '화면 미리보기 너비는 640~1920 사이의 정수여야 합니다.',
          });
        }
        if (quality is! int ||
            quality < AdminApiSettings.minScreenPreviewJpegQuality ||
            quality > AdminApiSettings.maxScreenPreviewJpegQuality) {
          return await _sendJson(request.response, 400, {
            'error': 'invalid-screen-preview-quality',
            'message': '화면 미리보기 JPEG 품질은 20~80 사이의 정수여야 합니다.',
          });
        }
        settings = settings.copyWith(
          screenPreviewFps: fps,
          screenPreviewWidth: width,
          screenPreviewJpegQuality: quality,
        );
        await _settingsStore.save(settings);
        notifyListeners();
        return await _sendJson(request.response, 200, {
          'ok': true,
          'fps': settings.screenPreviewFps,
          'width': settings.screenPreviewWidth,
          'quality': settings.screenPreviewJpegQuality,
        });
      }
      if (request.method == 'GET' && path == '/api/files/list') {
        final listing = await _exdataFileService.list(
          request.uri.queryParameters['path'] ?? '',
        );
        return await _sendJson(request.response, 200, listing.toJson());
      }
      if (request.method == 'GET' && path == '/api/files/download') {
        final download = await _exdataFileService.openDownload(
          request.uri.queryParameters['path'] ?? '',
        );
        request.response
          ..statusCode = 200
          ..contentLength = download.size
          ..headers.contentType = ContentType.binary
          ..headers.set(
            'Content-Disposition',
            'attachment; filename="download"; '
                "filename*=UTF-8''${Uri.encodeComponent(download.name)}",
          );
        await request.response.addStream(download.file.openRead());
        return await request.response.close();
      }
      if (request.method == 'PUT' && path == '/api/files/upload') {
        final relativePath = request.uri.queryParameters['path'] ?? '';
        final overwrite = request.uri.queryParameters['overwrite'] == 'true';
        final uploadId = request.uri.queryParameters['uploadId'];
        if (uploadId != null) {
          final offset = int.tryParse(
            request.uri.queryParameters['offset'] ?? '',
          );
          if (offset == null) {
            throw const ExdataFileException(
              400,
              'invalid-upload-offset',
              '올바르지 않은 업로드 위치입니다.',
            );
          }
          final result = await _exdataFileService.uploadChunk(
            relativePath,
            uploadId,
            offset,
            request,
            overwrite: overwrite,
            complete: request.uri.queryParameters['complete'] == 'true',
            contentLength:
                request.contentLength >= 0 ? request.contentLength : null,
          );
          return await _sendJson(
              request.response, result.complete ? 201 : 200, {
            'ok': true,
            'path': ExdataFileService.normalizeRelativePath(relativePath),
            'size': result.size,
            'complete': result.complete,
          });
        }
        final written = await _exdataFileService.upload(
          relativePath,
          request,
          overwrite: overwrite,
          contentLength:
              request.contentLength >= 0 ? request.contentLength : null,
        );
        return await _sendJson(request.response, 201, {
          'ok': true,
          'path': ExdataFileService.normalizeRelativePath(relativePath),
          'size': written,
        });
      }
      if (request.method == 'POST' && path == '/api/files/directory') {
        final body = await _readJsonObject(request, maxBytes: 16 * 1024);
        final relativePath = body['path'];
        if (relativePath is! String) {
          throw const FormatException('path 문자열이 필요합니다.');
        }
        await _exdataFileService.createDirectory(relativePath);
        return await _sendJson(request.response, 201, {
          'ok': true,
          'path': ExdataFileService.normalizeRelativePath(relativePath),
        });
      }
      if (request.method == 'POST' && path == '/api/files/move') {
        final body = await _readJsonObject(request, maxBytes: 32 * 1024);
        final source = body['source'];
        final destination = body['destination'];
        if (source is! String || destination is! String) {
          throw const FormatException('source와 destination 문자열이 필요합니다.');
        }
        if (ExdataFileService.normalizeRelativePath(source) !=
            ExdataFileService.normalizeRelativePath(destination)) {
          await _requireExdataPathUnused(source);
        }
        await _exdataFileService.move(source, destination);
        return await _sendJson(request.response, 200, {
          'ok': true,
          'source': ExdataFileService.normalizeRelativePath(source),
          'destination': ExdataFileService.normalizeRelativePath(destination),
        });
      }
      if (request.method == 'DELETE' && path == '/api/files') {
        final relativePath = request.uri.queryParameters['path'] ?? '';
        await _requireExdataPathUnused(relativePath);
        await _exdataFileService.delete(relativePath);
        return await _sendJson(request.response, 200, {'ok': true});
      }
      if (request.method == 'POST' && path == '/api/files/change-check') {
        final body = await _readJsonObject(request, maxBytes: 64 * 1024);
        final paths = body['paths'];
        if (paths is! List || paths.any((value) => value is! String)) {
          throw const FormatException('paths 문자열 배열이 필요합니다.');
        }
        for (final relativePath in paths.cast<String>()) {
          await _requireExdataPathUnused(relativePath);
        }
        return await _sendJson(request.response, 200, {'ok': true});
      }
      if (request.method == 'GET' && path == '/api/themes') {
        final themes = await _uiThemeService.list();
        return await _sendJson(request.response, 200, {
          'themes': themes.map((theme) => theme.toJson()).toList(),
        });
      }
      if (request.method == 'POST' && path == '/api/themes') {
        final body = await _readJsonObject(request, maxBytes: 64 * 1024);
        final name = body['name'];
        final description = body['description'];
        final values = body['values'];
        if (name is! String || values is! Map<String, dynamic>) {
          throw const FormatException('name 문자열과 values 객체가 필요합니다.');
        }
        final theme = await _uiThemeService.saveUserTheme(
          name,
          values,
          description: description is String ? description : '',
        );
        return await _sendJson(request.response, 201, {
          'ok': true,
          'theme': theme.toJson(),
        });
      }
      if (request.method == 'DELETE' && path == '/api/themes') {
        await _uiThemeService.deleteUserTheme(
          request.uri.queryParameters['id'] ?? '',
        );
        return await _sendJson(request.response, 200, {'ok': true});
      }
      if (request.method == 'GET' && path == '/api/config') {
        return await _sendJson(request.response, 200, await configReader());
      }
      if (request.method == 'GET' && path == '/api/config/effective') {
        return await _sendJson(
          request.response,
          200,
          await _effectiveConfigReader(),
        );
      }
      if (request.method == 'GET' && path == '/api/config/defaults') {
        return await _sendJson(
          request.response,
          200,
          await _defaultConfigReader(),
        );
      }
      if (request.method == 'PUT' && path == '/api/config') {
        final body = await _readJsonObject(request);
        await _backupService?.saveCurrentAsPrevious();
        await configWriter(body);
        return await _sendJson(request.response, 200, {
          'ok': true,
          'message': '설정을 저장하고 사이니지에 적용했습니다.',
        });
      }
      if (request.method == 'POST' && path == '/api/config/validate') {
        final body = await _readJsonObject(request);
        MenuConfigLoader.parse(body);
        return await _sendJson(request.response, 200, {'ok': true});
      }
      if (request.method == 'GET' && path == '/api/config-backup') {
        final backupService = _backupService;
        if (backupService == null) {
          return await _sendJson(
              request.response, 501, {'error': 'not-supported'});
        }
        final body = const JsonEncoder.withIndent(' ')
            .convert(await backupService.export());
        request.response.headers.set(
          'Content-Disposition',
          'attachment; filename="ysignage-settings.json"',
        );
        return await _sendBytes(
          request.response,
          utf8.encode(body),
          ContentType.json,
        );
      }
      if (request.method == 'PUT' && path == '/api/config-backup') {
        final backupService = _backupService;
        if (backupService == null) {
          return await _sendJson(
              request.response, 501, {'error': 'not-supported'});
        }
        final body = await _readJsonObject(request);
        final importedSettings = await backupService.import(body);
        await _sendJson(request.response, 202, {
          'ok': true,
          'message': '설정 백업을 검증하고 적용했습니다.',
        });
        _applySettingsLater(
          importedSettings,
          afterApply: _onConfigurationImported,
        );
        return;
      }
      if (request.method == 'POST' &&
          path == '/api/config-backup/restore-previous') {
        final backupService = _backupService;
        if (backupService == null) {
          return await _sendJson(
              request.response, 501, {'error': 'not-supported'});
        }
        final restoredSettings = await backupService.restorePrevious();
        await _sendJson(request.response, 202, {
          'ok': true,
          'message': '직전 설정으로 복원했습니다.',
        });
        _applySettingsLater(
          restoredSettings,
          afterApply: _onConfigurationImported,
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/diagnostics') {
        final body = const JsonEncoder.withIndent(' ')
            .convert(await _diagnosticsService.createReport());
        request.response.headers.set(
          'Content-Disposition',
          'attachment; filename="ysignage-diagnostics.json"',
        );
        return await _sendBytes(
          request.response,
          utf8.encode(body),
          ContentType.json,
        );
      }
      if (request.method == 'GET' && path.startsWith('/api/logs/')) {
        final name = path.substring('/api/logs/'.length);
        LogCategory? category;
        for (final value in LogCategory.values) {
          if (value.name == name) category = value;
        }
        if (category == null) {
          return await _sendJson(
            request.response,
            404,
            {'error': 'unknown-log-category'},
          );
        }
        request.response.headers.set(
          'Content-Disposition',
          'attachment; filename="$name.log"',
        );
        return await _sendBytes(
          request.response,
          utf8.encode(await AppLogger.read(category)),
          ContentType.text,
        );
      }
      if (request.method == 'GET' && path == '/api/server-settings') {
        return await _sendJson(request.response, 200, {
          ...settings.toJson(),
          'webAdminSshForwardingStatus':
              _webAdminSshTunnelController.status.name,
          'webAdminSshForwardingState':
              _webAdminSshTunnelController.forwardingStateText,
          'webAdminSshForwardingVerified':
              _webAdminSshTunnelController.forwardingVerified,
          'webAdminSshForwardingUrl': webAdminSshRemoteUri?.toString(),
          'webAdminSshForwardingLastVerifiedAt': _webAdminSshTunnelController
              .lastForwardingVerifiedAt
              ?.toUtc()
              .toIso8601String(),
          'webAdminSshForwardingError': _webAdminSshTunnelController.lastError,
        });
      }
      if (request.method == 'PUT' && path == '/api/server-settings') {
        final body = await _readJsonObject(request);
        final updated = AdminApiSettings.fromJson(body);
        await _validateSettings(updated);
        await _sendJson(request.response, 202, {
          'ok': true,
          'message': '관리 API가 새 설정으로 다시 시작됩니다.',
          'settings': updated.toJson(),
        });
        _applySettingsLater(updated);
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
    } on ExdataFileException catch (error) {
      AppLogger.warning(
        LogCategory.api,
        '${request.method} ${request.uri.path}: ${error.message}',
      );
      try {
        await _sendJson(request.response, error.statusCode, {
          'error': error.code,
          'message': error.message,
        });
      } catch (_) {}
    } on UiThemeException catch (error) {
      AppLogger.warning(
        LogCategory.api,
        '${request.method} ${request.uri.path}: ${error.message}',
      );
      try {
        await _sendJson(request.response, error.statusCode, {
          'error': error.code,
          'message': error.message,
        });
      } catch (_) {}
    } on FormatException catch (error) {
      AppLogger.warning(
          LogCategory.api, '${request.method} ${request.uri.path}: $error');
      try {
        await _sendJson(request.response, 400, {'error': error.message});
      } catch (_) {}
    } catch (error) {
      AppLogger.error(LogCategory.api, error);
      try {
        await _sendJson(request.response, 500, {'error': '$error'});
      } catch (_) {}
    }
  }

  Future<void> _requireExdataPathUnused(String relativePath) async {
    final normalized = ExdataFileService.normalizeRelativePath(relativePath);
    final references = findExdataConfigReferences(
      await _effectiveConfigReader(),
      exdataRootPath: _exdataFileService.rootPath,
    ).where((reference) => reference.isAffectedBy(normalized)).toList();
    if (references.isEmpty) return;

    final locations = references
        .map((reference) => reference.settingPath)
        .toSet()
        .take(3)
        .join(', ');
    final remaining =
        references.map((value) => value.settingPath).toSet().length - 3;
    final suffix = remaining > 0 ? ' 외 $remaining곳' : '';
    throw ExdataFileException(
      409,
      'file-in-use',
      '현재 설정에서 사용 중인 파일 또는 폴더이므로 삭제하거나 이름을 변경할 수 없습니다.\n'
          '사용 위치: $locations$suffix',
    );
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
      if (_sessions.containsKey(token)) {
        // 고정 만료가 아니라 마지막 관리 작업으로부터 30분 동안 유지한다.
        _sessions[token] = DateTime.now().add(_sessionLifetime);
        return token;
      }
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
            "script-src 'self' 'unsafe-inline'; connect-src 'self'; "
            "img-src 'self' blob:",
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

  @override
  void dispose() {
    _webAdminSshTunnelController.removeListener(_handleSshTunnelChanged);
    _webAdminSshTunnelController.dispose();
    super.dispose();
  }
}
