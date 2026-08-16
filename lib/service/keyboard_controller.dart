import 'package:flutter/foundation.dart';

/// 가상 키보드 표시 요청 콜백.
typedef KeyEventCallback = void Function(KeyboardEvent event);

/// 키보드 → WebView 로 전달되는 입력 이벤트.
sealed class KeyboardEvent {
  const KeyboardEvent();
}

/// 일반 문자(이미 조합 완료된 한 글자 또는 영문/숫자) 를 텍스트 끝에 삽입.
class InsertText extends KeyboardEvent {
  final String text;
  const InsertText(this.text);
}

/// 현재 커서 직전 글자를 [text] 로 교체. 한글 조합 중 음절 갱신용
/// (예: ㄱ → 가 → 각 처럼 동일 위치에서 음절 형태가 변할 때).
class ReplaceLast extends KeyboardEvent {
  final String text;
  const ReplaceLast(this.text);
}

/// 백스페이스. (조합 중이라면 [HangulComposer] 가 자체적으로 ReplaceLast/None
/// 으로 환원하므로 외부에서는 거의 사용되지 않는다.)
class BackspaceEvent extends KeyboardEvent {
  const BackspaceEvent();
}

/// Enter (form submit 또는 keydown 이벤트 디스패치).
class EnterEvent extends KeyboardEvent {
  const EnterEvent();
}

/// 가상 키보드 표시/비표시 상태와, 키 입력 콜백을 외부와 연결하는 컨트롤러.
///
/// 단일 인스턴스로 동작한다: 사이니지 화면 어디에서든 같은 키보드를 호출/감춤.
class KeyboardController {
  KeyboardController._();
  static final KeyboardController instance = KeyboardController._();

  /// 현재 키보드 표시 여부. Overlay 가 이 값을 구독해 표시/제거를 결정한다.
  final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  /// 입력 이벤트 수신자. 보통 [KioskWebView] 가 등록한다.
  KeyEventCallback? _onKey;

  void attach(KeyEventCallback onKey) {
    _onKey = onKey;
  }

  void detach(KeyEventCallback onKey) {
    if (_onKey == onKey) _onKey = null;
  }

  void dispatch(KeyboardEvent event) {
    _onKey?.call(event);
  }

  void show() {
    if (!visible.value) visible.value = true;
  }

  void hide() {
    if (visible.value) visible.value = false;
  }

  void toggle() {
    visible.value = !visible.value;
  }
}
