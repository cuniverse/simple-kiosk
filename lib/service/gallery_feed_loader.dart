import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../model/idle_config.dart';

/// 포토갤러리 게시물의 사진 한 장과 표시할 게시물 제목.
class GalleryFeedItem {
  final String title;
  final String imageUrl;
  final String postUrl;

  const GalleryFeedItem({
    required this.title,
    required this.imageUrl,
    required this.postUrl,
  });
}

class _GalleryPost {
  final String title;
  final Uri url;
  final Uri? thumbnailUrl;
  final DateTime? publishedDate;

  const _GalleryPost({
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.publishedDate,
  });
}

class _LoadedGalleryPost {
  final _GalleryPost post;
  final DateTime? publishedAt;
  final List<GalleryFeedItem> items;

  const _LoadedGalleryPost({
    required this.post,
    required this.publishedAt,
    required this.items,
  });
}

/// 그누보드 계열 갤러리 목록과 게시물 본문에서 사진을 수집한다.
class GalleryFeedLoader {
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Map<String, String> _headers = {
    'User-Agent': 'SimpleKiosk/1.0 gallery-screen',
  };

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;

  GalleryFeedLoader({http.Client? client, DateTime Function()? now})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _now = now ?? DateTime.now;

  Future<List<GalleryFeedItem>> load(GalleryConfig config) async {
    final groups = await Future.wait(
      config.effectiveUrls.map((url) async {
        try {
          return await _loadBoard(config, url);
        } catch (_) {
          return const <GalleryFeedItem>[];
        }
      }),
    );

    final items = <GalleryFeedItem>[];
    final seen = <String>{};
    var itemIndex = 0;
    while (items.length < config.maxImages) {
      var added = false;
      for (final group in groups) {
        if (itemIndex >= group.length) continue;
        final item = group[itemIndex];
        if (seen.add(item.imageUrl)) items.add(item);
        added = true;
        if (items.length >= config.maxImages) break;
      }
      if (!added) break;
      itemIndex++;
    }
    if (items.isEmpty) {
      throw const FormatException('포토갤러리 사진을 찾지 못했습니다.');
    }
    return items;
  }

  Future<List<GalleryFeedItem>> _loadBoard(
    GalleryConfig config,
    String url,
  ) async {
    final listUri = Uri.parse(url);
    final listHtml = await _getText(listUri);
    final parsedPosts = _parseGalleryPosts(listHtml, listUri);
    final requestedAt = _now();
    final posts = _selectGalleryCandidates(parsedPosts, config, requestedAt);
    if (posts.isEmpty) {
      throw const FormatException('포토갤러리 게시물을 찾지 못했습니다.');
    }

    // 목록 순서를 유지하면서 게시물 본문은 병렬 요청한다.
    final results = await Future.wait(
      posts.map((post) async {
        var publishedAt = post.publishedDate;
        try {
          final postHtml = await _getText(post.url);
          publishedAt = parsePostPublishedAt(postHtml) ?? publishedAt;
          final images = parsePostImageUrls(postHtml, post.url);
          if (images.isNotEmpty) {
            final items = images
                .map(
                  (image) => GalleryFeedItem(
                    title: post.title,
                    imageUrl: image.toString(),
                    postUrl: post.url.toString(),
                  ),
                )
                .toList(growable: false);
            return _LoadedGalleryPost(
              post: post,
              publishedAt: publishedAt,
              items: items,
            );
          }
        } catch (_) {
          // 개별 게시물 실패는 목록 썸네일로 대체한다.
        }
        final thumbnail = post.thumbnailUrl;
        return _LoadedGalleryPost(
          post: post,
          publishedAt: publishedAt,
          items: thumbnail == null
              ? const []
              : [
                  GalleryFeedItem(
                    title: post.title,
                    imageUrl: thumbnail.toString(),
                    postUrl: post.url.toString(),
                  ),
                ],
        );
      }),
    );

    final selectedPosts = _selectLoadedGalleryPosts(
      results.where((result) => result.items.isNotEmpty).toList(),
      config,
      requestedAt,
    );

    final seen = <String>{};
    final items = <GalleryFeedItem>[];
    for (final group in selectedPosts) {
      for (final item in group.items) {
        if (seen.add(item.imageUrl)) items.add(item);
      }
    }
    if (items.isEmpty) {
      throw const FormatException('포토갤러리 사진을 찾지 못했습니다.');
    }
    return items;
  }

  Future<String> _getText(Uri uri) async {
    final response =
        await _client.get(uri, headers: _headers).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'HTTP ${response.statusCode}',
        uri,
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

List<_GalleryPost> _parseGalleryPosts(String html, Uri baseUri) {
  final document = html_parser.parse(html);
  final posts = <_GalleryPost>[];
  final seen = <String>{};

  for (final card in document.querySelectorAll('.card')) {
    final titleElement =
        card.querySelector('.bo_tit .ks4') ?? card.querySelector('.bo_tit');
    final linkElement =
        card.querySelector('a.img-card') ?? card.querySelector('a.bo_tit');
    final href = linkElement?.attributes['href'];
    final title = _normalizedText(titleElement?.text ?? '');
    if (href == null || href.isEmpty || title.isEmpty) continue;

    final postUri = baseUri.resolve(href);
    if (!_isHttpUri(postUri) || !seen.add(postUri.toString())) continue;

    final thumbnailSrc =
        card.querySelector('a.img-card img')?.attributes['src'];
    final thumbnailUri = thumbnailSrc == null || thumbnailSrc.isEmpty
        ? null
        : baseUri.resolve(thumbnailSrc);
    posts.add(
      _GalleryPost(
        title: title,
        url: postUri,
        thumbnailUrl: thumbnailUri != null && _isHttpUri(thumbnailUri)
            ? thumbnailUri
            : null,
        publishedDate: _parsePublishedDate(
          card.querySelector('.gall_date')?.text ?? '',
        ),
      ),
    );
  }
  return posts;
}

List<_GalleryPost> _selectGalleryCandidates(
  List<_GalleryPost> posts,
  GalleryConfig config,
  DateTime now,
) {
  final lookbackDays = config.lookbackDays;
  if (lookbackDays == null) {
    return posts.take(config.maxPosts).toList(growable: false);
  }

  final cutoff = now.subtract(Duration(days: lookbackDays));
  final cutoffDate = DateTime(cutoff.year, cutoff.month, cutoff.day);
  final selected = <_GalleryPost>[];
  final selectedUrls = <Uri>{};
  for (final post in posts) {
    final date = post.publishedDate;
    // 목록에 날짜가 없으면 본문의 정확한 작성 시각을 확인할 후보로 포함한다.
    if (date == null || !date.isBefore(cutoffDate)) {
      selected.add(post);
      selectedUrls.add(post.url);
      if (selected.length >= config.maxPosts) return selected;
    }
  }

  // 기간 조건의 결과가 없거나 부족할 경우에 대비해 최신 게시물을 후보에 포함한다.
  if (selected.length < config.minPosts) {
    for (final post in posts) {
      if (selectedUrls.add(post.url)) selected.add(post);
      if (selected.length >= config.minPosts ||
          selected.length >= config.maxPosts) {
        break;
      }
    }
  }
  return selected;
}

List<_LoadedGalleryPost> _selectLoadedGalleryPosts(
  List<_LoadedGalleryPost> posts,
  GalleryConfig config,
  DateTime now,
) {
  final lookbackDays = config.lookbackDays;
  if (lookbackDays == null) {
    return posts.take(config.maxPosts).toList(growable: false);
  }

  final cutoff = now.subtract(Duration(days: lookbackDays));
  final selected = <_LoadedGalleryPost>[];
  final selectedUrls = <Uri>{};
  for (final post in posts) {
    final publishedAt = post.publishedAt;
    if (publishedAt != null && !publishedAt.isBefore(cutoff)) {
      selected.add(post);
      selectedUrls.add(post.post.url);
      if (selected.length >= config.maxPosts) return selected;
    }
  }

  if (selected.length < config.minPosts) {
    for (final post in posts) {
      if (selectedUrls.add(post.post.url)) selected.add(post);
      if (selected.length >= config.minPosts ||
          selected.length >= config.maxPosts) {
        break;
      }
    }
  }
  return selected;
}

DateTime? _parsePublishedDate(String value) {
  final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// 게시물 본문의 `26-08-12 18:24` 형식 작성 시각을 읽는다.
DateTime? parsePostPublishedAt(String html) {
  final document = html_parser.parse(html);
  final value = document.querySelector('.if_date')?.text ?? '';
  final match = RegExp(
    r'(\d{2}|\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})',
  ).firstMatch(value);
  if (match == null) return null;

  var year = int.parse(match.group(1)!);
  if (year < 100) year += 2000;
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final parsed = DateTime(year, month, day, hour, minute);
  if (parsed.year != year ||
      parsed.month != month ||
      parsed.day != day ||
      parsed.hour != hour ||
      parsed.minute != minute) {
    return null;
  }
  return parsed;
}

List<Uri> parsePostImageUrls(String html, Uri baseUri) {
  final document = html_parser.parse(html);
  final content = document.querySelector('#bo_v_con');
  if (content == null) return const [];

  final images = <Uri>[];
  final seen = <String>{};
  for (final anchor in content.querySelectorAll('a.view_image')) {
    final href = anchor.attributes['href'];
    if (href == null || href.isEmpty) continue;
    final viewerUri = baseUri.resolve(href);
    final original = viewerUri.queryParameters['fn'];
    final imageUri =
        original == null || original.isEmpty ? null : baseUri.resolve(original);
    if (imageUri != null &&
        _isHttpUri(imageUri) &&
        seen.add(imageUri.toString())) {
      images.add(imageUri);
    }
  }

  // 원본 링크가 없는 게시판 스킨은 본문 img를 사용한다.
  if (images.isEmpty) {
    for (final image in content.querySelectorAll('img')) {
      final src = image.attributes['src'];
      if (src == null || src.isEmpty) continue;
      final imageUri = baseUri.resolve(src);
      if (_isHttpUri(imageUri) && seen.add(imageUri.toString())) {
        images.add(imageUri);
      }
    }
  }
  return images;
}

String _normalizedText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isHttpUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
