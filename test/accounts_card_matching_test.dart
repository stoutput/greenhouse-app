import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/accounts.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'existing linked cards show inline matches without an initial prompt',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = _AccountsClient();
      addTearDown(client.dispose);
      await _pumpAccounts(tester, client);

      expect(find.text('New card account found'), findsNothing);
      expect(
        find.text('Imported account name: Garden Travel Visa'),
        findsOneWidget,
      );
      expect(find.text('Suggested match: Garden Travel Visa'), findsOneWidget);
      expect(find.text('Confirm card'), findsOneWidget);

      await tester.tap(find.text('Checking'));
      await tester.pumpAndSettle();
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Suggested match: Garden Travel Visa'), findsOneWidget);
    },
  );

  testWidgets('new account discovery prompts once and confirms the match', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _AccountsClient();
    addTearDown(client.dispose);
    await _pumpAccounts(tester, client);
    expect(find.text('New card account found'), findsNothing);

    client.secondAccountAdded = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('New card account found'), findsOneWidget);
    expect(find.text('Imported Garden Grocery Card'), findsWidgets);
    expect(find.text('Suggested match: Garden Grocery Card'), findsWidgets);

    await tester.tap(find.text('Confirm match'));
    await tester.pumpAndSettle();
    expect(client.requests, contains('PUT /cards/wallet/wallet-2'));
    expect(
      client.bodies[client.requests.lastIndexOf(
        'PUT /cards/wallet/wallet-2',
      )]!['productId'],
      'garden-grocery',
    );
    expect(find.text('New card account found'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('New card account found'), findsNothing);
  });

  testWidgets('read-only members see the suggestion but cannot confirm it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _AccountsClient(role: HouseholdRole.gardener);
    addTearDown(client.dispose);
    await _pumpAccounts(tester, client);
    client.secondAccountAdded = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('New card account found'), findsOneWidget);
    expect(
      find.text('An owner or admin can confirm this match.'),
      findsWidgets,
    );
    expect(find.text('Confirm match'), findsNothing);
    expect(client.requests.where((call) => call.startsWith('PUT ')), isEmpty);
  });

  testWidgets('Accounts remains usable when the server has no Cards API', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _AccountsClient(cardsUnavailable: true);
    addTearDown(client.dispose);
    await _pumpAccounts(tester, client);

    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Your accounts'), findsOneWidget);
    expect(find.text('New card account found'), findsNothing);
  });
}

Future<void> _pumpAccounts(WidgetTester tester, _AccountsClient client) async {
  tester.view.physicalSize = const Size(392, 820);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Accounts(client: client)),
    ),
  );
  await tester.pumpAndSettle();
}

class _AccountsClient extends GreenhouseClient {
  _AccountsClient({
    this.role = HouseholdRole.owner,
    this.cardsUnavailable = false,
  });

  final HouseholdRole role;
  final bool cardsUnavailable;
  bool secondAccountAdded = false;
  final confirmedProducts = <String, String>{};
  final requests = <String>[];
  final bodies = <Json?>[];
  final products = <Json>[
    {
      'id': 'garden-travel',
      'name': 'Garden Travel Visa',
      'issuer': 'Green Bank',
      'network': 'Visa',
      'rewards': [],
      'benefits': [],
    },
    {
      'id': 'garden-grocery',
      'name': 'Garden Grocery Card',
      'issuer': 'Green Bank',
      'network': 'Visa',
      'rewards': [],
      'benefits': [],
    },
  ];

  @override
  Uri? get origin => Uri.parse('https://accounts.example');

  @override
  HouseholdIdentity? get identity => HouseholdIdentity.fromJson({
    'id': 'member-accounts',
    'email': 'member@example.test',
    'householdId': 'home-accounts',
    'role': role.name,
  });

  @override
  HouseholdPermissions get permissions => HouseholdPermissions(role);

  Json _linkedCard(
    String id,
    String accountId,
    String name,
    String suggestion,
  ) => {
    'id': id,
    'kind': 'linked',
    'accountId': accountId,
    'displayName': name,
    'importedName': name,
    'mask': '1234',
    'productId': null,
    'openedOn': null,
    'benefitOverride': null,
    'suggestedProductId': suggestion,
    'candidateProductIds': <String>[],
  };

  Json _account(String id, String name) => {
    'account': {
      'id': id,
      'displayName': name,
      'kind': 'credit',
      'mask': '1234',
    },
    'connectionName': 'Garden Bank',
    'balances': [],
  };

  List<Json> get _accounts => [
    _account('account-1', 'Checking'),
    if (secondAccountAdded)
      _account('account-2', 'Imported Garden Grocery Card'),
  ];

  Json _walletCard(
    String id,
    String accountId,
    String name,
    String suggestion,
  ) {
    final confirmedProduct = confirmedProducts[id];
    return {
      ..._linkedCard(id, accountId, name, suggestion),
      'productId': confirmedProduct,
      'suggestedProductId': confirmedProduct == null ? suggestion : null,
    };
  }

  List<Json> get _wallet => [
    _walletCard('wallet-1', 'account-1', 'Garden Travel Visa', 'garden-travel'),
    if (secondAccountAdded)
      _walletCard(
        'wallet-2',
        'account-2',
        'Imported Garden Grocery Card',
        'garden-grocery',
      ),
  ];

  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    requests.add('$method $path');
    bodies.add(body);
    if (path == '/accounts') return {'items': _accounts};
    if (path == '/connections') return {'items': []};
    if (path == '/cards') {
      if (cardsUnavailable) {
        throw const GreenhouseException('Route not found', statusCode: 404);
      }
      return {
        'enabled': true,
        'navigationPage': {'id': 'cards', 'title': 'Cards'},
        'categories': [
          {
            'id': 'all-purchases',
            'label': 'All purchases',
            'isUniversal': true,
          },
          {'id': 'travel', 'label': 'Travel'},
          {'id': 'groceries', 'label': 'Groceries'},
        ],
        'products': products,
        'wallet': _wallet,
      };
    }
    if (path == '/accounts/account-1') {
      return {
        'account': {
          'id': 'account-1',
          'displayName': 'Checking',
          'kind': 'credit',
        },
        'connectionName': 'Garden Bank',
        'balances': [],
      };
    }
    if (path == '/accounts/account-2') {
      return {
        'account': {
          'id': 'account-2',
          'displayName': 'Imported Garden Grocery Card',
          'kind': 'credit',
        },
        'connectionName': 'Garden Bank',
        'balances': [],
      };
    }
    if (method == 'PUT' && path == '/cards/wallet/wallet-2') {
      confirmedProducts['wallet-2'] = body?['productId'] as String;
      return {
        'card': {
          ..._wallet.last,
          'productId': body?['productId'],
          'suggestedProductId': null,
        },
      };
    }
    return {};
  }
}
