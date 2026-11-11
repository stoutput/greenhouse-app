import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/accounts.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/transactions.dart';

void main() {
  testWidgets('gardener can read accounts and transaction details only', (
    tester,
  ) async {
    final client = _GardenerClient();
    addTearDown(client.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Accounts(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Checking'), findsOneWidget);
    await tester.tap(find.text('Checking'));
    await tester.pumpAndSettle();
    expect(find.text('Reported balances'), findsOneWidget);
    expect(find.text('Rename account'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => openTransaction(context, client, {
                  'transaction': {
                    'id': 'txn-1',
                    'amount': {'amount': '-1000', 'currency': 'USD'},
                    'description': 'Garden supplies',
                    'postedDate': '2026-11-01',
                  },
                  'annotation': {
                    'notes': 'Shared note',
                    'isExcluded': true,
                    'reviewState': 'reviewed',
                  },
                  'categoryName': 'Household',
                  'account': {'displayName': 'Checking'},
                }),
                child: const Text('Open transaction'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open transaction'));
    await tester.pumpAndSettle();
    expect(
      find.text('Transaction details are read-only for your household role.'),
      findsOneWidget,
    );
    expect(find.text('Category: Household'), findsOneWidget);
    expect(find.text('Notes: Shared note'), findsOneWidget);
    expect(find.text('Excluded from spending: Yes'), findsOneWidget);
    expect(find.text('Review status: Reviewed'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('Category'), findsNothing);
    expect(client.requests.where((path) => path == '/categories'), isEmpty);
  });
}

class _GardenerClient extends GreenhouseClient {
  final requests = <String>[];
  final _identity = HouseholdIdentity.fromJson({
    'id': 'member-gardener',
    'email': 'gardener@example.test',
    'displayName': 'Garden Member',
    'householdId': 'household-1',
    'role': 'gardener',
  })!;

  @override
  Uri? get origin => Uri.parse('https://garden.example');

  @override
  HouseholdIdentity? get identity => _identity;

  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    requests.add(path);
    if (path == '/accounts') {
      return {
        'items': [
          {
            'account': {
              'id': 'account-1',
              'displayName': 'Checking',
              'kind': 'deposit',
              'revision': 1,
            },
            'balances': [],
          },
        ],
      };
    }
    if (path == '/connections') return {'items': []};
    if (path == '/accounts/account-1') {
      return {
        'account': {
          'id': 'account-1',
          'displayName': 'Checking',
          'kind': 'deposit',
        },
        'balances': [],
        'connectionName': 'Manual account',
      };
    }
    return {};
  }
}
