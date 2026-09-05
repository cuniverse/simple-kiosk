import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Uses Windows trust, chain retrieval and SSL policy without ignoring errors.
/// Chain retrieval can access the network, so it must run off the UI isolate.
Future<bool> verifyWindowsServerCertificate(Uint8List der, String host) async {
  if (!Platform.isWindows ||
      der.isEmpty ||
      host.isEmpty ||
      host.contains('\x00')) {
    return false;
  }
  try {
    return await Isolate.run(() => _verify(der, host));
  } catch (_) {
    return false;
  }
}

bool _verify(Uint8List der, String host) {
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final create = crypt32.lookupFunction<
      Pointer<Void> Function(Uint32, Pointer<Uint8>, Uint32),
      Pointer<Void> Function(int, Pointer<Uint8>, int)>(
    'CertCreateCertificateContext',
  );
  final freeCertificate = crypt32.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CertFreeCertificateContext');
  final getChain = crypt32.lookupFunction<
      Int32 Function(
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<_ChainParameters>,
          Uint32,
          Pointer<Void>,
          Pointer<Pointer<Void>>),
      int Function(
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<_ChainParameters>,
          int,
          Pointer<Void>,
          Pointer<Pointer<Void>>)>(
    'CertGetCertificateChain',
  );
  final freeChain = crypt32.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('CertFreeCertificateChain');
  final verifyPolicy = crypt32.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<_PolicyParameters>,
          Pointer<_PolicyStatus>),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<_PolicyParameters>,
          Pointer<_PolicyStatus>)>('CertVerifyCertificateChainPolicy');

  return using((arena) {
    final encoded = arena<Uint8>(der.length)
      ..asTypedList(der.length).setAll(0, der);
    final certificate = create(1, encoded, der.length); // X509_ASN_ENCODING
    if (certificate == nullptr) return false;
    final chain = arena<Pointer<Void>>();
    try {
      final usage = arena<Pointer<Utf8>>()
        ..value = '1.3.6.1.5.5.7.3.1'.toNativeUtf8(allocator: arena);
      final parameters = arena<_ChainParameters>();
      parameters.ref
        ..cbSize = sizeOf<_ChainParameters>()
        ..urlRetrievalTimeout = 5000;
      parameters.ref.requestedUsage.usage
        ..count = 1
        ..identifiers = usage;
      // Check revocation (excluding roots), with a cumulative retrieval timeout.
      const flags = 0x40000000 | 0x08000000;
      if (getChain(nullptr, certificate, nullptr, nullptr, parameters, flags,
              nullptr, chain) ==
          0) {
        return false;
      }

      final ssl = arena<_SslPolicy>();
      ssl.ref
        ..cbSize = sizeOf<_SslPolicy>()
        ..authType = 2 // AUTHTYPE_SERVER
        ..serverName = host.toNativeUtf16(allocator: arena);
      final policy = arena<_PolicyParameters>();
      policy.ref
        ..cbSize = sizeOf<_PolicyParameters>()
        ..extra = ssl;
      final status = arena<_PolicyStatus>();
      status.ref.cbSize = sizeOf<_PolicyStatus>();
      // CERT_CHAIN_POLICY_SSL. Both flags fields remain zero: no ignored errors.
      return verifyPolicy(
                  Pointer<Void>.fromAddress(4), chain.value, policy, status) !=
              0 &&
          status.ref.error == 0;
    } finally {
      if (chain.value != nullptr) freeChain(chain.value);
      freeCertificate(certificate);
    }
  });
}

// Layouts from wincrypt.h; DWORD/BOOL/LONG remain 32-bit on Windows x64.
final class _EnhancedKeyUsage extends Struct {
  @Uint32()
  external int count;
  external Pointer<Pointer<Utf8>> identifiers;
}

final class _UsageMatch extends Struct {
  @Uint32()
  external int type;
  external _EnhancedKeyUsage usage;
}

final class _ChainParameters extends Struct {
  @Uint32()
  external int cbSize;
  external _UsageMatch requestedUsage;
  external _UsageMatch requestedIssuancePolicy;
  @Uint32()
  external int urlRetrievalTimeout;
  @Int32()
  external int checkRevocationFreshness;
  @Uint32()
  external int revocationFreshnessTime;
  external Pointer<Void> cacheResync;
  external Pointer<Void> strongSign;
  @Uint32()
  external int strongSignFlags;
}

final class _SslPolicy extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int authType;
  @Uint32()
  external int checks;
  external Pointer<Utf16> serverName;
}

final class _PolicyParameters extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int flags;
  external Pointer<_SslPolicy> extra;
}

final class _PolicyStatus extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int error;
  @Int32()
  external int chainIndex;
  @Int32()
  external int elementIndex;
  external Pointer<Void> extra;
}
