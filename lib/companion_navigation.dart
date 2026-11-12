import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_theme.dart';

abstract final class CompanionPage {
  static const overview = 'overview';
  static const activity = 'activity';
  static const accounts = 'accounts';
  static const plan = 'plan';
  static const insights = 'insights';
  static const more = 'more';
  static const cards = '/cards';

  static const _corePages = {
    overview,
    activity,
    accounts,
    plan,
    insights,
    more,
  };

  static String resolveDefault(String? value, {required bool cardsEnabled}) {
    if (_corePages.contains(value)) return value!;
    if (value == cards && cardsEnabled) return cards;
    return overview;
  }

  static String restorePage({
    required String? savedPage,
    required String currentPage,
    required bool cardsEnabled,
    required int startingRevision,
    required int currentRevision,
  }) => startingRevision == currentRevision
      ? resolveDefault(savedPage, cardsEnabled: cardsEnabled)
      : currentPage;

  static List<(String, String)> defaultOptions({required bool cardsEnabled}) =>
      [
        (overview, 'Overview'),
        (activity, 'Activity'),
        (accounts, 'Accounts'),
        (plan, 'Plan'),
        (insights, 'Insights'),
        (more, 'More'),
        if (cardsEnabled) (cards, 'Cards'),
      ];

  static int bottomIndex(String page) => switch (page) {
    overview => 0,
    activity => 1,
    accounts => 2,
    plan => 3,
    _ => 4,
  };
}

class MorePages extends StatelessWidget {
  const MorePages({
    required this.cardsEnabled,
    required this.cardsTitle,
    required this.onOpen,
    super.key,
  });
  final bool cardsEnabled;
  final String cardsTitle;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => FinanceList(
    children: [
      const Eyebrow('More'),
      const SectionTitle('More pages'),
      Panel(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_graph_outlined),
                title: const Text('Insights'),
                subtitle: const Text('Spending trends and recurring payments'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(CompanionPage.insights),
              ),
              if (cardsEnabled) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.credit_card_outlined),
                  title: Text(cardsTitle),
                  subtitle: const Text(
                    'Compare card benefits and manage your wallet',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onOpen(CompanionPage.cards),
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}
