// ignore_for_file: implementation_imports

import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/message/msg_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/service/web_admin_ssh_tunnel_controller.dart';

void main() {
  test('포워딩 상태 확인은 UTF-8이 아닌 HTTP 첫 줄만 바이트로 읽는다', () async {
    final status = await readHttpStatusLine(Stream<List<int>>.fromIterable([
      'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n'.codeUnits,
      [0xed, 0x95],
    ]));

    expect(status, 'HTTP/1.1 200 OK');
  });

  test('OpenSSH stream-local 원격 포워딩 요청을 인코딩한다', () {
    final request = SSH_Message_Global_Request.streamLocalForward(
      '/run/signage/ysignage1.sock',
    );
    final decoded = SSH_Message_Global_Request.decode(request.encode());

    expect(decoded.requestName, 'streamlocal-forward@openssh.com');
    expect(decoded.wantReply, isTrue);
    expect(decoded.socketPath, '/run/signage/ysignage1.sock');
  });

  test('OpenSSH forwarded stream-local 채널을 디코딩한다', () {
    final message = SSH_Message_Channel_Open.forwardedStreamLocal(
      senderChannel: 3,
      initialWindowSize: 1024,
      maximumPacketSize: 512,
      socketPath: '/run/signage/ysignage1.sock',
    );
    final decoded = SSH_Message_Channel_Open.decode(message.encode());

    expect(decoded.channelType, 'forwarded-streamlocal@openssh.com');
    expect(decoded.senderChannel, 3);
    expect(decoded.socketPath, '/run/signage/ysignage1.sock');
  });
}
