import 'package:flutter/material.dart';

/// `menu.json`의 `"icon": "icon:home"` 처럼 문자열로 Material 아이콘을
/// 지정할 수 있도록 매핑 테이블을 제공한다.
///
/// 트리 셰이킹 호환성을 위해 [IconData] 인스턴스를 직접 매핑한다.
/// 새 아이콘이 필요하면 이 맵에 추가하면 된다.
class MaterialIconRegistry {
  static const Map<String, IconData> _icons = {
    // 사이니지에서 자주 쓰는 아이콘들.
    'home': Icons.home_filled,
    'notice': Icons.campaign_outlined,
    'announcement': Icons.campaign_outlined,
    'gallery': Icons.photo_library_outlined,
    'photo': Icons.photo_outlined,
    'video': Icons.play_circle_outline,
    'movie': Icons.movie_outlined,
    'info': Icons.info_outline,
    'church': Icons.church_outlined,
    'menu': Icons.menu,
    'list': Icons.list_alt,
    'calendar': Icons.calendar_today,
    'event': Icons.event_outlined,
    'mail': Icons.mail_outline,
    'phone': Icons.phone_outlined,
    'map': Icons.map_outlined,
    'location': Icons.location_on_outlined,
    'settings': Icons.settings_outlined,
    'book': Icons.menu_book_outlined,
    'document': Icons.description_outlined,
    'news': Icons.newspaper_outlined,
    'people': Icons.people_outline,
    'group': Icons.groups_outlined,
    'category': Icons.category_outlined,
    'topic': Icons.topic_outlined,
    'star': Icons.star_outline,
    'favorite': Icons.favorite_outline,
    'search': Icons.search,
    'help': Icons.help_outline,
    'link': Icons.link,
    'web': Icons.public,
    'music': Icons.music_note_outlined,
    'mic': Icons.mic_outlined,
    'camera': Icons.photo_camera_outlined,
    'image': Icons.image_outlined,
    'download': Icons.download_outlined,
    'qr': Icons.qr_code_2,
  };

  /// 주어진 키([key])에 해당하는 [IconData]를 반환한다. 없으면 `null`.
  static IconData? lookup(String key) => _icons[key.toLowerCase()];

  /// 등록된 모든 키.
  static Iterable<String> get keys => _icons.keys;
}
