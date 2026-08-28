/// 터치 입력 폭주가 WebView 생성·재로드 작업으로 그대로 증폭되는 것을 막는다.
class TouchInputGuard<T> {
  final Duration selectionInterval;
  final Duration reloadInterval;

  DateTime? _lastSelectionAt;
  T? _lastSelectionKey;
  final Map<T, DateTime> _lastReloadAt = {};

  TouchInputGuard({
    this.selectionInterval = const Duration(milliseconds: 120),
    this.reloadInterval = const Duration(seconds: 2),
  });

  bool acceptSelection(T key, DateTime now) {
    final previous = _lastSelectionAt;
    if (previous != null && now.difference(previous) < selectionInterval) {
      // 같은 메뉴의 빠른 두 번째 탭은 정상 더블 탭일 수 있으므로 허용한다.
      // 서로 다른 메뉴를 연속으로 누를 때만 WebView 전환 폭주를 합친다.
      if (_lastSelectionKey != key) return false;
    }
    _lastSelectionAt = now;
    _lastSelectionKey = key;
    return true;
  }

  bool acceptReload(T key, DateTime now) {
    final previous = _lastReloadAt[key];
    if (previous != null && now.difference(previous) < reloadInterval) {
      return false;
    }
    _lastReloadAt[key] = now;
    return true;
  }

  void clear() {
    _lastSelectionAt = null;
    _lastSelectionKey = null;
    _lastReloadAt.clear();
  }
}
