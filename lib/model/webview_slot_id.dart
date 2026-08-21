import 'package:flutter/foundation.dart';

/// WebView 상태와 컨트롤러를 식별하는 안정적인 키.
///
/// 배열 인덱스를 사용하지 않으므로 순서가 바뀌어도 같은 언어·주제·메뉴를 계속
/// 가리키며, 서로 다른 주제에서 동일한 메뉴 ID를 사용해도 충돌하지 않는다.
@immutable
class WebViewSlotId {
  final String languageId;
  final String topicId;
  final String menuId;

  const WebViewSlotId({
    required this.languageId,
    this.topicId = 'default',
    required this.menuId,
  });

  @override
  bool operator ==(Object other) =>
      other is WebViewSlotId &&
      other.languageId == languageId &&
      other.topicId == topicId &&
      other.menuId == menuId;

  @override
  int get hashCode => Object.hash(languageId, topicId, menuId);

  @override
  String toString() => '$languageId/$topicId/$menuId';
}

/// WebView 트리가 교체된 뒤 이전 트리에서 도착한 콜백을 구분한다.
class WebViewGeneration {
  int _value = 0;

  int get value => _value;

  int next() => ++_value;

  bool isCurrent(int candidate) => candidate == _value;
}
