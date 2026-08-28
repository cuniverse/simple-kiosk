import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../model/idle_config.dart';

/// 포토갤러리 게시물의 사진 한 장과 표시할 게시물 제목.
class GalleryFeedItem {
  final String title;
  final String imageUrl;
  final String postUrl;
  final String? youtubeVideoId;

  const GalleryFeedItem({
    required this.title,
    required this.imageUrl,
    required this.postUrl,
    this.youtubeVideoId,
  });

  bool get isYoutube => youtubeVideoId != null;

  String get playbackId =>
      youtubeVideoId == null ? imageUrl : 'youtube:$youtubeVideoId';
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
      config.effectiveSources.map((source) async {
        try {
          return await _loadBoard(source);
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
        if (seen.add(item.playbackId)) items.add(item);
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
    GallerySourceConfig source,
  ) async {
    final listUri = Uri.parse(source.url);
    final listHtml = await _getText(listUri);
    final parsedPosts = _parseGalleryPosts(listHtml, listUri);
    final requestedAt = _now();
    final posts = _selectGalleryCandidates(parsedPosts, source, requestedAt);
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
          final youtubeVideoIds = parsePostYoutubeVideoIds(postHtml);
          if (youtubeVideoIds.isNotEmpty) {
            final items = youtubeVideoIds
                .map(
                  (videoId) => GalleryFeedItem(
                    title: post.title,
                    imageUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                    postUrl: post.url.toString(),
                    youtubeVideoId: videoId,
                  ),
                )
                .toList(growable: false);
            return _LoadedGalleryPost(
              post: post,
              publishedAt: publishedAt,
              items: items,
            );
          }
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
      source,
      requestedAt,
    );

    final seen = <String>{};
    final items = <GalleryFeedItem>[];
    for (final group in selectedPosts) {
      for (final item in group.items) {
        if (seen.add(item.playbackId)) items.add(item);
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

  // 그누보드 갤러리 스킨마다 외곽 구조는 `.card`, `.gall_li` 등으로
  // 다르지만 게시물 제목 링크인 `a.bo_tit`은 공통으로 제공된다.
  for (final titleLink in document.querySelectorAll('a.bo_tit')) {
    final container = _galleryPostContainer(titleLink);
    final titleElement = titleLink.querySelector('.ks4');
    final directTitle = _normalizedText(
      titleLink.nodes
          .whereType<html_dom.Text>()
          .map((node) => node.data)
          .join(' '),
    );
    final title = _normalizedText(titleElement?.text ?? directTitle);
    if (title.startsWith('#')) continue;
    final linkElement = titleLink.attributes['href']?.isNotEmpty == true
        ? titleLink
        : container.querySelector('a.img-card') ??
            container.querySelector('.gall_img a');
    final href = linkElement?.attributes['href'];
    if (href == null || href.isEmpty || title.isEmpty) continue;

    final postUri = baseUri.resolve(href);
    if (!_isHttpUri(postUri) || !seen.add(postUri.toString())) continue;

    final thumbnailSrc = (container.querySelector('a.img-card img') ??
            container.querySelector('.gall_img img') ??
            container.querySelector('img'))
        ?.attributes['src'];
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
          container.querySelector('.gall_date')?.text ?? '',
        ),
      ),
    );
  }
  return posts;
}

html_dom.Element _galleryPostContainer(html_dom.Element titleLink) {
  html_dom.Element? current = titleLink.parent;
  html_dom.Element? structuralMatch;
  while (current != null) {
    if (current.classes.contains('card') ||
        current.classes.contains('gall_li')) {
      return current;
    }
    if (structuralMatch == null &&
        current.querySelector('img') != null &&
        current.querySelector('.gall_date') != null) {
      structuralMatch = current;
    }
    if (current.localName == 'form' || current.localName == 'body') break;
    current = current.parent;
  }
  return structuralMatch ?? titleLink.parent ?? titleLink;
}

List<_GalleryPost> _selectGalleryCandidates(
  List<_GalleryPost> posts,
  GallerySourceConfig source,
  DateTime now,
) {
  final lookbackDays = source.lookbackDays;
  if (lookbackDays == null) {
    return posts.take(source.maxPosts).toList(growable: false);
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
      if (selected.length >= source.maxPosts) return selected;
    }
  }

  // 기간 조건의 결과가 없거나 부족할 경우에 대비해 최신 게시물을 후보에 포함한다.
  if (selected.length < source.minPosts) {
    for (final post in posts) {
      if (selectedUrls.add(post.url)) selected.add(post);
      if (selected.length >= source.minPosts ||
          selected.length >= source.maxPosts) {
        break;
      }
    }
  }
  return selected;
}

List<_LoadedGalleryPost> _selectLoadedGalleryPosts(
  List<_LoadedGalleryPost> posts,
  GallerySourceConfig source,
  DateTime now,
) {
  final lookbackDays = source.lookbackDays;
  if (lookbackDays == null) {
    return posts.take(source.maxPosts).toList(growable: false);
  }

  final cutoff = now.subtract(Duration(days: lookbackDays));
  final selected = <_LoadedGalleryPost>[];
  final selectedUrls = <Uri>{};
  for (final post in posts) {
    final publishedAt = post.publishedAt;
    if (publishedAt != null && !publishedAt.isBefore(cutoff)) {
      selected.add(post);
      selectedUrls.add(post.post.url);
      if (selected.length >= source.maxPosts) return selected;
    }
  }

  if (selected.length < source.minPosts) {
    for (final post in posts) {
      if (selectedUrls.add(post.post.url)) selected.add(post);
      if (selected.length >= source.minPosts ||
          selected.length >= source.maxPosts) {
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

List<String> parsePostYoutubeVideoIds(String html) {
  final document = html_parser.parse(html);
  final content = document.querySelector('#bo_v_con');
  if (content == null) return const [];

  final videoIds = <String>[];
  final seen = <String>{};
  for (final element in content.querySelectorAll('iframe[src], a[href]')) {
    final value = element.attributes['src'] ?? element.attributes['href'];
    final videoId = value == null ? null : _youtubeVideoId(value);
    if (videoId != null && seen.add(videoId)) videoIds.add(videoId);
  }

  // 일부 게시판은 YouTube 주소를 링크로 만들지 않고 본문 텍스트로 저장한다.
  final urlPattern = RegExp(
    r'''(?:https?:)?//(?:www\.|m\.)?(?:youtube\.com|youtube-nocookie\.com|youtu\.be)/[^\s<"']+''',
    caseSensitive: false,
  );
  for (final match in urlPattern.allMatches(content.text)) {
    final videoId = _youtubeVideoId(match.group(0)!);
    if (videoId != null && seen.add(videoId)) videoIds.add(videoId);
  }
  return videoIds;
}

String? _youtubeVideoId(String value) {
  var candidate = value.trim().replaceAll('&amp;', '&');
  if (candidate.startsWith('//')) candidate = 'https:$candidate';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? videoId;
  if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
    if (uri.pathSegments.isNotEmpty) videoId = uri.pathSegments.first;
  } else if (host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com')) {
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'watch') {
      videoId = uri.queryParameters['v'];
    } else if (uri.pathSegments.length >= 2 &&
        const {'embed', 'shorts', 'live'}.contains(uri.pathSegments.first)) {
      videoId = uri.pathSegments[1];
    }
  }
  if (videoId == null) return null;
  final normalized = videoId.split(RegExp(r'[?&#/]')).first;
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(normalized)
      ? normalized
      : null;
}

String _normalizedText(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

bool _isHttpUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
