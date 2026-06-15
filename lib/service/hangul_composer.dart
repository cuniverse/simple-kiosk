import 'keyboard_controller.dart';

/// 두벌식 한글 자모 조합기.
///
/// 입력은 두벌식 키보드의 단일 자모(또는 영문/숫자/특수문자) 한 글자씩
/// 받는다. 자모는 호환 자모(U+3131..U+3163) 가 아니라 일반 한글 자모
/// (`ㄱ`,`ㄴ`,...) 로 들어온다고 가정한다.
///
/// 출력은 [InsertText] / [ReplaceLast] 의 시퀀스로, [KeyboardController.dispatch]
/// 로 그대로 흘리면 된다.
///
/// 알고리즘 요약(두벌식):
/// - 자음 입력
///   - 조합 없음: ㄱ → 새 음절 "ㄱ" append (compose=ㄱ 단일 자음 상태)
///   - 초성만 있음(ㄱ): ㄴ → "ㄱ" 확정 + "ㄴ" 새로 append (둘 다 단일 자음)
///   - 초성+중성(가): ㄱ → "각" 종성 채워 replace
///   - 초성+중성+종성(각): ㄴ → 종성 ㄱ→ㄴ 변경 시도, 이미 종성이면 "각" 유지 + "ㄴ" 새 append
///   - 종성 + 다음 모음 → 종성 분리: 각 + ㅏ → "가" + "카" 가 아니라 "가" + "가" 잘못된 예. 정확히는 "각" → "가"+"가". 자세한 건 코드 참고.
/// - 모음 입력
///   - 조합 없음: ㅏ → 호환 자모 그대로 append (자음/모음 단독은 호환자모로 표시)
///   - 초성만 있음(ㄱ): ㅏ → "가" replace
///   - 초성+중성(가): ㅑ → 이중모음 결합 시도(없으면 "가" 확정 + "ㅑ" 새 append)
///   - 초성+중성+종성(각): ㅏ → 종성을 다음 음절 초성으로 분리. "각" → "가" + "카" 가 아닌, 종성ㄱ 을 떼서 → "가" 로 줄이고 + "가" 새 음절 push
class HangulComposer {
  // 두벌식 자모 인덱스 변환용 데이터.
  // 초성 19자
  static const List<String> _cho = [
    'ㄱ',
    'ㄲ',
    'ㄴ',
    'ㄷ',
    'ㄸ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅃ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅉ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];
  // 중성 21자
  static const List<String> _jung = [
    'ㅏ',
    'ㅐ',
    'ㅑ',
    'ㅒ',
    'ㅓ',
    'ㅔ',
    'ㅕ',
    'ㅖ',
    'ㅗ',
    'ㅘ',
    'ㅙ',
    'ㅚ',
    'ㅛ',
    'ㅜ',
    'ㅝ',
    'ㅞ',
    'ㅟ',
    'ㅠ',
    'ㅡ',
    'ㅢ',
    'ㅣ',
  ];
  // 종성 27자 (0 = 종성 없음, 1..27)
  static const List<String> _jong = [
    '',
    'ㄱ',
    'ㄲ',
    'ㄳ',
    'ㄴ',
    'ㄵ',
    'ㄶ',
    'ㄷ',
    'ㄹ',
    'ㄺ',
    'ㄻ',
    'ㄼ',
    'ㄽ',
    'ㄾ',
    'ㄿ',
    'ㅀ',
    'ㅁ',
    'ㅂ',
    'ㅄ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];

  // 모음 결합 규칙: (현재 중성 + 입력 모음) -> 결합 모음
  static const Map<String, String> _vowelCombine = {
    'ㅗㅏ': 'ㅘ',
    'ㅗㅐ': 'ㅙ',
    'ㅗㅣ': 'ㅚ',
    'ㅜㅓ': 'ㅝ',
    'ㅜㅔ': 'ㅞ',
    'ㅜㅣ': 'ㅟ',
    'ㅡㅣ': 'ㅢ',
  };
  // 결합 모음 분리 (백스페이스/종성-초성 전환 시)
  static const Map<String, List<String>> _vowelSplit = {
    'ㅘ': ['ㅗ', 'ㅏ'],
    'ㅙ': ['ㅗ', 'ㅐ'],
    'ㅚ': ['ㅗ', 'ㅣ'],
    'ㅝ': ['ㅜ', 'ㅓ'],
    'ㅞ': ['ㅜ', 'ㅔ'],
    'ㅟ': ['ㅜ', 'ㅣ'],
    'ㅢ': ['ㅡ', 'ㅣ'],
  };
  // 종성 결합: (현재 종성 + 새 자음) -> 결합 종성
  static const Map<String, String> _jongCombine = {
    'ㄱㅅ': 'ㄳ',
    'ㄴㅈ': 'ㄵ',
    'ㄴㅎ': 'ㄶ',
    'ㄹㄱ': 'ㄺ',
    'ㄹㅁ': 'ㄻ',
    'ㄹㅂ': 'ㄼ',
    'ㄹㅅ': 'ㄽ',
    'ㄹㅌ': 'ㄾ',
    'ㄹㅍ': 'ㄿ',
    'ㄹㅎ': 'ㅀ',
    'ㅂㅅ': 'ㅄ',
  };
  // 결합 종성 분리
  static const Map<String, List<String>> _jongSplit = {
    'ㄳ': ['ㄱ', 'ㅅ'],
    'ㄵ': ['ㄴ', 'ㅈ'],
    'ㄶ': ['ㄴ', 'ㅎ'],
    'ㄺ': ['ㄹ', 'ㄱ'],
    'ㄻ': ['ㄹ', 'ㅁ'],
    'ㄼ': ['ㄹ', 'ㅂ'],
    'ㄽ': ['ㄹ', 'ㅅ'],
    'ㄾ': ['ㄹ', 'ㅌ'],
    'ㄿ': ['ㄹ', 'ㅍ'],
    'ㅀ': ['ㄹ', 'ㅎ'],
    'ㅄ': ['ㅂ', 'ㅅ'],
  };

  // 현재 조합 상태. 모두 한글 자모 문자(또는 빈 문자열).
  String _cho1 = '';
  String _jung1 = '';
  String _jong1 = '';

  bool get _hasCompose => _cho1.isNotEmpty || _jung1.isNotEmpty;

  /// 외부에 노출되는 "조합 중인 글자". 단일 자음/모음만 있는 상태에서는 그
  /// 호환 자모 한 글자, 그 이상이면 조합된 음절.
  String _currentSyllable() {
    if (!_hasCompose) return '';
    if (_cho1.isNotEmpty && _jung1.isEmpty && _jong1.isEmpty) return _cho1;
    if (_cho1.isEmpty && _jung1.isNotEmpty && _jong1.isEmpty) return _jung1;
    // 초성+중성(+종성)
    final ci = _cho.indexOf(_cho1);
    final ji = _jung.indexOf(_jung1);
    final ki = _jong.indexOf(_jong1);
    if (ci < 0 || ji < 0 || ki < 0) {
      // 안전망: 인덱스 매핑 실패 시 자모 그대로 이어 붙임.
      return '$_cho1$_jung1$_jong1';
    }
    return String.fromCharCode(0xAC00 + (ci * 21 + ji) * 28 + ki);
  }

  void reset() {
    _cho1 = '';
    _jung1 = '';
    _jong1 = '';
  }

  /// 외부에서 한글 외의 키(영문/숫자/특수)나 화면 클릭으로 조합 상태를
  /// 강제 종료하고 싶을 때 호출. 마지막 음절은 그대로 확정된 상태로 남는다.
  /// 별도 이벤트 발행 없음(이미 화면에 들어가 있는 문자 그대로).
  void commit() => reset();

  /// 한 자모(또는 결합 자모) 입력. 결과 이벤트 시퀀스 반환.
  List<KeyboardEvent> input(String jamo) {
    if (_isVowel(jamo)) {
      return _inputVowel(jamo);
    } else if (_cho.contains(jamo) || _jong.contains(jamo)) {
      return _inputConsonant(jamo);
    }
    // 자모 아닌 입력 → 현재 조합 종료 + 그대로 삽입
    final events = <KeyboardEvent>[];
    if (_hasCompose) {
      reset();
    }
    events.add(InsertText(jamo));
    return events;
  }

  /// 백스페이스. 조합 중이면 한 자모씩 되돌린다. 조합 중이 아니면 일반
  /// [BackspaceEvent] 반환(외부에서 텍스트 한 글자 삭제).
  List<KeyboardEvent> backspace() {
    if (!_hasCompose) return const [BackspaceEvent()];
    // 종성 → 중성 → 초성 순으로 한 단계씩 제거.
    if (_jong1.isNotEmpty) {
      final parts = _jongSplit[_jong1];
      if (parts != null) {
        _jong1 = parts[0];
      } else {
        _jong1 = '';
      }
    } else if (_jung1.isNotEmpty) {
      final parts = _vowelSplit[_jung1];
      if (parts != null) {
        _jung1 = parts[0];
      } else {
        _jung1 = '';
      }
    } else if (_cho1.isNotEmpty) {
      _cho1 = '';
    }
    final after = _currentSyllable();
    if (after.isEmpty) {
      // 조합이 비었으니 직전 글자 자체를 제거.
      return const [BackspaceEvent()];
    }
    return [ReplaceLast(after)];
  }

  bool _isVowel(String s) =>
      _jung.contains(s) || _vowelCombine.values.contains(s);

  List<KeyboardEvent> _inputConsonant(String c) {
    final events = <KeyboardEvent>[];
    if (!_hasCompose) {
      // 초성 단독.
      _cho1 = c;
      events.add(InsertText(c));
      return events;
    }
    if (_cho1.isNotEmpty && _jung1.isEmpty) {
      // 초성만 있는 상태에서 자음 또 입력 → 이전 자음 확정, 새 자음 시작.
      reset();
      _cho1 = c;
      events.add(InsertText(c));
      return events;
    }
    // 초성+중성(+종성) 상태.
    if (_jong1.isEmpty) {
      // 종성으로 채워본다(가능한 자음만).
      if (_jong.contains(c)) {
        _jong1 = c;
        events.add(ReplaceLast(_currentSyllable()));
        return events;
      }
      // 종성으로 못 쓰는 자음(예: ㄸ,ㅃ,ㅉ) → 음절 확정, 새 자음 시작.
      reset();
      _cho1 = c;
      events.add(InsertText(c));
      return events;
    }
    // 이미 종성 있음 → 결합 종성 시도.
    final combined = _jongCombine['$_jong1$c'];
    if (combined != null) {
      _jong1 = combined;
      events.add(ReplaceLast(_currentSyllable()));
      return events;
    }
    // 결합 불가 → 음절 확정 + 새 자음 시작.
    reset();
    _cho1 = c;
    events.add(InsertText(c));
    return events;
  }

  List<KeyboardEvent> _inputVowel(String v) {
    final events = <KeyboardEvent>[];
    if (!_hasCompose) {
      // 모음 단독 → 호환 자모 그대로 표시(조합 상태로 저장).
      _jung1 = v;
      events.add(InsertText(v));
      return events;
    }
    if (_cho1.isNotEmpty && _jung1.isEmpty && _jong1.isEmpty) {
      // 초성+모음 → 음절 형성.
      _jung1 = v;
      events.add(ReplaceLast(_currentSyllable()));
      return events;
    }
    if (_cho1.isEmpty && _jung1.isNotEmpty && _jong1.isEmpty) {
      // 모음 단독 + 모음 → 이중모음 결합 시도.
      final combined = _vowelCombine['$_jung1$v'];
      if (combined != null) {
        _jung1 = combined;
        events.add(ReplaceLast(_currentSyllable()));
        return events;
      }
      // 결합 불가 → 분리 push.
      reset();
      _jung1 = v;
      events.add(InsertText(v));
      return events;
    }
    if (_cho1.isNotEmpty && _jung1.isNotEmpty && _jong1.isEmpty) {
      // 초성+중성 → 이중모음 결합 시도.
      final combined = _vowelCombine['$_jung1$v'];
      if (combined != null) {
        _jung1 = combined;
        events.add(ReplaceLast(_currentSyllable()));
        return events;
      }
      // 결합 불가 → 현재 음절 확정, 새 음절(모음 단독)로.
      reset();
      _jung1 = v;
      events.add(InsertText(v));
      return events;
    }
    // 초성+중성+종성 + 모음 → 종성을 다음 음절의 초성으로 이동.
    final jongChars = _jongSplit[_jong1] ?? [_jong1];
    // 결합 종성이면 마지막만 떼어 이동.
    final moveCho = jongChars.last;
    final leftJong = jongChars.length == 2 ? jongChars[0] : '';

    final prevCho = _cho1;
    final prevJung = _jung1;
    _cho1 = prevCho;
    _jung1 = prevJung;
    _jong1 = leftJong;
    final shrunk = _currentSyllable();

    // 새 음절 초기화.
    reset();
    _cho1 = moveCho;
    _jung1 = v;
    final newSyllable = _currentSyllable();

    events.add(ReplaceLast(shrunk));
    events.add(InsertText(newSyllable));
    return events;
  }
}
