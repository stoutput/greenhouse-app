import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/cards.dart';
import 'package:greenhouse/greenhouse_client.dart';

void main() {
  test('annual fee unknown and no-fee products remain distinct', () {
    expect(annualFeeDisplay(null), 'Not verified');
    expect(annualFeeDisplay(0), 'No annual fee');
    expect(annualFeeDisplay(9500), r'$95.00');
  });

  test('product availability labels preserve non-active states', () {
    expect(
      productAvailabilityLabel({'status': 'discontinued'}),
      'Not available for new applicants',
    );
    expect(productAvailabilityLabel({'status': 'invite_only'}), 'Invite only');
    expect(productAvailabilityLabel({'status': 'active'}), isNull);
  });

  test('explicit additional categories apply without inferring siblings', () {
    const categories = [
      {'id': 'all-purchases', 'label': 'All purchases', 'isUniversal': true},
      {'id': 'groceries', 'label': 'Groceries'},
      {'id': 'whole-foods', 'label': 'Whole Foods Market'},
    ];
    const products = [
      {
        'id': 'amex',
        'name': 'Blue Cash',
        'rewards': [
          {
            'categoryId': 'groceries',
            'additionalCategoryIds': ['whole-foods'],
            'rate': 6,
            'unit': 'percent',
          },
        ],
      },
      {
        'id': 'prime',
        'name': 'Prime Visa',
        'rewards': [
          {'categoryId': 'whole-foods', 'rate': 5, 'unit': 'percent'},
        ],
      },
    ];
    const wallet = [
      {'id': 'amex-wallet', 'productId': 'amex'},
      {'id': 'prime-wallet', 'productId': 'prime'},
    ];

    expect(
      rankCardsForCategory(
        wallet: wallet,
        products: products,
        categoryId: 'whole-foods',
        categories: categories,
      ).map((row) => row.walletCard['id']),
      ['amex-wallet', 'prime-wallet'],
    );
    expect(
      rankCardsForCategory(
        wallet: wallet,
        products: products,
        categoryId: 'groceries',
        categories: categories,
      ).map((row) => row.walletCard['id']),
      ['amex-wallet'],
    );
  });

  test('category recommendations compare all-purchase and specific rates numerically', () {
    const categories = [
      {'id': 'groceries', 'label': 'Groceries'},
      {'id': 'all-purchases', 'label': 'All purchases', 'isUniversal': true},
    ];
    const products = [
      {
        'id': 'specific-high',
        'name': 'Specific high',
        'rewards': [
          {'categoryId': 'groceries', 'rate': 10, 'unit': 'percent'},
        ],
      },
      {
        'id': 'specific-low',
        'name': 'Specific low',
        'rewards': [
          {'categoryId': 'groceries', 'rate': 2, 'unit': 'percent'},
          {'categoryId': 'all-purchases', 'rate': 3, 'unit': 'x'},
        ],
      },
      {
        'id': 'universal',
        'name': 'Universal',
        'rewards': [
          {'categoryId': 'all-purchases', 'rate': 5, 'unit': 'percent'},
        ],
      },
      {'id': 'no-rewards', 'name': 'No rewards', 'rewards': []},
    ];
    const wallet = [
      {'id': 'a', 'productId': 'specific-low'},
      {'id': 'b', 'productId': 'specific-high'},
      {'id': 'c', 'productId': 'universal'},
      {'id': 'd', 'productId': 'no-rewards'},
      {'id': 'e', 'productId': null},
    ];

    final groceries = rankCardsForCategory(
      wallet: wallet,
      products: products,
      categoryId: 'groceries',
      categories: categories,
    );
    expect(groceries.map((item) => item.walletCard['id']), ['b', 'c', 'a']);
    expect(rewardRateLabel(groceries.first.reward!), '10%');
    expect(rewardRateLabel(groceries.last.reward!), '3x');

    final travel = rankCardsForCategory(
      wallet: wallet,
      products: products,
      categoryId: 'travel',
      categories: categories,
    );
    expect(travel.map((item) => item.walletCard['id']), ['c', 'a']);
  });

  test(
    'wallet overrides replace catalog rewards and can rank unknown products',
    () {
      const categories = [
        {'id': 'all-purchases', 'label': 'All purchases', 'isUniversal': true},
        {'id': 'groceries', 'label': 'Groceries'},
      ];
      const products = [
        {
          'id': 'catalog-card',
          'name': 'Catalog card',
          'rewards': [
            {'categoryId': 'groceries', 'rate': 2, 'unit': 'percent'},
          ],
          'benefits': [
            {
              'title': 'Catalog perk',
              'description': 'Default benefit',
              'categoryId': null,
            },
          ],
        },
      ];
      const wallet = [
        {
          'id': 'catalog-wallet',
          'productId': 'catalog-card',
          'benefitOverride': {
            'rewards': [
              {'categoryId': 'groceries', 'rate': 3, 'unit': 'x'},
            ],
            'benefits': [
              {
                'title': 'Custom perk',
                'description': 'My household term',
                'categoryId': null,
              },
            ],
          },
        },
        {
          'id': 'unknown-wallet',
          'displayName': 'Unlisted card',
          'productId': null,
          'benefitOverride': {
            'rewards': [
              {'categoryId': 'groceries', 'rate': 4, 'unit': 'percent'},
            ],
            'benefits': [],
          },
        },
      ];
      final ranked = rankCardsForCategory(
        wallet: wallet,
        products: products,
        categoryId: 'groceries',
        categories: categories,
      );
      expect(ranked.map((row) => row.walletCard['id']), [
        'unknown-wallet',
        'catalog-wallet',
      ]);
      expect(rewardRateLabel(ranked.last.reward!), '3x');
      expect(
        effectiveCardBenefits(wallet.first, products.first).single['title'],
        'Custom perk',
      );
    },
  );

  test('purchase categories come only from effective wallet rewards', () {
    const categories = [
      {'id': 'all-purchases', 'label': 'All purchases'},
      {'id': 'groceries', 'label': 'Groceries'},
      {'id': 'costco-gas', 'label': 'Gas at Costco'},
      {'id': 'override-only', 'label': 'Custom category'},
      {'id': 'manual-only', 'label': 'Manual card category'},
      {'id': 'unrelated', 'label': 'Entertainment'},
    ];
    const products = [
      {
        'id': 'owned',
        'name': 'Owned card',
        'rewards': [
          {'categoryId': 'groceries', 'rate': 2, 'unit': 'percent'},
        ],
      },
      {
        'id': 'unowned',
        'name': 'Unowned card',
        'rewards': [
          {'categoryId': 'unrelated', 'rate': 4, 'unit': 'percent'},
        ],
      },
    ];
    const wallet = [
      {
        'productId': 'owned',
        'benefitOverride': {
          'rewards': [
            {
              'categoryId': 'override-only',
              'additionalCategoryIds': ['costco-gas'],
              'rate': 5,
              'unit': 'percent',
            },
          ],
        },
      },
      {
        'productId': null,
        'benefitOverride': {
          'rewards': [
            {'categoryId': 'manual-only', 'rate': 3, 'unit': 'percent'},
          ],
        },
      },
    ];

    expect(
      walletRewardCategories(
        wallet: wallet,
        products: products,
        categories: categories,
      ).map((category) => category['id']),
      ['costco-gas', 'override-only', 'manual-only'],
    );
    expect(
      walletRewardCategories(
        wallet: [
          ...wallet,
          {
            'productId': 'owned',
            'benefitOverride': {
              'rewards': [
                {'categoryId': 'all-purchases', 'rate': 1, 'unit': 'percent'},
              ],
            },
          },
        ],
        products: products,
        categories: categories,
      ).map((category) => category['id']),
      contains('all-purchases'),
    );
  });

  test(
    'masked display fills the network digit groups without revealing a PAN',
    () {
      expect(
        maskedCardDigits('1234567890123456', 'visa'),
        '•••• •••• •••• 3456',
      );
      expect(
        maskedCardDigits('1234567890123456', 'mastercard'),
        '•••• •••• •••• 3456',
      );
      expect(maskedCardDigits('123456789012345', 'amex'), '•••• •••••• •2345');
      expect(maskedCardDigits(null, 'amex'), '•••• •••••• •••••');
      expect(maskedCardDigits('12', 'amex'), '•••• •••••• •••12');
      expect(maskedCardDigits(null, 'visa'), '•••• •••• •••• ••••');
      expect(maskedCardDigits('12', 'visa'), '•••• •••• •••• ••12');
    },
  );

  testWidgets('selecting a category opens the dimmed best-card hero', (
    tester,
  ) async {
    final client = _CardsClient(staleAlias: true);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Cards(client: client)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('What are you purchasing today?'), findsOneWidget);
    expect(find.text('Use this card for the best benefits!'), findsNothing);
    await tester.tap(find.byTooltip('Show categories'));
    await tester.pumpAndSettle();
    expect(find.text('All purchases'), findsNothing);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Dining'), findsNothing);
    await tester.enterText(find.byType(TextField), 'grocries');
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();
    expect(find.text('Use this card for the best benefits!'), findsOneWidget);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'supermarket');
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'tl');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel & lodging').last);
    await tester.pumpAndSettle();

    expect(find.text('Use this card for the best benefits!'), findsOneWidget);
    expect(find.text('Trail card'), findsWidgets);
    expect(find.text('5x · Travel & lodging'), findsWidgets);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Best for Travel & lodging'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Use this card for the best benefits!'), findsNothing);

    await tester.enterText(find.byType(TextField), 'tl');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel & lodging').last);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.text('Use this card for the best benefits!'), findsNothing);
  });

  testWidgets('card preview renders the issuer logo fallback', (tester) async {
    const logo = 'https://www.example.test/apple-logo.png';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: CardPreview(
              product: {
                'name': 'Apple Card',
                'issuer': 'Goldman Sachs Bank USA',
                'network': 'Mastercard',
                'fallback': {
                  'label': 'Apple Card',
                  'backgroundColor': '#f8f8f8',
                  'foregroundColor': '#202124',
                  'issuerLogoUrl': logo,
                },
              },
              walletCard: {'displayName': 'Apple Card', 'mask': null},
            ),
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == logo,
      ),
      findsOneWidget,
    );
    expect(find.text('Goldman Sachs Bank USA'), findsOneWidget);
  });

  testWidgets(
    'wallet stack opens selected details and returns by close or drag',
    (tester) async {
      tester.view.physicalSize = const Size(392, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CardsClient(multipleCards: true, withOverride: true);
      addTearDown(client.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(body: Cards(client: client)),
        ),
      );
      await tester.pumpAndSettle();

      final previews = find.byType(CardPreview);
      expect(previews, findsNWidgets(3));
      final firstRect = tester.getRect(previews.at(0));
      final secondRect = tester.getRect(previews.at(1));
      final lastRect = tester.getRect(previews.at(2));
      expect(secondRect.top, greaterThan(firstRect.top));
      expect(secondRect.top, lessThan(firstRect.bottom));
      expect(lastRect.top, greaterThan(secondRect.top));
      expect(lastRect.top, lessThan(secondRect.bottom));
      expect(lastRect.bottom, greaterThan(secondRect.bottom));
      await tester.tapAt(Offset(firstRect.center.dx, firstRect.top + 36));
      await tester.pumpAndSettle();
      expect(find.text('Trail card'), findsWidgets);
      await tester.tap(find.byTooltip('Close card details'));
      await tester.pumpAndSettle();

      await tester.tapAt(Offset(secondRect.center.dx, secondRect.top + 36));
      await tester.pumpAndSettle();

      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byType(CardPreview), findsNWidgets(4));
      expect(
        tester
            .state<ScrollableState>(_walletSheetScrollable())
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
      expect(find.text('Backup card'), findsOneWidget);
      expect(find.text('Benefits'), findsOneWidget);
      expect(find.text('Edited'), findsWidgets);
      await tester.tap(find.byTooltip('Close card details'));
      await tester.pumpAndSettle();
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(CardPreview), findsNWidgets(3));

      await tester.tap(find.byType(CardPreview).last);
      await tester.pumpAndSettle();
      expect(find.text('Travel backup'), findsOneWidget);
      final editButton = find.text('Edit card benefits');
      await tester.scrollUntilVisible(
        editButton,
        240,
        scrollable: _walletSheetScrollable(),
      );
      await tester.ensureVisible(editButton);
      final handle = find.byTooltip('Drag down to close card details');
      final closeButton = find.byTooltip('Close card details');
      expect(handle, findsOneWidget);
      expect(closeButton, findsOneWidget);
      final listTop = tester.getTopLeft(_walletSheetScrollable()).dy;
      expect(tester.getRect(handle).bottom, lessThanOrEqualTo(listTop));
      expect(tester.getRect(closeButton).bottom, lessThanOrEqualTo(listTop));
      await tester.drag(handle, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close card details'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
      expect(find.byType(Cards), findsOneWidget);
    },
  );

  testWidgets('benefit editor requires valid rows and clears stale aliases', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _CardsClient(staleAlias: true);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Cards(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    await _openCardDetails(tester);
    final editButton = find.text('Edit card benefits');
    await tester.scrollUntilVisible(
      editButton,
      240,
      scrollable: _walletSheetScrollable(),
    );
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    final categoryFields = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Category',
    );
    await tester.scrollUntilVisible(
      categoryFields.first,
      240,
      scrollable: _scrollableFor(categoryFields.first),
    );
    await tester.ensureVisible(categoryFields.first);
    await tester.tap(categoryFields.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();
    expect(
      tester.state<FormFieldState<String>>(categoryFields.first).value,
      'groceries',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Enter a valid rate for each reward row, or remove a blank row.',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Choose a category for each reward row, or remove a blank row.',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Enter a title and details for each perk, or remove a blank row.',
      ),
      findsNothing,
    );
    expect(client.requests, contains('PUT /cards/wallet/wallet-1/benefits'));
    final body =
        client.bodies[client.requests.lastIndexOf(
          'PUT /cards/wallet/wallet-1/benefits',
        )]!;
    final override = body['override'] as Map;
    final rewards = override['rewards'] as List;
    expect(rewards, hasLength(1));
    expect(rewards.single['categoryId'], 'groceries');
    expect(rewards.single.containsKey('additionalCategoryIds'), isFalse);
    expect(rewards.single['rate'], 5);
  });

  testWidgets('reset to defaults is visible in card details', (tester) async {
    tester.view.physicalSize = const Size(392, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _CardsClient(withOverride: true);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Cards(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    await _openCardDetails(tester);

    expect(find.text('User-overridden benefits'), findsOneWidget);
    final resetButton = find.text('Reset to defaults');
    await tester.scrollUntilVisible(
      resetButton,
      240,
      scrollable: _walletSheetScrollable(),
    );
    expect(find.text('Reset to defaults'), findsOneWidget);
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(find.text('Reset card benefits?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    final index = client.requests.lastIndexOf(
      'PUT /cards/wallet/wallet-1/benefits',
    );
    expect(index, isNonNegative);
    expect(client.bodies[index]!['override'], isNull);
    expect(client.withOverride, isFalse);
    expect(client.requests.last, 'GET /cards');
  });

  testWidgets('a manual reward starts blank and cannot be saved incomplete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _CardsClient(unknownProduct: true);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Cards(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    await _openCardDetails(tester);
    final editButton = find.text('Edit card benefits');
    await tester.scrollUntilVisible(
      editButton,
      240,
      scrollable: _walletSheetScrollable(),
    );
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add reward'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Rate (required)'),
      240,
      scrollable: _editorScrollable(),
    );
    final rateField = _formFieldForLabel('Rate (required)');
    expect(tester.widget<TextFormField>(rateField).initialValue, '');
    await tester.tap(find.text('Save card benefits'));
    await tester.pumpAndSettle();
    expect(
      client.requests.where((call) => call.contains('/benefits')),
      isEmpty,
    );

    final category = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Category',
    );
    await tester.scrollUntilVisible(
      category.first,
      240,
      scrollable: _editorScrollable(),
    );
    await tester.tap(category.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();
    await tester.enterText(_formFieldForLabel('Rate (required)'), '2');
    await tester.tap(find.text('Save card benefits'));
    await tester.pumpAndSettle();

    final index = client.requests.lastIndexOf(
      'PUT /cards/wallet/wallet-1/benefits',
    );
    expect(index, isNonNegative);
    final override = client.bodies[index]!['override'] as Map;
    final rewards = override['rewards'] as List;
    expect(rewards, hasLength(1));
    expect(rewards.single['rate'], 2);
    expect(rewards.single['categoryId'], 'groceries');
  });

  testWidgets(
    'linked suggestions need explicit confirmation before rewards appear',
    (tester) async {
      tester.view.physicalSize = const Size(392, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CardsClient(linkedSuggestion: true);
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Cards(client: client)),
        ),
      );
      await tester.pumpAndSettle();
      await _openCardDetails(tester);

      expect(
        find.text('Imported account name: Wells Fargo Active Cash 4521'),
        findsOneWidget,
      );
      expect(find.text('Suggested match: Trail card'), findsOneWidget);
      expect(find.text('Benefits'), findsOneWidget);
      final confirmButton = find.text('Confirm card');
      await tester.scrollUntilVisible(
        confirmButton,
        240,
        scrollable: _walletSheetScrollable(),
      );
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(client.requests, contains('PUT /cards/wallet/wallet-1'));
      final index = client.requests.lastIndexOf('PUT /cards/wallet/wallet-1');
      expect(client.bodies[index]!['productId'], 'product-1');
      expect(find.text('Suggested match: Trail card'), findsNothing);
      expect(find.text('Trip delay cover'), findsOneWidget);
    },
  );

  testWidgets(
    'confirming a suggested product warns before clearing overrides',
    (tester) async {
      tester.view.physicalSize = const Size(392, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CardsClient(linkedSuggestion: true, withOverride: true);
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Cards(client: client)),
        ),
      );
      await tester.pumpAndSettle();
      await _openCardDetails(tester);
      final confirmButton = find.text('Confirm card');
      await tester.scrollUntilVisible(
        confirmButton,
        240,
        scrollable: _walletSheetScrollable(),
      );
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      expect(find.text('Replace user-overridden benefits?'), findsOneWidget);
      expect(
        client.requests.where((call) => call == 'PUT /cards/wallet/wallet-1'),
        isEmpty,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Suggested match: Trail card'), findsOneWidget);
    },
  );

  testWidgets('read-only members can see but cannot confirm suggestions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _CardsClient(
      linkedSuggestion: true,
      withOverride: true,
      role: HouseholdRole.gardener,
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Cards(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    await _openCardDetails(tester);

    expect(
      find.text('Imported account name: Wells Fargo Active Cash 4521'),
      findsOneWidget,
    );
    expect(find.text('Suggested match: Trail card'), findsOneWidget);
    expect(find.text('User-overridden benefits'), findsOneWidget);
    expect(
      find.text('An owner or admin can confirm this match.'),
      findsOneWidget,
    );
    expect(find.text('Confirm card'), findsNothing);
    expect(find.text('Reset to defaults'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(
              OutlinedButton,
              'Edit user-overridden benefits',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('ambiguous linked-card candidates require a product choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _CardsClient(linkedSuggestion: true, ambiguousMatch: true);
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Cards(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    await _openCardDetails(tester);
    expect(
      find.text('Imported account name: Wells Fargo Active Cash 4521'),
      findsOneWidget,
    );
    expect(find.text('Benefits'), findsOneWidget);
    final candidateField = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Possible card matches',
    );
    expect(candidateField, findsOneWidget);
    await tester.scrollUntilVisible(
      candidateField,
      240,
      scrollable: _walletSheetScrollable(),
    );
    await tester.tap(candidateField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trail card').last);
    await tester.pumpAndSettle();
    expect(client.requests, contains('PUT /cards/wallet/wallet-1'));
    expect(
      client.bodies[client.requests.lastIndexOf(
        'PUT /cards/wallet/wallet-1',
      )]!['productId'],
      'product-1',
    );
  });

  testWidgets(
    'removing the first reward keeps the remaining row values aligned',
    (tester) async {
      tester.view.physicalSize = const Size(392, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _CardsClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Cards(client: client)),
        ),
      );
      await tester.pumpAndSettle();
      await _openCardDetails(tester);
      final editButton = find.text('Edit card benefits');
      await tester.scrollUntilVisible(
        editButton,
        240,
        scrollable: _walletSheetScrollable(),
      );
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add reward'),
        240,
        scrollable: _editorScrollable(),
      );
      await tester.tap(find.text('Add reward'));
      await tester.pumpAndSettle();
      final editorScrollable = _scrollableFor(find.text('Add reward'));
      await tester.scrollUntilVisible(
        find.text('Rate (required)'),
        240,
        scrollable: editorScrollable,
      );
      final rateField = _formFieldForLabel('Rate (required)');

      final categoryFields = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Category',
      );
      await tester.tap(categoryFields.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();
      await tester.enterText(rateField, '2');
      await tester.drag(editorScrollable, const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Remove reward').first);
      await tester.tap(find.byTooltip('Remove reward').first);
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      await tester.tap(find.text('Save card benefits'));
      await tester.pumpAndSettle();
      final index = client.requests.lastIndexOf(
        'PUT /cards/wallet/wallet-1/benefits',
      );
      expect(index, isNonNegative);
      final override = client.bodies[index]!['override'] as Map;
      final rewards = override['rewards'] as List;
      expect(rewards, hasLength(1));
      expect(rewards.single['categoryId'], 'groceries');
      expect(rewards.single['unit'], 'percent');
      expect(rewards.single['rate'], 2);
    },
  );
}

Finder _scrollableFor(Finder child) =>
    find.ancestor(of: child, matching: find.byType(Scrollable)).first;

Finder _walletSheetScrollable() => find
    .descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Scrollable),
      skipOffstage: false,
    )
    .first;

Finder _editorScrollable() => find.byType(Scrollable, skipOffstage: false).last;

Future<void> _openCardDetails(WidgetTester tester) async {
  await tester.tap(find.byType(CardPreview).last);
  await tester.pumpAndSettle();
  expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  expect(find.byType(Scrollable, skipOffstage: false), findsWidgets);
}

Finder _formFieldForLabel(String text) => find
    .ancestor(of: find.text(text).last, matching: find.byType(TextFormField))
    .first;

class _CardsClient extends GreenhouseClient {
  _CardsClient({
    this.staleAlias = false,
    this.withOverride = false,
    this.linkedSuggestion = false,
    this.unknownProduct = false,
    this.ambiguousMatch = false,
    this.multipleCards = false,
    this.role = HouseholdRole.owner,
  });

  final bool staleAlias;
  final bool linkedSuggestion;
  final bool unknownProduct;
  final bool ambiguousMatch;
  final bool multipleCards;
  final HouseholdRole role;
  bool withOverride;
  bool productConfirmed = false;
  final requests = <String>[];
  final bodies = <Json?>[];

  @override
  Uri? get origin => Uri.parse('https://cards.example');

  @override
  HouseholdIdentity? get identity => HouseholdIdentity.fromJson({
    'id': 'member-1',
    'email': 'member@example.test',
    'householdId': 'home-1',
    'role': role.name,
  });

  @override
  HouseholdPermissions get permissions => HouseholdPermissions(role);

  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    requests.add('$method $path');
    bodies.add(body);
    if (method == 'PUT' && path.endsWith('/benefits')) {
      withOverride = body?['override'] != null;
      return {
        'card': {'id': 'wallet-1'},
      };
    }
    if (method == 'PUT' && path == '/cards/wallet/wallet-1') {
      productConfirmed = body?['productId'] != null;
      withOverride = false;
      return {
        'card': {'id': 'wallet-1'},
      };
    }
    return {
      'enabled': true,
      'navigationPage': {'id': 'cards', 'title': 'Cards'},
      'categories': [
        {'id': 'all-purchases', 'label': 'All purchases', 'isUniversal': true},
        {
          'id': 'groceries',
          'label': 'Groceries',
          'searchText': 'supermarket grocery store',
        },
        {'id': 'dining', 'label': 'Dining'},
        {'id': 'travel', 'label': 'Travel & lodging'},
      ],
      'products': [
        {
          'id': 'product-1',
          'name': 'Trail card',
          'issuer': 'Garden Bank',
          'network': 'Visa',
          'fallback': {
            'label': 'Garden Bank',
            'backgroundColor': '#235a44',
            'foregroundColor': '#ffffff',
          },
          'rewards': [
            {
              'categoryId': 'travel',
              if (staleAlias) 'additionalCategoryIds': ['groceries'],
              'rate': 5,
              'unit': 'x',
            },
          ],
          'benefits': [
            {
              'title': 'Trip delay cover',
              'description': 'Applies when terms are met.',
              'categoryId': null,
            },
          ],
          'sources': [],
        },
      ],
      'wallet': [
        {
          'id': 'wallet-1',
          'kind': linkedSuggestion ? 'linked' : 'manual',
          'accountId': linkedSuggestion ? 'account-1' : null,
          'displayName': linkedSuggestion
              ? 'Wells Fargo Active Cash 4521'
              : unknownProduct
              ? 'Unlisted manual card'
              : 'Trail card',
          'importedName': linkedSuggestion
              ? 'Wells Fargo Active Cash 4521'
              : null,
          'mask': '4567',
          'productId': linkedSuggestion
              ? (productConfirmed ? 'product-1' : null)
              : unknownProduct
              ? null
              : 'product-1',
          'openedOn': null,
          'suggestedProductId': linkedSuggestion && !productConfirmed
              ? (ambiguousMatch ? null : 'product-1')
              : null,
          'candidateProductIds':
              linkedSuggestion && !productConfirmed && ambiguousMatch
              ? ['product-1']
              : [],
          'benefitOverride': withOverride
              ? {'rewards': [], 'benefits': []}
              : null,
        },
        if (multipleCards)
          {
            'id': 'wallet-2',
            'kind': 'manual',
            'displayName': 'Backup card',
            'mask': '1122',
            'productId': 'product-1',
            'openedOn': null,
            'benefitOverride': withOverride
                ? {
                    'rewards': [
                      {'categoryId': 'groceries', 'rate': 7, 'unit': 'percent'},
                    ],
                    'benefits': [],
                  }
                : null,
          },
        if (multipleCards)
          {
            'id': 'wallet-3',
            'kind': 'manual',
            'displayName': 'Travel backup',
            'mask': '7788',
            'productId': 'product-1',
            'openedOn': null,
            'benefitOverride': null,
          },
      ],
    };
  }
}
