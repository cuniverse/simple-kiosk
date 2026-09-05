import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:simple_kiosk/service/update_http_client.dart';
import 'package:simple_kiosk/service/windows_certificate_verifier.dart';

void main() {
  final url = Uri.parse('https://updates.example/package.zip');

  test('ordinary response skips fallback and releases the streamed client',
      () async {
    late _Client transport;
    final client = UpdateHttpClient(
      clientFactory: (_) => transport = _Client((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 2);
        return http.StreamedResponse(Stream.value([1, 2]), 302,
            contentLength: 2,
            headers: {'location': '/release'},
            isRedirect: true);
      }),
      verifyCertificate: (_, __) async => fail('Unexpected Windows validation'),
    );
    addTearDown(client.close);
    final response = await client.send(http.Request('GET', url)
      ..followRedirects = false
      ..maxRedirects = 2);
    expect(transport.closes, 0);
    expect(response.statusCode, 302);
    expect(response.isRedirect, isTrue);
    expect(response.headers['location'], '/release');
    expect(response.contentLength, 2);
    expect(await response.stream.toBytes(), [1, 2]);
    expect(transport.closes, 1);
  });

  test('Windows-validated retry preserves range and accepts only exact peer',
      () async {
    var attempts = 0;
    var validations = 0;
    final transports = <_Client>[];
    final certificate = _Certificate(1);
    final client = UpdateHttpClient(
      clientFactory: (check) {
        attempts++;
        final transport = _Client((request) async {
          expect(request.url, url);
          expect(request.headers['Range'], 'bytes=10-');
          expect(request.headers['User-Agent'], 'updater');
          if (!check(certificate, url.host, 443)) {
            throw const HandshakeException('untrusted by Dart');
          }
          // Windows trust for this exact peer must not cover a different peer.
          expect(check(_Certificate(2), url.host, 443), isFalse);
          expect(check(certificate, 'other.example', 443), isFalse);
          expect(check(certificate, url.host, 444), isFalse);
          expect(check(_Certificate(1, expired: true), url.host, 443), isFalse);
          return http.StreamedResponse(Stream.value([10, 11]), 206,
              headers: {'content-range': 'bytes 10-11/12'});
        });
        transports.add(transport);
        return transport;
      },
      verifyCertificate: (der, host) async {
        validations++;
        expect(der, [1]);
        expect(host, url.host);
        return true;
      },
    );
    addTearDown(client.close);
    final response = await client
        .get(url, headers: {'Range': 'bytes=10-', 'User-Agent': 'updater'});
    expect(response.statusCode, 206);
    expect(response.bodyBytes, [10, 11]);
    expect(response.headers['content-range'], 'bytes 10-11/12');
    expect(attempts, 2);
    expect(validations, 1);
    expect(transports.map((e) => e.closes), everyElement(1));
  });

  for (final throwsError in [false, true]) {
    test('Windows ${throwsError ? 'error' : 'rejection'} fails closed',
        () async {
      const failure = HandshakeException('original TLS failure');
      var attempts = 0;
      final client = UpdateHttpClient(
        clientFactory: (check) {
          attempts++;
          return _Client((_) async {
            expect(check(_Certificate(1), url.host, 443), isFalse);
            throw failure;
          });
        },
        verifyCertificate: (_, __) async {
          if (throwsError) throw StateError('Windows verifier unavailable');
          return false;
        },
      );
      addTearDown(client.close);
      await expectLater(client.get(url), throwsA(same(failure)));
      expect(attempts, 1);
    });
  }

  test('TLS failure without a rejected certificate does not retry', () async {
    final client = UpdateHttpClient(
      clientFactory: (_) => _Client((_) async {
        throw const HandshakeException('protocol failure');
      }),
      verifyCertificate: (_, __) async => fail('Unexpected Windows validation'),
    );
    addTearDown(client.close);
    await expectLater(client.get(url), throwsA(isA<HandshakeException>()));
  });

  test('each redirected host requires its own Windows validation', () async {
    final validated = <String>[];
    var attempts = 0;
    final client = UpdateHttpClient(
      clientFactory: (check) {
        attempts++;
        return _Client((_) async {
          for (final host in [url.host, 'assets.example']) {
            if (!check(_Certificate(1), host, 443)) {
              throw const HandshakeException('untrusted redirect');
            }
          }
          return http.StreamedResponse(Stream.value([1]), 200);
        });
      },
      verifyCertificate: (_, host) async {
        validated.add(host);
        return true;
      },
    );
    addTearDown(client.close);
    expect((await client.get(url)).statusCode, 200);
    expect(validated, [url.host, 'assets.example']);
    expect(attempts, 3);
  });

  test('changing certificates cannot cause an unbounded retry loop', () async {
    var attempts = 0;
    final client = UpdateHttpClient(
      clientFactory: (check) {
        attempts++;
        return _Client((_) async {
          expect(check(_Certificate(attempts), url.host, 443), isFalse);
          throw const HandshakeException('certificate changed');
        });
      },
      verifyCertificate: (_, __) async => true,
    );
    addTearDown(client.close);
    await expectLater(client.get(url), throwsA(isA<HandshakeException>()));
    expect(attempts, 4);
  });

  test('closing while Windows verifies prevents the retry', () async {
    final verification = Completer<bool>();
    final started = Completer<void>();
    var attempts = 0;
    final client = UpdateHttpClient(
      clientFactory: (check) {
        attempts++;
        return _Client((_) async {
          check(_Certificate(1), url.host, 443);
          throw const HandshakeException('untrusted');
        });
      },
      verifyCertificate: (_, __) {
        started.complete();
        return verification.future;
      },
    );
    final result = client.get(url);
    final expectation =
        expectLater(result, throwsA(isA<http.ClientException>()));
    await started.future;
    client.close();
    verification.complete(true);
    await expectation;
    expect(attempts, 1);
  });

  test('response cancellation closes the download connection', () async {
    final body = StreamController<List<int>>();
    late _Client transport;
    final client = UpdateHttpClient(
      clientFactory: (_) => transport =
          _Client((_) async => http.StreamedResponse(body.stream, 200)),
    );
    addTearDown(client.close);
    final response = await client.send(http.Request('GET', url));
    final received = Completer<void>();
    final subscription = response.stream.listen((_) => received.complete());
    body.add([1]);
    await received.future;
    await subscription.cancel();
    expect(transport.closes, 1);
    await body.close();
  });

  test('Windows validator rejects malformed certificates', () async {
    expect(
        await verifyWindowsServerCertificate(Uint8List(0), url.host), isFalse);
    expect(
        await verifyWindowsServerCertificate(
            Uint8List.fromList([1, 2, 3]), url.host),
        isFalse);
  });
}

class _Client extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) onSend;
  int closes = 0;
  _Client(this.onSend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      onSend(request);

  @override
  void close() => closes++;
}

class _Certificate implements X509Certificate {
  final int id;
  final bool expired;
  _Certificate(this.id, {this.expired = false});

  @override
  Uint8List get der => Uint8List.fromList([id]);
  @override
  DateTime get startValidity => DateTime.utc(2020);
  @override
  DateTime get endValidity => DateTime.utc(expired ? 2021 : 2100);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
