import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/finance_widgets.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/greenhouse_theme.dart';
import 'package:greenhouse/overview.dart';

void main() {
  testWidgets('shows tabs, totals, and categorized account drilldowns', (
    tester,
  ) async {
    final client = _MockClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Liabilities'), findsOneWidget);
    expect(find.text('Total assets'), findsOneWidget);
    expect(find.text(r'$1,000.00'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Investments'), findsOneWidget);
    expect(find.text('Other assets'), findsOneWidget);
    expect(find.text('Loans'), findsNothing);
    expect(find.text('Credit cards'), findsNothing);
    expect(client.requests, isNot(contains('/accounts')));

    await tester.tap(find.text('Investments'));
    await tester.pumpAndSettle();
    expect(client.requests, contains('/accounts'));
    expect(find.text('Brokerage'), findsOneWidget);
    expect(find.text(r'$975.00'), findsOneWidget);
    expect(find.text(r'$500.00'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Liabilities'));
    await tester.pumpAndSettle();
    expect(find.text('Total liabilities'), findsOneWidget);
    expect(find.text(r'$300.00'), findsOneWidget);
    expect(find.text('Loans'), findsOneWidget);
    expect(find.text('Credit cards'), findsOneWidget);
    expect(find.text('Checking'), findsNothing);
    expect(find.text('Limited history'), findsOneWidget);

    await tester.tap(find.text('Loans'));
    await tester.pumpAndSettle();
    expect(find.text('Garden Loan'), findsOneWidget);
    expect(find.text(r'-$2,500.00'), findsOneWidget);
    expect(find.text('Closed loan'), findsNothing);
    expect(find.text('Garden Bank · ••4321'), findsOneWidget);

    await tester.tap(find.text('Garden Loan'));
    await tester.pumpAndSettle();
    expect(find.text('Account activity'), findsOneWidget);
    expect(find.text('Search transactions'), findsOneWidget);
    expect(client.transactionQueries.last['accountIds'], 'loan-1');
  });

  testWidgets('latest unknown balance never falls back to an older value', (
    tester,
  ) async {
    final client = _MockClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Checking'));
    await tester.pumpAndSettle();
    expect(find.text('Everyday checking'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Unavailable'),
      ),
      findsOneWidget,
    );
    expect(find.text(r'$123.45'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Investments'));
    await tester.pumpAndSettle();
    expect(find.text(r'$975.00'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Unavailable'),
      ),
      findsNWidgets(2),
    );
    expect(find.text(r'$500.00'), findsNothing);
  });

  testWidgets('unknownBalanceTypes suppresses the investment fallback', (
    tester,
  ) async {
    final client = _MockClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Investments'));
    await tester.pumpAndSettle();
    final wire = find.widgetWithText(ListTile, 'Wire brokerage');
    expect(wire, findsOneWidget);
    expect(
      find.descendant(of: wire, matching: find.text('Unavailable')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: wire, matching: find.text(r'$500.00')),
      findsNothing,
    );
  });

  testWidgets('keeps the summary when an older server has no breakdown', (
    tester,
  ) async {
    final client = _MockClient(
      picture: {
        'netWorth': _usd('70000'),
        'cash': _usd('40000'),
        'investments': _usd('30000'),
        'debt': _usd('0'),
        'history': [
          {'month': '2026-09', 'netWorth': _usd('65000')},
          {'month': '2026-10', 'netWorth': _usd('70000')},
        ],
      },
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Investments'), findsOneWidget);
    expect(find.text('Debt'), findsOneWidget);
    expect(find.text('Assets'), findsNothing);
    expect(find.text('Liabilities'), findsNothing);
    expect(client.requests, isNot(contains('/accounts')));
  });

  testWidgets('preserves unknown history gaps and single points', (
    tester,
  ) async {
    final client = _MockClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    final charts = tester
        .widgetList<TrendChart>(find.byType(TrendChart))
        .toList();
    expect(charts, hasLength(4));
    expect(
      charts.any((chart) => chart.points.any((point) => point.value == null)),
      isTrue,
    );
    expect(find.text('No recorded history'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Includes estimates'), findsOneWidget);
    final savingsChart = charts.firstWhere(
      (chart) => chart.label?.startsWith('Savings') == true,
    );
    expect(savingsChart.label, contains('includes estimates'));

    await tester.tap(find.text('Liabilities'));
    await tester.pumpAndSettle();
    final loanChart = tester
        .widgetList<TrendChart>(find.byType(TrendChart))
        .firstWhere((chart) => chart.label?.startsWith('Loans') == true);
    expect(
      loanChart.points.where((point) => point.value != null),
      hasLength(1),
    );
    expect(find.text('Limited history'), findsOneWidget);
  });

  testWidgets('fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _MockClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your financial picture'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  GreenhouseClient client, {
  Widget Function(BuildContext context, Widget child)? builder,
}) => MaterialApp(
  theme: greenhouseTheme(Brightness.light),
  builder: builder == null
      ? null
      : (context, child) => builder(context, child ?? const SizedBox.shrink()),
  home: Scaffold(
    body: Overview(client: client, onActivity: () {}),
  ),
);

Json _usd(String amount) => {'amount': amount, 'currency': 'USD'};

Json _point(
  String date,
  String? amount, {
  String currency = 'USD',
  bool estimated = false,
}) => {
  'date': date,
  'total': amount == null ? null : {'amount': amount, 'currency': currency},
  if (estimated) 'estimated': true,
};

Json _account(
  String id,
  String name,
  String kind,
  List<Json> balances, {
  bool closed = false,
  String connection = 'Garden Bank',
  List<String>? unknownBalanceTypes,
}) => {
  'account': {
    'id': id,
    'displayName': name,
    'kind': kind,
    'currency': 'USD',
    'mask': '4321',
    'isClosed': closed,
  },
  'kind': kind,
  'balances': balances,
  'connectionName': connection,
  'unknownBalanceTypes': ?unknownBalanceTypes,
};

Json _balance(
  String type,
  String? amount,
  String observedAt, {
  String currency = 'USD',
}) => {
  'balanceType': type,
  'amount': amount == null ? null : {'amount': amount, 'currency': currency},
  'observedAt': observedAt,
};

class _MockClient extends GreenhouseClient {
  _MockClient({Json? picture, List<Json>? accounts})
    : picture = picture ?? _defaultPicture,
      accounts = accounts ?? _defaultAccounts;

  final Json picture;
  final List<Json> accounts;
  final requests = <String>[];
  final transactionQueries = <Map<String, String>>[];

  @override
  Uri? get origin => Uri.parse('https://garden.test');

  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    requests.add(path);
    if (path == '/financial-picture') {
      return {
        'data': picture,
        'freshness': {'asOf': '2026-11-01T12:00:00.000Z'},
      };
    }
    if (path.startsWith('/months/')) {
      return {
        'data': {'income': _usd('500000'), 'postedSpending': _usd('100000')},
      };
    }
    if (path == '/transactions') {
      transactionQueries.add({...?query});
      return {'items': <Json>[]};
    }
    if (path == '/accounts') return {'items': accounts};
    return <String, dynamic>{};
  }
}

final _defaultPicture = <String, dynamic>{
  'netWorth': _usd('70000'),
  'cash': _usd('100000'),
  'investments': _usd('95000'),
  'debt': _usd('30000'),
  'history': [
    {'month': '2026-09', 'netWorth': _usd('65000')},
    {'month': '2026-10', 'netWorth': _usd('70000')},
  ],
  'breakdown': {
    'assets': _usd('100000'),
    'liabilities': _usd('30000'),
    'categories': [
      {
        'id': 'checking',
        'label': 'Checking',
        'side': 'assets',
        'total': _usd('40000'),
        'accountIds': ['checking-1'],
        'history': [
          _point('2026-10-01', '30000'),
          _point('2026-10-02', '40000'),
        ],
      },
      {
        'id': 'savings',
        'label': 'Savings',
        'side': 'assets',
        'total': _usd('60000'),
        'accountIds': ['savings-1'],
        'history': [
          _point('2026-10-01', '55000', currency: 'EUR', estimated: true),
          _point('2026-10-02', null),
          _point('2026-10-03', '60000', currency: 'EUR'),
        ],
      },
      {
        'id': 'investments',
        'label': 'Investments',
        'side': 'assets',
        'total': _usd('95000'),
        'accountIds': ['invest-1', 'invest-unknown', 'invest-wire'],
        'history': [
          _point('2026-10-01', '90000'),
          _point('2026-10-02', '95000'),
        ],
      },
      {
        'id': 'other-assets',
        'label': 'Other assets',
        'side': 'assets',
        'total': null,
        'accountIds': ['other-1'],
        'history': [_point('2026-10-01', null)],
      },
      {
        'id': 'loans',
        'label': 'Loans',
        'side': 'liabilities',
        'total': _usd('25000'),
        'accountIds': ['loan-1', 'loan-closed'],
        'history': [_point('2026-10-01', '25000')],
      },
      {
        'id': 'credit-cards',
        'label': 'Credit cards',
        'side': 'liabilities',
        'total': _usd('5000'),
        'accountIds': ['card-1'],
        'history': [_point('2026-10-01', '4500'), _point('2026-10-02', '5000')],
      },
    ],
  },
};

final _defaultAccounts = <Json>[
  _account('checking-1', 'Everyday checking', 'depository', [
    _balance('current', '12345', '2026-10-01T12:00:00.000Z'),
    _balance('current', null, '2026-10-03T12:00:00.000Z'),
  ]),
  _account('savings-1', 'Rainy day savings', 'depository', [
    _balance('current', '60000', '2026-10-02T12:00:00.000Z', currency: 'EUR'),
  ]),
  _account('invest-1', 'Brokerage', 'investment', [
    _balance('current', '50000', '2026-10-02T12:00:00.000Z'),
    _balance('investment-value', '90000', '2026-10-01T12:00:00.000Z'),
    _balance('investment-value', '97500', '2026-10-03T12:00:00.000Z'),
  ]),
  _account('invest-unknown', 'Unknown brokerage', 'investment', [
    _balance('investment-value', null, '2026-10-03T12:00:00.000Z'),
    _balance('current', '50000', '2026-10-02T12:00:00.000Z'),
  ]),
  _account(
    'invest-wire',
    'Wire brokerage',
    'investment',
    [_balance('current', '50000', '2026-10-03T12:00:00.000Z')],
    unknownBalanceTypes: ['investment-value'],
  ),
  _account('loan-1', 'Garden Loan', 'loan', [
    _balance('current', '-250000', '2026-10-02T12:00:00.000Z'),
  ]),
  _account('loan-closed', 'Closed loan', 'loan', [
    _balance('current', '-1000', '2026-10-02T12:00:00.000Z'),
  ], closed: true),
  _account('card-1', 'Garden Card', 'credit-card', [
    _balance('current', '-5000', '2026-10-02T12:00:00.000Z'),
  ]),
];
