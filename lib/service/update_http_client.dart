import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'app_logger.dart';
import 'windows_certificate_verifier.dart';

typedef CertificateCheck = bool Function(X509Certificate, String, int);
typedef CertificateVerifier = Future<bool> Function(Uint8List, String);

http.Client createUpdateHttpClient() =>
    Platform.isWindows ? UpdateHttpClient() : http.Client();

/// Retries read-only updater requests after independent Windows SSL validation.
/// Acceptance is scoped to the exact DER certificate, host, port and request.
class UpdateHttpClient extends http.BaseClient {
  final http.Client Function(CertificateCheck) _clientFactory;
  final CertificateVerifier _verifyCertificate;
  final Set<http.Client> _active = {};
  bool _closed = false;

  UpdateHttpClient({
    http.Client Function(CertificateCheck)? clientFactory,
    CertificateVerifier? verifyCertificate,
  })  : _clientFactory = clientFactory ?? _ioClient,
        _verifyCertificate =
            verifyCertificate ?? verifyWindowsServerCertificate;

  static http.Client _ioClient(CertificateCheck check) =>
      IOClient(HttpClient()..badCertificateCallback = check);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _ensureOpen(request.url);
    // Only replay body-free reads. The updater uses GET for all its requests.
    if (request is! http.Request ||
        !const {'GET', 'HEAD'}.contains(request.method) ||
        request.bodyBytes.isNotEmpty) {
      throw http.ClientException(
          'Updater requires a body-free GET or HEAD', request.url);
    }
    final accepted = <String>{};
    for (var attempt = 0;; attempt++) {
      _ensureOpen(request.url);
      X509Certificate? rejected;
      String? rejectedHost;
      String? rejectedKey;
      final client = _clientFactory((certificate, host, port) {
        final key = '$host:$port:${base64.encode(certificate.der)}';
        final now = DateTime.now();
        if (accepted.contains(key) &&
            !now.isBefore(certificate.startValidity) &&
            !now.isAfter(certificate.endValidity)) {
          return true;
        }
        rejected = certificate;
        rejectedHost = host;
        rejectedKey = key;
        return false;
      });
      _active.add(client);
      try {
        final copy = http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;
        final response = await client.send(copy);
        return http.StreamedResponse(
          _releaseOnDone(response.stream, client),
          response.statusCode,
          contentLength: response.contentLength,
          request: request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      } on HandshakeException {
        _release(client);
        final certificate = rejected;
        final host = rejectedHost;
        final key = rejectedKey;
        if (attempt >= 3 ||
            certificate == null ||
            host == null ||
            key == null ||
            accepted.contains(key)) {
          rethrow;
        }
        bool verified;
        try {
          verified = await _verifyCertificate(certificate.der, host)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          verified = false;
        }
        if (!verified) rethrow;
        accepted.add(key);
        AppLogger.info(LogCategory.update,
            'Retrying update HTTPS after Windows SSL validation: $host');
      } catch (_) {
        _release(client);
        rethrow;
      }
    }
  }

  Stream<List<int>> _releaseOnDone(
      Stream<List<int>> stream, http.Client client) async* {
    try {
      yield* stream;
    } finally {
      _release(client);
    }
  }

  void _ensureOpen(Uri url) {
    if (_closed) throw http.ClientException('Update client is closed', url);
  }

  void _release(http.Client client) {
    if (_active.remove(client)) client.close();
  }

  @override
  void close() {
    _closed = true;
    for (final client in _active.toList()) {
      _release(client);
    }
  }
}
