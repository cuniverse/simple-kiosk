import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_kiosk/model/layout_config.dart';
import 'package:simple_kiosk/model/menu_topic.dart';
import 'package:simple_kiosk/model/menu_language.dart';
import 'package:simple_kiosk/widget/language_selection.dart';

Map<String, dynamic> topicJson({bool? showIcon}) => {
      'id': 'general',
      'label': 'General',
      'icon': 'icon:category',
      if (showIcon != null) 'showIcon': showIcon,
      'items': [
        {'id': 'home', 'title': 'Home', 'url': 'https://example.com'},
      ],
    };

void main() {
  test('주제 아이콘 설정은 생략 가능하며 bool만 허용한다', () {
    expect(LayoutConfig.fromJson({}).hideTopicIcons, isFalse);
    expect(
        LayoutConfig.fromJson({'hideTopicIcons': true}).hideTopicIcons, isTrue);
    expect(() => LayoutConfig.fromJson({'hideTopicIcons': 'true'}),
        throwsFormatException);
    expect(MenuTopic.fromJson(topicJson(), 0, 0).showIcon, isNull);
    expect(
        MenuTopic.fromJson(topicJson(showIcon: false), 0, 0).showIcon, isFalse);
    expect(
      () => MenuTopic.fromJson({...topicJson(), 'showIcon': 'false'}, 0, 0),
      throwsFormatException,
    );
  });

  for (final hideTopicIcons in [false, true]) {
    for (final showIcon in <bool?>[null, false, true]) {
      testWidgets('주제 아이콘 hide=$hideTopicIcons, override=$showIcon',
          (tester) async {
        var selected = false;
        final topic = MenuTopic.fromJson(topicJson(showIcon: showIcon), 0, 0);
        await tester.pumpWidget(MaterialApp(
          home: LanguageSelection(
            title: 'Languages',
            subtitle: '',
            skipSingleTopic: false,
            hideTopicIcons: hideTopicIcons,
            languages: [
              MenuLanguage(
                id: 'en',
                label: 'English',
                icon: 'icon:language',
                items: topic.items,
                topics: [topic],
              ),
            ],
            onSelected: (language, topic) {
              expect(language, 0);
              expect(topic, 0);
              selected = true;
            },
            onReturnToIdle: () {},
          ),
        ));
        final languageButton = find.byKey(const ValueKey('language-en'));
        expect(find.descendant(of: languageButton, matching: find.byType(Icon)),
            findsOneWidget);
        await tester.tap(languageButton);
        await tester.pumpAndSettle();
        final topicButton = find.byKey(const ValueKey('topic-general'));
        expect(
          find.descendant(of: topicButton, matching: find.byType(Icon)),
          (showIcon ?? !hideTopicIcons) ? findsOneWidget : findsNothing,
        );
        expect(topic.icon, 'icon:category');
        await tester.ensureVisible(topicButton);
        await tester.tap(topicButton);
        expect(selected, isTrue);
      });
    }
  }
}
