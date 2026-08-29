import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_logger.dart';
import 'runtime_paths.dart';

enum FontResourceSource { flutterDefault, external, packaged, system }

class ResolvedFontResource {
  const ResolvedFontResource({
    required this.requestedFamily,
    required this.effectiveFamily,
    required this.source,
  });

  final String? requestedFamily;
  final String? effectiveFamily;
  final FontResourceSource source;
}

/// 사이니지 UI 글꼴을 외부 폴더, 패키지, 시스템 순서로 선택한다.
class FontResourceService {
  static final ValueNotifier<ResolvedFontResource> current = ValueNotifier(
    const ResolvedFontResource(
      requestedFamily: null,
      effectiveFamily: null,
      source: FontResourceSource.flutterDefault,
    ),
  );

  static const Map<String, String> _packagedAliases = {
    'nanumsquare': 'NanumSquare',
    '나눔스퀘어': 'NanumSquare',
    'nanumgothic': 'NanumGothic',
    '나눔고딕': 'NanumGothic',
    'nanumbrush': 'NanumBrush',
    'nanumbrushscript': 'NanumBrush',
    '나눔손글씨붓': 'NanumBrush',
    'pretendard': 'Pretendard',
    'pretendard139': 'Pretendard',
    'kopubdotum': 'KoPubDotum',
    'kopub돋움': 'KoPubDotum',
    'kopub돋움체': 'KoPubDotum',
    '가톨릭체': 'Catholic',
    'catholic': 'Catholic',
    'museumclassic': 'MuseumClassic',
    '박물관체': 'MuseumClassic',
    '국립박물관문화재단클래식': 'MuseumClassic',
    '국립박물관문화재단클래식체': 'MuseumClassic',
    'seoul': 'Seoul',
    '서울': 'Seoul',
    '서울체': 'Seoul',
    'seoulnamsan': 'Seoul',
    '서울남산': 'Seoul',
    '서울남산체': 'Seoul',
    'seoulhangang': 'SeoulHangang',
    '서울한강': 'SeoulHangang',
    '서울한강체': 'SeoulHangang',
  };

  static final Map<String, String> _loadedExternalFamilies = {};
  static final Map<String, String> _resolvedFamilies = {};

  static List<String> get packagedFamilies => const [
        'Pretendard',
        'NanumSquare',
        'NanumGothic',
        'NanumBrush',
        'KoPubDotum',
        'Catholic',
        'MuseumClassic',
        'Seoul',
        'SeoulHangang',
      ];

  static Future<ResolvedFontResource> apply(
    String? requestedFamily, {
    Iterable<String?> additionalFamilies = const [],
  }) async {
    for (final family in additionalFamilies) {
      await _resolve(family);
    }
    return _publish(await _resolve(requestedFamily));
  }

  /// 이미 준비된 설정 이름을 실제 Flutter 글꼴 패밀리 이름으로 변환한다.
  static String? familyFor(String? requestedFamily) {
    final requested = requestedFamily?.trim();
    if (requested == null || requested.isEmpty) return null;
    final normalized = _normalize(requested);
    return _resolvedFamilies[normalized] ??
        _packagedAliases[normalized] ??
        requested;
  }

  static Future<ResolvedFontResource> _resolve(String? requestedFamily) async {
    final requested = requestedFamily?.trim();
    if (requested == null || requested.isEmpty) {
      return const ResolvedFontResource(
        requestedFamily: null,
        effectiveFamily: null,
        source: FontResourceSource.flutterDefault,
      );
    }

    try {
      final external = await _loadExternal(requested);
      if (external != null) {
        _resolvedFamilies[_normalize(requested)] = external;
        return ResolvedFontResource(
          requestedFamily: requested,
          effectiveFamily: external,
          source: FontResourceSource.external,
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(LogCategory.app, error, stackTrace);
    }

    final packaged = _packagedAliases[_normalize(requested)];
    if (packaged != null) {
      _resolvedFamilies[_normalize(requested)] = packaged;
      return ResolvedFontResource(
        requestedFamily: requested,
        effectiveFamily: packaged,
        source: FontResourceSource.packaged,
      );
    }

    // Flutter/Windows가 설치된 시스템 글꼴 이름을 직접 해석한다. 존재하지
    // 않는 이름은 Flutter의 기본 폰트로 자동 폴백한다.
    _resolvedFamilies[_normalize(requested)] = requested;
    return ResolvedFontResource(
      requestedFamily: requested,
      effectiveFamily: requested,
      source: FontResourceSource.system,
    );
  }

  static ResolvedFontResource _publish(ResolvedFontResource resource) {
    current.value = resource;
    AppLogger.info(
      LogCategory.app,
      'UI font: requested=${resource.requestedFamily ?? '(default)'}, '
      'effective=${resource.effectiveFamily ?? '(flutter default)'}, '
      'source=${resource.source.name}',
    );
    return resource;
  }

  static Future<String?> _loadExternal(String requested) async {
    final rootPath = RuntimePaths.fonts;
    if (rootPath == null) return null;
    final root = Directory(rootPath);
    if (!await root.exists()) return null;

    final normalized = _normalize(requested);
    if (normalized.isEmpty) return null;
    final cached = _loadedExternalFamilies[normalized];
    if (cached != null) return cached;

    final candidates = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final lowerPath = entity.path.toLowerCase();
      if (!lowerPath.endsWith('.ttf') && !lowerPath.endsWith('.otf')) continue;
      final stem = entity.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.(?:ttf|otf)$', caseSensitive: false),
        '',
      );
      final parentSegments = entity.parent.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      final parentName = parentSegments.isEmpty ? null : parentSegments.last;
      if (_normalize(stem).startsWith(normalized) ||
          (parentName != null && _normalize(parentName) == normalized)) {
        candidates.add(entity);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.path.compareTo(b.path));

    final newest = await Future.wait(
      candidates.map(
        (file) async => (await file.stat()).modified.millisecondsSinceEpoch,
      ),
    );
    final revision = newest.fold<int>(0, (value, item) => value ^ item);
    final alias = 'ExternalFont_${normalized}_$revision';
    final loader = FontLoader(alias);
    for (final file in candidates) {
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
    _loadedExternalFamilies[normalized] = alias;
    return alias;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
}
