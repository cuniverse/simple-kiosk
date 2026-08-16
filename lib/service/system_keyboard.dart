import 'keyboard_controller.dart';

/// 가상 키보드 호출 API (호환용 래퍼).
///
/// 내부적으로 [KeyboardController.instance] 의 표시 상태만 토글한다. 실제
/// 키보드 UI 는 `VirtualKeyboardOverlay` 가 그린다. OS 시스템 키보드는
/// 사용하지 않는다(사이니지 환경 일관성을 위해 모든 OS 에서 동일한 Flutter
/// 가상 키보드를 사용).
class SystemKeyboard {
  static Future<void> show() async {
    KeyboardController.instance.show();
  }

  static Future<void> hide() async {
    KeyboardController.instance.hide();
  }
}
