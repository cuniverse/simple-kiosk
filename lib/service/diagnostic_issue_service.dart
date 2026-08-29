import 'dart:convert';
import 'dart:io';

import 'diagnostics_service.dart';

class DiagnosticIssueResult {
  final int? number;
  final Uri? url;
  final String message;

  const DiagnosticIssueResult({
    this.number,
    this.url,
    this.message = '',
  });
}

class DiagnosticIssueException implements Exception {
  final String message;

  const DiagnosticIssueException(this.message);

  @override
  String toString() => message;
}

class DiagnosticIssueReport {
  final String title;
  final String body;

  const DiagnosticIssueReport({required this.title, required this.body});
}

class DiagnosticIssueService {
  static const int maximumBodyBytes = 28000;
  final DiagnosticsService _diagnosticsService;

  const DiagnosticIssueService({
    DiagnosticsService diagnosticsService = const DiagnosticsService(),
  }) : _diagnosticsService = diagnosticsService;

  static Uri relayUri(Uri remoteAdminUri) =>
      remoteAdminUri.resolve('/api/github-issues');

  static DiagnosticIssueReport buildReport(
    Map<String, dynamic> diagnostics, {
    String updateStatus = '',
  }) {
    final application = diagnostics['application'];
    final applicationMap =
        application is Map ? Map<String, dynamic>.from(application) : const {};
    final appName = '${applicationMap['name'] ?? 'simple-kiosk'}'.trim();
    final version = '${applicationMap['version'] ?? 'unknown'}'.trim();
    final title = '[자동 진단] $appName v$version';
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(diagnostics)
        .replaceAll('```', '``\u200b`');
    final prefix = StringBuffer()
      ..writeln('설정 화면의 **진단 정보로 이슈 등록** 버튼에서 자동 생성된 보고서입니다.')
      ..writeln()
      ..writeln('## 업데이트 상태')
      ..writeln(updateStatus.trim().isEmpty ? '확인 불가' : updateStatus.trim())
      ..writeln()
      ..writeln('## 진단 정보')
      ..writeln('```json');
    const suffix = '\n```';
    final availableBytes = maximumBodyBytes -
        utf8.encode(prefix.toString()).length -
        utf8.encode(suffix).length;
    final diagnosticText = _truncateUtf8(encoded, availableBytes);
    return DiagnosticIssueReport(
      title: title,
      body: '${prefix.toString()}$diagnosticText$suffix',
    );
  }

  Future<DiagnosticIssueResult> submit(
    Uri remoteAdminUri, {
    String updateStatus = '',
  }) async {
    final diagnostics = await _diagnosticsService.createReport();
    final report = buildReport(diagnostics, updateStatus: updateStatus);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(relayUri(remoteAdminUri))
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'title': report.title, 'body': report.body}));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final responseText = await utf8.decoder.bind(response).join();
      Map<String, dynamic> payload = const {};
      try {
        final decoded = jsonDecode(responseText);
        if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // HTTP 상태와 원문 일부로 아래에서 오류를 알린다.
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final relayMessage = payload['message'];
        throw DiagnosticIssueException(
          relayMessage is String && relayMessage.trim().isNotEmpty
              ? relayMessage.trim()
              : '이슈 중계 서버 오류 (HTTP ${response.statusCode})',
        );
      }
      final numberValue = payload['number'];
      final urlValue = payload['url'];
      return DiagnosticIssueResult(
        number: numberValue is num ? numberValue.toInt() : null,
        url: urlValue is String ? Uri.tryParse(urlValue) : null,
        message:
            payload['message'] is String ? payload['message'] as String : '',
      );
    } on DiagnosticIssueException {
      rethrow;
    } catch (error) {
      throw DiagnosticIssueException('진단 이슈 등록 실패: $error');
    } finally {
      client.close(force: true);
    }
  }

  static String _truncateUtf8(String value, int maximumBytes) {
    if (maximumBytes <= 0) return '';
    if (utf8.encode(value).length <= maximumBytes) return value;
    const marker = '\n... (용량 제한으로 이후 진단 내용 생략)';
    final markerBytes = utf8.encode(marker).length;
    final contentLimit = maximumBytes - markerBytes;
    if (contentLimit <= 0) return '';
    final buffer = StringBuffer();
    var usedBytes = 0;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final length = utf8.encode(character).length;
      if (usedBytes + length > contentLimit) break;
      buffer.write(character);
      usedBytes += length;
    }
    return '${buffer.toString()}$marker';
  }
}
