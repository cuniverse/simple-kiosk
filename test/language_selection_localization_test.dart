import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/menu_item.dart';
import 'package:simple_kiosk/model/menu_language.dart';
import 'package:simple_kiosk/model/menu_topic.dart';
import 'package:simple_kiosk/widget/button_text_wrap.dart';
import 'package:simple_kiosk/widget/language_selection.dart';

void main() {
  const items = [
    MenuItem(id: 'home', title: 'Home', url: 'https://example.com'),
  ];

  test('주제 선택 문구는 언어 ID에 맞는 기본 번역을 사용한다', () {
    const language = MenuLanguage(
      id: 'en-US',
      label: 'English',
      items: items,
    );

    expect(language.topicSelectionTitle('전역 제목'), 'Select a topic');
    expect(
      language.topicSelectionSubtitle('전역 부제'),
      'Please select a topic',
    );
    expect(language.changeLanguageLabel, 'Choose another language');
  });

  test('언어별 주제 선택 문구를 설정으로 재정의한다', () {
    final language = MenuLanguage.fromJson({
      'id': 'en',
      'label': 'English',
      'topicSelectionTitle': 'Pick a section',
      'topicSelectionSubtitle': '',
      'changeLanguageLabel': 'Languages',
      'items': [
        {'id': 'home', 'title': 'Home', 'url': 'https://example.com'},
      ],
    }, 0);

    expect(language.topicSelectionTitle('전역 제목'), 'Pick a section');
    expect(language.topicSelectionSubtitle('전역 부제'), isEmpty);
    expect(language.changeLanguageLabel, 'Languages');
  });

  testWidgets('선택한 언어로 주제 화면 문구를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LanguageSelection(
          title: '언어를 선택하세요',
          subtitle: '',
          topicTitle: '주제를 선택하세요',
          topicSubtitle: '원하는 주제를 선택하세요',
          skipSingleTopic: false,
          languages: const [
            MenuLanguage(
              id: 'en',
              label: 'English',
              items: items,
              topics: [
                MenuTopic(id: 'general', label: 'General', items: items),
                MenuTopic(id: 'travel', label: 'Travel', items: items),
              ],
            ),
          ],
          onSelected: (_, __) {},
          onReturnToIdle: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('language-en')));
    await tester.pumpAndSettle();

    expect(find.text('Select a topic'), findsOneWidget);
    expect(find.text('Please select a topic'), findsOneWidget);
    final changeLanguageText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('change-language')),
        matching: find.byType(Text),
      ),
    );
    expect(
      changeLanguageText.data,
      keepButtonWordsTogether('Choose another language'),
    );
    expect(changeLanguageText.semanticsLabel, 'Choose another language');
    expect(find.text('주제를 선택하세요'), findsNothing);
  });
}
