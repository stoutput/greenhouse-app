import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/companion_navigation.dart';
import 'package:greenhouse/finance_widgets.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/plugin_pages.dart';

Json _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

PluginPageEntry _entry(String pageId, {String revision = ''}) =>
    PluginPageEntry(
      installationId: 'install-1',
      pageId: pageId,
      revision: revision,
      title: pageId,
      path: pluginPagePath('install-1', pageId),
      icon: 'extension',
      version: 2,
      availability: 'available',
      requiredCapabilities: const [],
      legacyPaths: const [],
    );

class _CanonicalTransport implements PluginPageTransport {
  _CanonicalTransport({
    required this.spec,
    required this.resources,
    this.validationError,
  });

  final Json spec;
  final Map<String, PluginResourceState> resources;
  final Json? validationError;
  Completer<PluginQueryResult>? pendingRecommendations;
  Completer<PluginQueryResult>? pendingEntriesRefresh;
  Completer<PluginMutationResult>? pendingMutation;
  final categoryItems = <Json>[
    {"id": "groceries", "title": "Groceries"},
    {"id": "travel", "title": "Travel"},
    for (var index = 0; index < 120; index++)
      {"id": "category-$index", "title": "Category $index"},
  ];
  final queries = <(String, Json)>[];
  final actions = <(String, Json, String?)>[];
  final entries = <Json>[
    {'id': 'one', 'title': 'Original'},
  ];
  final products = <Json>[
    for (var index = 0; index < 120; index++)
      {'id': 'product-$index', 'title': 'Product $index'},
  ];

  @override
  Future<PluginPageDocument> loadPage() async => PluginPageDocument(
    installationId: 'install-1',
    pageId: 'page',
    title: 'Page',
    ui: spec,
    resources: resources,
    readOnly: false,
  );

  @override
  Future<PluginQueryResult> runQuery(String queryId, Json input) async {
    queries.add((queryId, input));
    switch (queryId) {
      case 'entries':
        if (pendingEntriesRefresh != null) {
          return pendingEntriesRefresh!.future;
        }
        return PluginQueryResult(
          data: {'items': entries, 'total': entries.length, 'hasMore': false},
          revision: '2',
        );
      case 'products':
        final offset = input['offset'] is int ? input['offset'] as int : 0;
        final search = label(input['search'], '').toLowerCase();
        final matches = products
            .where(
              (item) => label(item['title']).toLowerCase().contains(search),
            )
            .toList();
        return PluginQueryResult(
          data: {
            'items': matches.skip(offset).take(100).toList(),
            'total': matches.length,
            'hasMore': offset + 100 < matches.length,
          },
          revision: 'p$offset',
        );
      case 'categories':
        final offset = input['offset'] is int ? input['offset'] as int : 0;
        final search = label(input['search'], '').toLowerCase();
        final matches = categoryItems
            .where(
              (item) => label(item['title']).toLowerCase().contains(search),
            )
            .toList();
        return PluginQueryResult(
          data: {
            'items': matches.skip(offset).take(100).toList(),
            'total': matches.length,
            'hasMore': offset + 100 < matches.length,
          },
          revision: 'c$offset',
        );
      case 'recommendations':
        if (pendingRecommendations != null) {
          return pendingRecommendations!.future;
        }
        return const PluginQueryResult(
          data: {
            'items': [
              {
                'id': 'rec-1',
                'title': 'Recommended card',
                'fallbackLabel': 'Issuer',
                'caption': 'Network •••• 1234',
                'tone': 'forest',
                'highlights': [
                  {'label': 'Selected purchase reward', 'value': '3%'},
                  {'label': 'Annual credit', 'value': 'Travel credit'},
                ],
              },
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: 'r2',
        );
      default:
        return const PluginQueryResult(data: null, revision: '0');
    }
  }

  @override
  Future<PluginMutationResult> runAction(
    String actionId,
    Json input, {
    String? revision,
  }) async {
    actions.add((actionId, input, revision));
    if (pendingMutation != null) {
      final result = await pendingMutation!.future;
      pendingMutation = null;
      return result;
    }
    if (validationError != null) {
      throw GreenhouseException(
        'The request was not valid',
        statusCode: 400,
        details: validationError,
      );
    }
    if (actionId == 'save') {
      entries
        ..clear()
        ..add({'id': input['id'], 'title': input['title']});
      resources['entries'] = PluginResourceState(
        data: {'items': entries, 'total': entries.length, 'hasMore': false},
        revision: '3',
      );
    }
    if (actionId == 'benefits') {
      final selected = input['id'];
      final items = pluginItems(resources['wallet']?.data);
      final index = items.indexWhere((item) => item['id'] == selected);
      if (index >= 0) {
        items[index] = {
          ...items[index],
          'rewards': input['rewards'],
          'benefits': input['benefits'],
        };
        resources['wallet'] = PluginResourceState(
          data: {'items': items, 'total': items.length, 'hasMore': false},
          revision: 'w3',
        );
      }
    }
    return PluginMutationResult(
      data: const {},
      revision: '2',
      invalidatedResources: const ['entries'],
    );
  }
}

class _UiClient extends GreenhouseClient {
  _UiClient(this.transport);
  final _CanonicalTransport transport;
  int loads = 0;
  final requests = <Map<String, String>?>[];
  Uri currentOrigin = Uri.parse('https://one.example');
  @override
  Uri get origin => currentOrigin;
  @override
  HouseholdIdentity get identity => HouseholdIdentity.fromJson({
    'id': 'member',
    'email': 'member@example.test',
    'householdId': 'household',
    'role': 'owner',
  })!;
  @override
  HouseholdPermissions get permissions => identity.permissions;
  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    requests.add(query);
    if (path.contains('/queries/')) {
      final result = await transport.runQuery(
        path.split('/').last,
        object(body?['input']),
      );
      return {'data': result.data, 'revision': result.revision};
    }
    if (path.contains('/actions/')) {
      final result = await transport.runAction(
        path.split('/').last,
        object(body?['input']),
        revision: body?['revision'] as String?,
      );
      return {
        'data': result.data,
        'revision': result.revision,
        'invalidatedResources': result.invalidatedResources,
      };
    }
    loads++;
    return {
      'installationId': 'install-1',
      'pageId': 'page',
      'title': 'Page',
      'ui': transport.spec,
      'readOnly': false,
      'resources': {
        for (final entry in transport.resources.entries)
          entry.key: {
            'data': entry.value.data,
            'revision': entry.value.revision,
          },
      },
    };
  }
}

Widget _clientBody(_UiClient client, {String revision = ''}) => MaterialApp(
  home: Scaffold(
    body: PluginPageScreen(
      client: client,
      entry: _entry('page', revision: revision),
      allowedDestinations: CompanionPage.destinationsFor(const []),
      onNavigate: (_) {},
      isCurrent: () => true,
    ),
  ),
);

Widget _body(
  _CanonicalTransport transport, {
  bool privacyMasked = false,
  bool readOnly = false,
  bool allowAdminActions = true,
  bool includePage = true,
  bool reducedMotion = false,
  bool Function()? isCurrent,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
    child: child!,
  ),
  home: Scaffold(
    body: !includePage
        ? const Text("Core page")
        : PluginPageBody(
            transport: transport,
            entry: _entry('page'),
            allowedDestinations: CompanionPage.destinationsFor(const []),
            onNavigate: (_) {},
            privacyMasked: privacyMasked,
            roleReadOnly: readOnly,
            allowAdminActions: allowAdminActions,
            isCurrent: isCurrent ?? () => true,
          ),
  ),
);

Finder _sheet(Finder matcher) => find.descendant(
  of: find.byKey(const ValueKey('plugin-detail-list')),
  matching: matcher,
);

Finder get _sheetScroll => _sheet(find.byType(Scrollable)).first;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .4);
  await tester.pumpAndSettle();
}

_CanonicalTransport _cardsTransport() => _CanonicalTransport(
  spec: _fixture('cards-page-spec.json'),
  resources: {
    'wallet': const PluginResourceState(
      data: {
        'items': [
          {
            'id': 'card-1',
            'title': 'Private card',
            'caption': 'Network •••• 1234',
            'fallbackLabel': 'Issuer',
            'tone': 'forest',
            'badges': [
              {'label': 'Override', 'tone': 'gold'},
            ],
            'identificationNotice': 'Saved identification',
            'editProductId': null,
          },
        ],
        'total': 1,
        'hasMore': false,
      },
      revision: 'w1',
    ),
  },
);

_CanonicalTransport _preservationTransport({
  String productId = 'old-product',
  String editProductId = 'suggested-product',
  bool customized = true,
}) => _CanonicalTransport(
  spec: _fixture('cards-page-spec.json'),
  resources: {
    'wallet': PluginResourceState(
      data: {
        'items': [
          {
            'id': 'one',
            'title': 'Editable card',
            'productId': productId,
            'editProductId': editProductId,
            'customized': customized,
            'openedOn': '2024-01-01',
            'removable': true,
            'rewards': [
              {
                'categoryId': 'groceries',
                'rate': 3,
                'unit': 'percent',
                'cap': null,
                'conditions': null,
                'additionalCategoryIds': ['whole-foods'],
                'validFrom': '2026-01-01',
                'validThrough': '2026-12-31',
              },
            ],
            'benefits': [],
          },
        ],
        'total': 1,
        'hasMore': false,
      },
      revision: 'w1',
    ),
    'categories': const PluginResourceState(
      data: {
        'items': [
          {'id': 'groceries', 'title': 'Groceries'},
          {'id': 'travel', 'title': 'Travel'},
        ],
        'total': 2,
        'hasMore': false,
      },
      revision: 'c1',
    ),
  },
);

Future<void> _openWalletEditor(
  WidgetTester tester,
  _CanonicalTransport transport,
) async {
  await tester.pumpWidget(_body(transport));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Editable card'));
  await tester.pumpAndSettle();
  await _reveal(tester, find.text('Details'));
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();
}

Future<void> _openPurchaseChoices(WidgetTester tester) async {
  final picker = find.byKey(const ValueKey('picker-purchase-picker'));
  await _reveal(tester, picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('resource-picker-search')), findsOneWidget);
}

Future<void> _openCard(
  WidgetTester tester,
  _CanonicalTransport transport,
) async {
  await tester.pumpWidget(_body(transport));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Private card'));
  await tester.pumpAndSettle();
  await _reveal(tester, find.text('Details'));
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();
  expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  expect(_sheet(find.text('Network •••• 1234')), findsOneWidget);
  expect(_sheet(find.text('Override')), findsOneWidget);
  expect(_sheet(find.text('Issuer')), findsOneWidget);
}

void main() {
  testWidgets('one plugin mutation blocks other writes through refresh', (
    tester,
  ) async {
    final spec = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(_fixture('example-page-spec.json')))
          as Map<String, dynamic>,
    );
    (spec['actions'] as List).add({'id': 'second', 'access': 'member'});
    (spec['components'] as List).add({
      'id': 'second-button',
      'type': 'button',
      'label': 'Second action',
      'action': 'second',
    });
    (spec['roots'] as List).add('second-button');
    final transport = _CanonicalTransport(
      spec: spec,
      resources: {
        'entries': const PluginResourceState(
          data: {
            'items': [
              {'id': 'one', 'title': 'Original'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: '1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    transport.pendingMutation = Completer<PluginMutationResult>();
    transport.pendingEntriesRefresh = Completer<PluginQueryResult>();

    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('field-editor-title')),
      'Updated',
    );
    await tester.tap(find.byKey(const ValueKey('save-editor')));
    await tester.pump();
    expect(transport.actions.map((action) => action.$1), ['save']);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Second action'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('field-editor-title')),
          )
          .enabled,
      isFalse,
    );

    transport.pendingMutation!.complete(
      const PluginMutationResult(
        data: {},
        revision: '2',
        invalidatedResources: ['entries'],
      ),
    );
    await tester.pump();
    expect(transport.queries.where((query) => query.$1 == 'entries').length, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Second action'),
          )
          .onPressed,
      isNull,
    );

    transport.pendingEntriesRefresh!.complete(
      const PluginQueryResult(
        data: {
          'items': [
            {'id': 'one', 'title': 'Updated'},
          ],
          'total': 1,
          'hasMore': false,
        },
        revision: '3',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Second action'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Second action'));
    await tester.pumpAndSettle();
    expect(transport.actions.map((action) => action.$1), ['save', 'second']);
  });

  testWidgets('canonical example selects, edits and saves with revision', (
    tester,
  ) async {
    final transport = _CanonicalTransport(
      spec: _fixture('example-page-spec.json'),
      resources: {
        'entries': const PluginResourceState(
          data: {
            'items': [
              {'id': 'one', 'title': 'Original'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: '1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField).first;
    expect(tester.widget<TextFormField>(field).controller?.text, 'Original');
    await tester.enterText(field, 'Updated');
    await _reveal(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(transport.actions.single.$1, 'save');
    expect(transport.actions.single.$2, {'id': 'one', 'title': 'Updated'});
    expect(transport.actions.single.$3, '1');
    expect(find.text('Updated'), findsWidgets);
  });

  testWidgets('canonical example validation keeps the draft', (tester) async {
    final transport = _CanonicalTransport(
      spec: _fixture('example-page-spec.json'),
      resources: {
        'entries': const PluginResourceState(
          data: {
            'items': [
              {'id': 'one', 'title': 'Original'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: '1',
        ),
      },
      validationError: {
        'fieldErrors': {'title': 'Use a longer title'},
      },
    );
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Draft');
    await _reveal(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Use a longer title'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller
          ?.text,
      'Draft',
    );
  });

  testWidgets('canonical Cards renders every wallet row without a cap', (
    tester,
  ) async {
    final walletItems = [
      for (var index = 1; index <= 6; index++)
        {
          'id': 'card-$index',
          'title': 'Card $index',
          'subtitle': 'Subtitle $index',
          'destination': '/transactions?accountId=account-$index',
          'facts': [
            {'label': 'Annual fee', 'value': '\$$index'},
          ],
          'removable': true,
          'rewards': [
            {
              'categoryId': 'groceries',
              'additionalCategoryIds': ['whole-foods'],
              'validFrom': '2026-01-01',
              'validThrough': '2026-12-31',
              'rate': 3,
              'unit': 'percent',
              'cap': null,
              'conditions': null,
            },
          ],
          'benefits': [
            {
              'title': 'Travel credit',
              'description': 'Annual travel credit',
              'categoryId': null,
            },
          ],
        },
    ];
    final transport = _CanonicalTransport(
      spec: _fixture('cards-page-spec.json'),
      resources: {
        'wallet': PluginResourceState(
          data: {
            'items': walletItems,
            'total': walletItems.length,
            'hasMore': false,
          },
          revision: 'w1',
        ),
        'categories': const PluginResourceState(
          data: {
            'items': [
              {'id': 'groceries', 'title': 'Groceries'},
              {'id': 'travel', 'title': 'Travel'},
            ],
            'total': 2,
            'hasMore': false,
          },
          revision: 'c1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    expect(find.text('Card 1'), findsWidgets);
    expect(find.text('Card 6'), findsOneWidget);
    expect(find.text('1 of 6'), findsOneWidget);
    expect(find.text('6 of 6'), findsOneWidget);

    await _reveal(tester, find.text('Card 6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card 6').first);
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Card details'),
      160,
      scrollable: _sheetScroll,
    );
    expect(find.text('Card details'), findsOneWidget);
    await tester.scrollUntilVisible(
      _sheet(find.text('Rewards 1')),
      180,
      scrollable: _sheetScroll,
    );
    expect(_sheet(find.text('Rewards 1')), findsOneWidget);
    await tester.scrollUntilVisible(
      _sheet(find.text('Travel credit')),
      180,
      scrollable: _sheetScroll,
    );
    expect(_sheet(find.text('Travel credit')), findsOneWidget);
    expect(find.text('AdditionalCategoryIds'), findsNothing);
  });

  testWidgets(
    'canonical purchase picker searches, recommends and closes with a clean reset',
    (tester) async {
      final transport = _cardsTransport();
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      expect(find.text('What are you purchasing today?'), findsOneWidget);
      await _reveal(tester, find.text('Private card'));
      await tester.tap(find.text('Private card'));
      await tester.pumpAndSettle();
      expect(find.text('Private card'), findsNWidgets(2));
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Card name'), findsNothing);
      await _openPurchaseChoices(tester);
      final search = find.byKey(const ValueKey('resource-picker-search'));
      await tester.enterText(search, 'gro');
      await tester.pumpAndSettle();
      expect(transport.queries.last.$1, 'categories');
      expect(transport.queries.last.$2['search'], 'gro');
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Travel'), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller?.text, '');
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isFalse);
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(transport.queries.last.$1, 'recommendations');
      expect(transport.queries.last.$2['categoryId'], 'groceries');
      expect(find.text('Use this card for the best benefits!'), findsOneWidget);
      expect(find.text('Recommended card'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('3%'),
        140,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey('dialog-content-recommendation-dialog'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('3%'), findsOneWidget);
      expect(find.text('Travel credit'), findsOneWidget);
      expect(find.byKey(const ValueKey('close-plugin-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close-plugin-sheet')));
      await tester.pumpAndSettle();
      expect(find.text('Recommended card'), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text('Private card'), findsNWidgets(2));
      await _openPurchaseChoices(tester);
      expect(tester.widget<TextField>(search).controller?.text, '');
      await tester.tap(find.byTooltip('Close choices'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('resource-picker-search')),
        findsNothing,
      );
      expect(find.text('Recommended card'), findsNothing);
    },
  );

  testWidgets(
    'outside dismissal resets the recommendation without changing wallet selection',
    (tester) async {
      final transport = _cardsTransport();
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      await _openPurchaseChoices(tester);
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.text('Recommended card'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text('Recommended card'), findsNothing);
      await tester.pump();
      expect(find.text('Recommended card'), findsNothing);
    },
  );

  testWidgets('manual entry stays inside an initially closed disclosure', (
    tester,
  ) async {
    final transport = _cardsTransport();
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    expect(find.text('Card name'), findsNothing);
    final disclosure = find.byKey(const ValueKey('disclosure-add-disclosure'));
    await _reveal(tester, disclosure);
    await tester.tap(
      find
          .descendant(of: disclosure, matching: find.text('Add manual card'))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Card name'), findsOneWidget);
    await tester.tap(
      find
          .descendant(of: disclosure, matching: find.text('Add manual card'))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Card name'), findsNothing);
  });

  testWidgets(
    'purchase choices paginate beyond 100 without permanent category rows',
    (tester) async {
      final transport = _cardsTransport();
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      await _openPurchaseChoices(tester);
      final optionsScroll = find
          .descendant(
            of: find.byKey(const ValueKey('plugin-options-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Load more'),
        250,
        scrollable: optionsScroll,
      );
      await _reveal(tester, find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(transport.queries.last.$2['offset'], 100);
      await tester.scrollUntilVisible(
        find.text('Category 119'),
        180,
        scrollable: optionsScroll,
      );
      await _reveal(tester, find.text('Category 119'));
      await tester.tap(find.text('Category 119'));
      await tester.pumpAndSettle();
      expect(transport.queries.last.$2['categoryId'], 'category-119');
      expect(find.text('Recommended card'), findsOneWidget);
    },
  );

  for (final stop in ['dismiss', 'privacy', 'disable']) {
    testWidgets('late recommendations cannot reopen after $stop', (
      tester,
    ) async {
      final transport = _cardsTransport();
      final pending = Completer<PluginQueryResult>();
      transport.pendingRecommendations = pending;
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      await _openPurchaseChoices(tester);
      await tester.tap(find.text('Groceries'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      if (stop == 'dismiss') {
        await tester.tap(find.byKey(const ValueKey('close-plugin-sheet')));
        await tester.pump(const Duration(milliseconds: 350));
      } else {
        await tester.pumpWidget(
          _body(
            transport,
            privacyMasked: stop == 'privacy',
            isCurrent: () => stop != 'disable',
          ),
        );
        await tester.pump();
      }
      pending.complete(
        const PluginQueryResult(
          data: {
            'items': [
              {'id': 'late', 'title': 'Late private recommendation'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: 'late',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text('Late private recommendation'), findsNothing);
      expect(transport.actions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('repeater submit preserves unrendered reward metadata', (
    tester,
  ) async {
    final wallet = {
      'id': 'card-1',
      'title': 'Card 1',
      'rewards': [
        {
          'categoryId': 'groceries',
          'additionalCategoryIds': ['whole-foods'],
          'validFrom': '2026-01-01',
          'validThrough': '2026-12-31',
          'rate': 3,
          'unit': 'percent',
          'cap': null,
          'conditions': null,
        },
      ],
      'benefits': [
        {
          'title': 'Travel credit',
          'description': 'Annual travel credit',
          'categoryId': null,
        },
      ],
    };
    final transport = _CanonicalTransport(
      spec: _fixture('cards-page-spec.json'),
      resources: {
        'wallet': PluginResourceState(
          data: {
            'items': [wallet],
            'total': 1,
            'hasMore': false,
          },
          revision: 'w1',
        ),
        'categories': const PluginResourceState(
          data: {
            'items': [
              {'id': 'groceries', 'title': 'Groceries'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: 'c1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card 1').first);
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Rewards and benefits override'),
      180,
      scrollable: _sheetScroll,
    );
    await _reveal(tester, find.text('Rewards and benefits override'));
    final rate = find.byKey(const ValueKey('field-benefits-rewards.0.rate'));
    await tester.enterText(rate, '5');
    final save = find.byKey(const ValueKey('save-benefits'));
    await _reveal(tester, save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final call = transport.actions.lastWhere((entry) => entry.$1 == 'benefits');
    final rewards = (call.$2['rewards'] as List).cast<Map>();
    expect(rewards.single['rate'], 5);
    expect(rewards.single['additionalCategoryIds'], ['whole-foods']);
    expect(rewards.single['validFrom'], '2026-01-01');
    expect(rewards.single['validThrough'], '2026-12-31');
    expect(call.$3, 'w1');
    await _reveal(tester, find.text('Add Rewards'));
    await tester.tap(find.text('Add Rewards'));
    await tester.pumpAndSettle();
    expect(find.text('Rewards 2'), findsOneWidget);
  });

  testWidgets(
    'removing first repeater rows preserves remaining displayed draft and metadata',
    (tester) async {
      final transport = _CanonicalTransport(
        spec: _fixture('cards-page-spec.json'),
        resources: {
          'wallet': const PluginResourceState(
            data: {
              'items': [
                {
                  'id': 'card-1',
                  'title': 'Two-row card',
                  'rewards': [
                    {
                      'categoryId': 'groceries',
                      'rate': 2,
                      'unit': 'percent',
                      'cap': 'First cap',
                      'conditions': 'First condition',
                      'additionalCategoryIds': ['first-extra'],
                      'validFrom': '2025-01-01',
                      'validThrough': '2025-12-31',
                    },
                    {
                      'categoryId': 'travel',
                      'rate': 5,
                      'unit': 'x',
                      'cap': 'Second cap',
                      'conditions': 'Second condition',
                      'additionalCategoryIds': ['second-extra'],
                      'validFrom': '2026-01-01',
                      'validThrough': '2026-12-31',
                    },
                  ],
                  'benefits': [
                    {
                      'title': 'First credit',
                      'description': 'First description',
                      'categoryId': 'groceries',
                    },
                    {
                      'title': 'Second credit',
                      'description': 'Second description',
                      'categoryId': 'travel',
                    },
                  ],
                },
              ],
              'total': 1,
              'hasMore': false,
            },
            revision: 'w1',
          ),
          'categories': const PluginResourceState(
            data: {
              'items': [
                {'id': 'groceries', 'title': 'Groceries'},
                {'id': 'travel', 'title': 'Travel'},
              ],
              'total': 2,
              'hasMore': false,
            },
            revision: 'c1',
          ),
        },
      );
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two-row card'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rewards and benefits override'),
        180,
        scrollable: _sheetScroll,
      );
      Future<void> type(String path, String value) async {
        final field = find.byKey(ValueKey('field-benefits-$path'));
        await _reveal(tester, field);
        await tester.enterText(field, value);
      }

      await type('rewards.1.rate', '7.5');
      await type('rewards.1.cap', 'Typed cap');
      await type('rewards.1.conditions', 'Typed condition');
      await type('benefits.1.title', 'Typed credit');
      await type('benefits.1.description', 'Typed description');
      Future<void> remove(String title) async {
        final header = find
            .ancestor(of: find.text(title), matching: find.byType(Row))
            .first;
        final button = find.descendant(
          of: header,
          matching: find.byTooltip('Remove'),
        );
        await _reveal(tester, button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await remove('Rewards 1');
      String displayed(String path) => tester
          .widget<TextFormField>(find.byKey(ValueKey('field-benefits-$path')))
          .controller!
          .text;
      expect(displayed('rewards.0.rate'), '7.5');
      expect(displayed('rewards.0.cap'), 'Typed cap');
      expect(displayed('rewards.0.conditions'), 'Typed condition');
      expect(
        tester
            .state<FormFieldState<String>>(
              _sheet(find.byType(DropdownButtonFormField<String>)).first,
            )
            .value,
        'x',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('field-benefits-rewards.0.categoryId')),
          matching: find.text('Travel'),
        ),
        findsOneWidget,
      );
      await remove('Benefits 1');
      expect(displayed('benefits.0.title'), 'Typed credit');
      expect(displayed('benefits.0.description'), 'Typed description');
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('field-benefits-benefits.0.categoryId'),
          ),
          matching: find.text('Travel'),
        ),
        findsOneWidget,
      );
      final save = find.byKey(const ValueKey('save-benefits'));
      await _reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final input = transport.actions
          .lastWhere((call) => call.$1 == 'benefits')
          .$2;
      expect(input['rewards'], [
        {
          'categoryId': 'travel',
          'rate': 7.5,
          'unit': 'x',
          'cap': 'Typed cap',
          'conditions': 'Typed condition',
          'additionalCategoryIds': ['second-extra'],
          'validFrom': '2026-01-01',
          'validThrough': '2026-12-31',
        },
      ]);
      expect(input['benefits'], [
        {
          'title': 'Typed credit',
          'description': 'Typed description',
          'categoryId': 'travel',
        },
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final category in ['Travel', 'Groceries']) {
    testWidgets(
      'selecting $category clears aliases only when category actually changes',
      (tester) async {
        final transport = _preservationTransport();
        await _openWalletEditor(tester, transport);
        final rate = find.byKey(
          const ValueKey('field-benefits-rewards.0.rate'),
        );
        await tester.scrollUntilVisible(rate, 180, scrollable: _sheetScroll);
        await _reveal(tester, rate);
        await tester.enterText(rate, '5');
        final categoryField = find.byKey(
          const ValueKey('field-benefits-rewards.0.categoryId'),
        );
        await _reveal(tester, categoryField);
        await tester.tap(
          find.descendant(of: categoryField, matching: find.byType(TextButton)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(category).last);
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('save-benefits'));
        await _reveal(tester, save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        final reward =
            (transport.actions.single.$2['rewards'] as List).single as Map;
        expect(reward['categoryId'], category.toLowerCase());
        expect(reward['rate'], 5);
        if (category == 'Travel') {
          expect(reward.containsKey('additionalCategoryIds'), isFalse);
        } else {
          expect(reward['additionalCategoryIds'], ['whole-foods']);
        }
        expect(reward['validFrom'], '2026-01-01');
        expect(reward['validThrough'], '2026-12-31');
      },
    );
  }

  testWidgets(
    'prefilled replacement confirms before posting; cancel keeps draft and accept posts once',
    (tester) async {
      final transport = _preservationTransport();
      await _openWalletEditor(tester, transport);
      final opened = find.byKey(const ValueKey('field-identify-openedOn'));
      await tester.scrollUntilVisible(opened, 160, scrollable: _sheetScroll);
      await _reveal(tester, opened);
      await tester.enterText(opened, '2026-04-05');
      final save = find.byKey(const ValueKey('save-identify'));
      await _reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Changing the card product clears your custom rewards and benefits. Continue?',
        ),
        findsOneWidget,
      );
      expect(transport.actions, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(transport.actions, isEmpty);
      expect(
        tester.widget<TextFormField>(opened).controller?.text,
        '2026-04-05',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(transport.actions, hasLength(1));
      expect(transport.actions.single.$1, 'update');
      expect(transport.actions.single.$2, {
        'id': 'one',
        'productId': 'suggested-product',
        'openedOn': '2026-04-05',
      });
      expect(transport.actions.single.$3, 'w1');
    },
  );

  testWidgets('same-product date edit skips conditional confirmation', (
    tester,
  ) async {
    final transport = _preservationTransport(editProductId: 'old-product');
    await _openWalletEditor(tester, transport);
    final opened = find.byKey(const ValueKey('field-identify-openedOn'));
    await tester.scrollUntilVisible(opened, 160, scrollable: _sheetScroll);
    await _reveal(tester, opened);
    await tester.enterText(opened, '2026-04-05');
    final save = find.byKey(const ValueKey('save-identify'));
    await _reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(transport.actions.single.$2, {
      'id': 'one',
      'productId': 'old-product',
      'openedOn': '2026-04-05',
    });
  });

  testWidgets('privacy closes pending confirmation and prevents its post', (
    tester,
  ) async {
    final transport = _preservationTransport();
    await _openWalletEditor(tester, transport);
    final save = find.byKey(const ValueKey('save-identify'));
    await tester.scrollUntilVisible(save, 160, scrollable: _sheetScroll);
    await _reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    await tester.pumpWidget(_body(transport, privacyMasked: true));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(transport.actions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'static action confirmation still cancels and posts once on acceptance',
    (tester) async {
      final transport = _preservationTransport();
      await _openWalletEditor(tester, transport);
      final remove = find.text('Remove manual card');
      await tester.scrollUntilVisible(remove, 200, scrollable: _sheetScroll);
      await _reveal(tester, remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('Remove this manually tracked card?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(transport.actions, isEmpty);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(transport.actions.single.$1, 'delete');
      expect(transport.actions.single.$2, {'id': 'one'});
    },
  );

  testWidgets(
    'clearOnChange rebinds visible text and select siblings only after a changed value',
    (tester) async {
      final spec = _fixture('example-page-spec.json');
      final form = (spec['components'] as List).firstWhere(
        (item) => item['id'] == 'editor',
      ) as Map;
      final fields = form['fields'] as List;
      (fields.first as Map)['clearOnChange'] = ['secondary', 'mode'];
      fields.addAll([
        {
          'name': 'secondary',
          'label': 'Secondary',
          'type': 'text',
          'nullable': true,
          'value': 'Keep text',
        },
        {
          'name': 'mode',
          'label': 'Mode',
          'type': 'select',
          'nullable': true,
          'value': 'first',
          'options': [
            {'value': 'first', 'label': 'First'},
            {'value': 'second', 'label': 'Second'},
          ],
        },
      ]);
      final inputProperties =
          ((spec['actions'] as List).first['inputSchema'] as Map)['properties']
              as Map;
      inputProperties['secondary'] = {
        'anyOf': [
          {'type': 'string', 'maxLength': 200},
          {'type': 'null'},
        ],
      };
      inputProperties['mode'] = {
        'anyOf': [
          {'type': 'string', 'maxLength': 200},
          {'type': 'null'},
        ],
      };
      final transport = _CanonicalTransport(
        spec: spec,
        resources: {
          'entries': const PluginResourceState(
            data: {
              'items': [
                {'id': 'one', 'title': 'Original'},
              ],
              'total': 1,
              'hasMore': false,
            },
            revision: '1',
          ),
        },
      );
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      final title = find.byKey(const ValueKey('field-editor-title'));
      final secondary = find.byKey(const ValueKey('field-editor-secondary'));
      final mode = find.byType(DropdownButtonFormField<String>);
      await tester.enterText(title, 'Original');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(secondary).controller?.text,
        'Keep text',
      );
      expect(tester.state<FormFieldState<String>>(mode).value, 'first');
      await tester.enterText(title, 'Changed');
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(secondary).controller?.text, '');
      expect(tester.state<FormFieldState<String>>(mode).value, isNull);
      expect(transport.actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('resource-backed select loads beyond 100 options', (
    tester,
  ) async {
    final transport = _CanonicalTransport(
      spec: _fixture('cards-page-spec.json'),
      resources: {
        'wallet': const PluginResourceState(
          data: {
            'items': [
              {'id': 'card-1', 'title': 'Card 1'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: 'w1',
        ),
        'categories': const PluginResourceState(
          data: {
            'items': [
              {'id': 'groceries', 'title': 'Groceries'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: 'c1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card 1').first);
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await _reveal(tester, _sheet(find.text('None')).first);
    await tester.pumpAndSettle();
    await tester.tap(_sheet(find.text('None')).first);
    await tester.pumpAndSettle();
    expect(
      transport.queries.any(
        (query) =>
            query.$1 == 'products' &&
            query.$2['limit'] == 100 &&
            query.$2['offset'] == 0,
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Load more'),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('plugin-options-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _reveal(tester, find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(
      transport.queries.any(
        (query) => query.$1 == 'products' && query.$2['offset'] == 100,
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Product 100'),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('plugin-options-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Product 100'), findsOneWidget);
  });

  testWidgets('a stale page cannot submit an action after disablement', (
    tester,
  ) async {
    var current = true;
    final transport = _CanonicalTransport(
      spec: _fixture('example-page-spec.json'),
      resources: {
        'entries': const PluginResourceState(
          data: {
            'items': [
              {'id': 'one', 'title': 'Original'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: '1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport, isCurrent: () => current));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    current = false;
    await tester.enterText(find.byType(TextFormField).first, 'Stale');
    await _reveal(tester, find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(transport.actions, isEmpty);
  });

  testWidgets('privacy and role read-only mask and disable the page', (
    tester,
  ) async {
    final transport = _CanonicalTransport(
      spec: _fixture('example-page-spec.json'),
      resources: {
        'entries': const PluginResourceState(
          data: {
            'items': [
              {'id': 'one', 'title': 'Original'},
            ],
            'total': 1,
            'hasMore': false,
          },
          revision: '1',
        ),
      },
    );
    await tester.pumpWidget(_body(transport, privacyMasked: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('privacy mode'), findsOneWidget);
    expect(find.text('Original'), findsNothing);

    await tester.pumpWidget(_body(transport, readOnly: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'leaving a page closes its sheet and preserves unrelated routes',
    (tester) async {
      final transport = _cardsTransport();
      await _openCard(tester, transport);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        DialogRoute<void>(
          context: navigator.context,
          builder: (_) => const AlertDialog(title: Text('Unrelated dialog')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(_body(transport, includePage: false));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.text('Private card'), findsNothing);
      expect(find.text('Unrelated dialog'), findsOneWidget);
      expect(transport.actions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['privacy', 'role', 'identity']) {
    testWidgets('$change change clears the open sheet and old draft', (
      tester,
    ) async {
      final transport = _cardsTransport();
      await _openCard(tester, transport);
      await tester.pumpWidget(
        _body(
          change == 'identity' ? _cardsTransport() : transport,
          privacyMasked: change == 'privacy',
          readOnly: change == 'role',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byKey(const ValueKey('plugin-detail-list')), findsNothing);
      expect(transport.actions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a declared member action remains available without admin permission',
    (tester) async {
      final spec = _fixture('example-page-spec.json');
      (spec['actions'] as List).first['access'] = 'member';
      final transport = _CanonicalTransport(
        spec: spec,
        resources: {
          'entries': const PluginResourceState(
            data: {
              'items': [
                {'id': 'one', 'title': 'Original'},
              ],
              'total': 1,
              'hasMore': false,
            },
            revision: '1',
          ),
        },
      );
      await tester.pumpWidget(_body(transport, allowAdminActions: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Member edit');
      await _reveal(tester, find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(transport.actions.single.$2, {
        'id': 'one',
        'title': 'Member edit',
      });
    },
  );
  testWidgets(
    'equivalent discovery rebuild preserves sheet and draft; server change clears them',
    (tester) async {
      final client = _UiClient(_cardsTransport());
      addTearDown(client.dispose);
      await tester.pumpWidget(_clientBody(client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Private card'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      final opened = find.byKey(const ValueKey('field-identify-openedOn'));
      await tester.scrollUntilVisible(opened, 160, scrollable: _sheetScroll);
      await _reveal(tester, opened);
      await tester.enterText(opened, '2026-01-02');
      await tester.pumpWidget(_clientBody(client));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(
        tester.widget<TextFormField>(opened).controller?.text,
        '2026-01-02',
      );
      expect(client.loads, 1);
      await tester.pumpWidget(_clientBody(client, revision: 'new-spec-grants'));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(client.loads, 2);
      client.currentOrigin = Uri.parse('https://two.example');
      await tester.pumpWidget(_clientBody(client, revision: 'new-spec-grants'));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(client.loads, 3);
    },
  );

  test('all client page operations advertise mobile capabilities', () async {
    final client = _UiClient(_cardsTransport());
    addTearDown(client.dispose);
    final transport = ClientPluginPageTransport(
      client: client,
      entry: _entry('page'),
    );
    await transport.loadPage();
    await transport.runQuery('categories', {'search': 'gro'});
    await transport.runAction('create', {'name': 'Manual'}, revision: 'w1');
    expect(client.requests, hasLength(3));
    for (final query in client.requests) {
      expect(query?['surface'], 'mobile');
      expect(query?['versions'], pluginUiVersions);
      expect(query?['capabilities'], pluginComponentCapabilities.join(','));
    }
  });
  testWidgets(
    'three card headers remain reachable and reduced motion removes focus transforms',
    (tester) async {
      final transport = _CanonicalTransport(
        spec: _fixture('cards-page-spec.json'),
        resources: {
          'wallet': const PluginResourceState(
            data: {
              'items': [
                {'id': 'first', 'title': 'First card'},
                {'id': 'second', 'title': 'Second card'},
                {'id': 'last', 'title': 'Last card'},
              ],
              'total': 3,
              'hasMore': false,
            },
            revision: 'w1',
          ),
        },
      );
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsNothing);
      for (final title in ['First card', 'Second card', 'Last card']) {
        await _reveal(tester, find.text(title).first);
        await tester.tap(find.text(title).first);
        await tester.pumpAndSettle();
        expect(find.text(title), findsNWidgets(2));
        expect(find.byType(DraggableScrollableSheet), findsNothing);
      }
      final transforms = find.byWidgetPredicate(
        (widget) =>
            widget is Transform &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith(
              'card-transform-',
            ),
      );
      expect(
        tester
            .widgetList<Transform>(transforms)
            .any((widget) => widget.transform.getTranslation().y == -15),
        isTrue,
      );
      await tester.pumpWidget(_body(transport, reducedMotion: true));
      await tester.pumpAndSettle();
      for (final transform in tester.widgetList<Transform>(transforms)) {
        expect(transform.transform.getTranslation().y, 0);
        final scale = transform.child! as Transform;
        expect(scale.transform.getMaxScaleOnAxis(), 1);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an explicit form submit validates and includes its edited draft',
    (tester) async {
      final spec = _fixture('example-page-spec.json');
      final components = spec['components'] as List;
      (components.firstWhere((value) => value['id'] == 'editor')
          as Map)['children'] = [
        'submit',
      ];
      components.add({
        'id': 'submit',
        'type': 'button',
        'label': 'Apply edit',
        'action': 'save',
      });
      final transport = _CanonicalTransport(
        spec: spec,
        resources: {
          'entries': const PluginResourceState(
            data: {
              'items': [
                {'id': 'one', 'title': 'Original'},
              ],
              'total': 1,
              'hasMore': false,
            },
            revision: '1',
          ),
        },
      );
      await tester.pumpWidget(_body(transport));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Explicit edit');
      await _reveal(tester, find.text('Apply edit'));
      await tester.tap(find.text('Apply edit'));
      await tester.pumpAndSettle();
      expect(transport.actions.single.$2, {
        'id': 'one',
        'title': 'Explicit edit',
      });
      expect(transport.actions.single.$3, '1');
    },
  );

  test('page trees reject cycles, fallback cycles and excessive repeated expansion', () {
    expect(
      PluginPageSpec.fromJson({
        'version': 2,
        'roots': ['layout'],
        'components': [
          {
            'id': 'layout',
            'type': 'collection-detail',
            'children': ['list'],
            'emptyChildren': ['layout'],
          },
          {'id': 'list', 'type': 'collection', 'resource': 'entries'},
        ],
      }).hasValidTree,
      isFalse,
    );
    expect(
      PluginPageSpec.fromJson({
        'version': 2,
        'roots': ['a'],
        'components': [
          {
            'id': 'a',
            'type': 'section',
            'children': ['a'],
          },
        ],
      }).hasValidTree,
      isFalse,
    );
    expect(
      PluginPageSpec.fromJson({
        'version': 2,
        'roots': ['a'],
        'components': [
          {'id': 'a', 'type': 'section', 'children': List.filled(501, 'b')},
          {'id': 'b', 'type': 'text', 'text': 'Unreachable'},
        ],
      }).hasValidTree,
      isFalse,
    );
  });
}
