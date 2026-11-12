import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/companion_navigation.dart';

void main() {
  test(
    'default pages include Cards only while its contribution is enabled',
    () {
      expect(
        CompanionPage.resolveDefault(CompanionPage.cards, cardsEnabled: false),
        CompanionPage.overview,
      );
      expect(
        CompanionPage.resolveDefault(CompanionPage.cards, cardsEnabled: true),
        CompanionPage.cards,
      );
      expect(
        CompanionPage.resolveDefault('unknown-plugin-page', cardsEnabled: true),
        CompanionPage.overview,
      );
      expect(
        CompanionPage.defaultOptions(cardsEnabled: false)
            .map((item) => item.$1),
        isNot(contains(CompanionPage.cards)),
      );
      expect(
        CompanionPage.defaultOptions(cardsEnabled: true).map((item) => item.$1),
        contains(CompanionPage.cards),
      );
    },
  );

  test(
    'a delayed Cards lookup cannot override a page chosen in the meantime',
    () {
      expect(
        CompanionPage.restorePage(
          savedPage: CompanionPage.cards,
          currentPage: CompanionPage.activity,
          cardsEnabled: true,
          startingRevision: 0,
          currentRevision: 1,
        ),
        CompanionPage.activity,
      );
      expect(
        CompanionPage.restorePage(
          savedPage: CompanionPage.cards,
          currentPage: CompanionPage.overview,
          cardsEnabled: true,
          startingRevision: 0,
          currentRevision: 0,
        ),
        CompanionPage.cards,
      );
    },
  );

  testWidgets('More lists Insights and only enabled plugin pages', (
    tester,
  ) async {
    var opened = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MorePages(
            cardsEnabled: false,
            cardsTitle: 'Cards',
            onOpen: (page) => opened = page,
          ),
        ),
      ),
    );
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Cards'), findsNothing);
    await tester.tap(find.text('Insights'));
    expect(opened, CompanionPage.insights);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MorePages(
            cardsEnabled: true,
            cardsTitle: 'Cards',
            onOpen: (page) => opened = page,
          ),
        ),
      ),
    );
    expect(find.text('Cards'), findsOneWidget);
    await tester.tap(find.text('Cards'));
    expect(opened, CompanionPage.cards);
  });
}
