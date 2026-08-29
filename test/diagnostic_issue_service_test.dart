import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/diagnostic_issue_service.dart';
import 'package:simple_kiosk/service/diagnostics_service.dart';

class _FakeDiagnosticsService extends DiagnosticsService {
  const _FakeDiagnosticsService();

  @override
  Future<Map<String, dynamic>> createReport() async => {
        'application': {'name': 'simple-kiosk', 'version': '1.2.34'},
        'system': {'operatingSystem': 'windows'},
        'logs': {'app': '테스트 로그'},
      };
}

void main() {
  test('원격 관리자 주소를 이슈 중계 주소로 변환한다', () {
    final uri = DiagnosticIssueService.relayUri(
      Uri.parse('http://ysignage1.signage.cuniverse.net/?tab=diagnostics'),
    );

    expect(
      uri.toString(),
      'http://ysignage1.signage.cuniverse.net/api/github-issues',
    );
  });

  test('자동 이슈 보고서에 환경과 업데이트 상태를 포함한다', () {
    final report = DiagnosticIssueService.buildReport({
      'generatedAt': '2026-08-29T10:00:00Z',
      'application': {'name': 'simple-kiosk', 'version': '1.2.34'},
      'system': {'operatingSystem': 'windows'},
      'logs': {'app': '최근 로그'},
    }, updateStatus: '업데이트 확인 실패');

    expect(report.title, '[자동 진단] simple-kiosk v1.2.34');
    expect(report.body, contains('업데이트 확인 실패'));
    expect(report.body, contains('"operatingSystem": "windows"'));
    expect(report.body, contains('최근 로그'));
  });

  test('버튼 호출 한 번으로 중계 서버에 진단 이슈를 등록한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Map<String, dynamic> requestBody;
    final requestHandled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/github-issues');
      requestBody = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'number': 321,
        'url': 'https://github.com/cuniverse/simple-kiosk/issues/321',
        'message': '등록 완료',
      }));
      await request.response.close();
    });
    const service = DiagnosticIssueService(
      diagnosticsService: _FakeDiagnosticsService(),
    );

    final result = await service.submit(
      Uri.parse('http://127.0.0.1:${server.port}/admin?ignored=1'),
      updateStatus: '최신 버전',
    );
    await requestHandled;

    expect(requestBody['title'], '[자동 진단] simple-kiosk v1.2.34');
    expect(requestBody['body'], contains('최신 버전'));
    expect(result.number, 321);
    expect(result.url?.path, '/cuniverse/simple-kiosk/issues/321');
  });

  test('진단 본문을 중계 서버 용량 제한 이하로 잘라낸다', () {
    final report = DiagnosticIssueService.buildReport({
      'application': {'name': 'simple-kiosk', 'version': '1.2.34'},
      'logs': {'app': List.filled(40000, '가').join()},
    });

    expect(
      utf8.encode(report.body).length,
      lessThanOrEqualTo(DiagnosticIssueService.maximumBodyBytes),
    );
    expect(report.body, contains('용량 제한으로 이후 진단 내용 생략'));
    expect(report.body, endsWith('\n```'));
  });
}
