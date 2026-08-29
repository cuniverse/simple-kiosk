import 'package:characters/characters.dart';

const String buttonWordJoiner = '\u2060';

/// 버튼 문구의 공백은 줄바꿈 후보로 두고 단어 내부는 분리되지 않게 한다.
///
/// Unicode WORD JOINER는 표시 폭이 없으며 인접한 문자 사이의
/// 줄바꿈을 금지한다. 그래핀 클러스터 단위로 처리해 조합 문자와
/// 이모지를 훼손하지 않는다.
String keepButtonWordsTogether(String value) {
  final result = StringBuffer();
  var previousWasWord = false;
  for (final character in value.characters) {
    final isWhitespace = character.trim().isEmpty;
    if (!isWhitespace && previousWasWord) result.write(buttonWordJoiner);
    result.write(character);
    previousWasWord = !isWhitespace;
  }
  return result.toString();
}

Iterable<String> buttonTextWords(String value) =>
    value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
