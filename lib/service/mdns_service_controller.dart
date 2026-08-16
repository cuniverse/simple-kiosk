import 'dart:io';

import 'package:mdns_dart/mdns_dart.dart';

import '../app_identity.dart';

abstract class MdnsPublisher {
  bool get running;

  Future<void> start({required String hostname, required int port});

  Future<void> stop();
}

class MdnsServiceController implements MdnsPublisher {
  MDNSServer? _server;

  @override
  bool get running => _server != null;

  @override
  Future<void> start({required String hostname, required int port}) async {
    await stop();
    final addresses = await _localAddresses();
    if (addresses.isEmpty) {
      throw const SocketException('mDNS에 사용할 로컬 네트워크 주소가 없습니다.');
    }
    final service = await MDNSService.create(
      instance: appDisplayName,
      service: mdnsServiceType,
      hostName: hostname,
      port: port,
      ips: addresses,
      txt: const ['path=/', 'apiVersion=1'],
    );
    final server = MDNSServer(
      MDNSServerConfig(zone: service, reuseAddress: true),
    );
    await server.start();
    _server = server;
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) await server.stop();
  }

  Future<List<InternetAddress>> _localAddresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.any,
    );
    return interfaces
        .expand((interface) => interface.addresses)
        .where((address) =>
            !address.isLoopback &&
            !(address.type == InternetAddressType.IPv6 && address.isLinkLocal))
        .toSet()
        .toList();
  }
}
