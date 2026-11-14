import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';
import 'transactions.dart';

@immutable
class CardsCatalog {
  const CardsCatalog({
    required this.enabled,
    required this.navigationPage,
    required this.catalogSource,
    required this.products,
    required this.categories,
    required this.wallet,
  });

  final bool enabled;
  final Json? navigationPage;
  final Json? catalogSource;
  final List<Json> products;
  final List<Json> categories;
  final List<Json> wallet;

  factory CardsCatalog.fromJson(Json json) => CardsCatalog(
    enabled: json['enabled'] == true,
    navigationPage: json['navigationPage'] == null
        ? null
        : object(json['navigationPage']),
    catalogSource: json['catalogSource'] == null
        ? null
        : object(json['catalogSource']),
    products: objects(json['products']),
    categories: objects(json['categories']),
    wallet: objects(json['wallet']),
  );
}

@immutable
class CardRecommendation {
  const CardRecommendation(this.walletCard, this.product, this.reward);

  final Json walletCard;
  final Json? product;
  final Json? reward;
}

bool hasBenefitOverride(Json card) => card['benefitOverride'] is Map;

List<Json> effectiveCardRewards(Json card, Json? product) {
  if (hasBenefitOverride(card)) {
    return objects(object(card['benefitOverride'])['rewards']);
  }
  return objects(product?['rewards']);
}

List<Json> effectiveCardBenefits(Json card, Json? product) {
  if (hasBenefitOverride(card)) {
    return objects(object(card['benefitOverride'])['benefits']);
  }
  return objects(product?['benefits']);
}

List<Json> walletRewardCategories({
  required List<Json> wallet,
  required List<Json> products,
  required List<Json> categories,
}) {
  final productById = {for (final product in products) product['id']: product};
  final availableIds = <String>{};
  for (final card in wallet) {
    final product = productById[card['productId']];
    for (final reward in effectiveCardRewards(card, product)) {
      if (reward['categoryId'] case final String id) availableIds.add(id);
      if (reward['additionalCategoryIds'] case final List ids) {
        availableIds.addAll(ids.whereType<String>());
      }
    }
  }
  return categories
      .where((category) => availableIds.contains(category['id']))
      .toList();
}

List<CardRecommendation> rankCardsForCategory({
  required List<Json> wallet,
  required List<Json> products,
  required String categoryId,
  required List<Json> categories,
}) {
  final productById = {for (final product in products) product['id']: product};
  final universalIds = categories
      .where(_isUniversalCategory)
      .map((category) => category['id'])
      .whereType<String>()
      .toSet();
  final result = wallet
      .map((card) {
        final product = productById[card['productId']];
        final allRewards = effectiveCardRewards(card, product);
        final rewards = allRewards
            .where(
              (reward) =>
                  _rewardAppliesToCategory(reward, categoryId, universalIds),
            )
            .toList();
        final reward = rewards.isEmpty
            ? null
            : rewards.reduce(
                (best, item) =>
                    rewardRate(item) > rewardRate(best) ? item : best,
              );
        return CardRecommendation(card, product, reward);
      })
      .where(
        (item) =>
            item.reward != null &&
            (item.product != null || hasBenefitOverride(item.walletCard)),
      )
      .toList();
  result.sort((a, b) => rewardRate(b.reward!).compareTo(rewardRate(a.reward!)));
  return result;
}

bool _rewardAppliesToCategory(
  Json reward,
  String categoryId,
  Set<String> universalIds,
) {
  final additional = reward['additionalCategoryIds'];
  return reward['categoryId'] == categoryId ||
      (additional is List && additional.contains(categoryId)) ||
      universalIds.contains(reward['categoryId']);
}

double rewardRate(Json reward) {
  final rate = reward['rate'];
  return rate is num ? rate.toDouble() : double.tryParse(label(rate, '')) ?? 0;
}

bool _isUniversalCategory(Json category) =>
    category['id'] == 'all-purchases' ||
    category['isUniversal'] == true ||
    category['kind'] == 'all-purchases';

String? productAvailabilityLabel(Json? product) =>
    switch (label(product?['status'], '')) {
      'discontinued' => 'Not available for new applicants',
      'invite_only' => 'Invite only',
      'unknown' => 'Availability unverified',
      _ => null,
    };

String rewardRateLabel(Json reward) {
  final rate = rewardRate(reward);
  final number = rate == rate.roundToDouble()
      ? rate.toStringAsFixed(0)
      : rate
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return '$number${reward['unit'] == 'x' ? 'x' : '%'}';
}

String annualFeeDisplay(Object? cents) {
  if (cents is! num) return 'Not verified';
  if (cents == 0) return 'No annual fee';
  return money({'amount': '$cents', 'currency': 'USD'});
}

/// Native card wallet. PAN and CVV data are never requested or displayed.
class Cards extends StatefulWidget {
  const Cards({required this.client, this.onDisabled, super.key});
  final GreenhouseClient client;
  final VoidCallback? onDisabled;

  @override
  State<Cards> createState() => _CardsState();
}

class _CardsState extends State<Cards> {
  late Future<CardsCatalog> future = _load();
  String? selectedCardId;
  String? selectedCategoryId;
  bool reportedDisabled = false;

  Future<CardsCatalog> _load() async {
    final catalog = CardsCatalog.fromJson(
      await widget.client.request('/cards'),
    );
    if (!catalog.enabled && !reportedDisabled) {
      reportedDisabled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDisabled?.call();
      });
    }
    return catalog;
  }

  Future<void> _reload() async {
    final request = _load();
    setState(() {
      future = request;
    });
    try {
      await request;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CardsCatalog>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return FinanceList(
          onRefresh: _reload,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(errorMessage(snapshot.error!)),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final catalog = snapshot.data!;
      if (!catalog.enabled || catalog.navigationPage == null) {
        return const FinanceList(
          children: [
            Panel(
              child: Text('Cards is not enabled for this GreenHouse instance.'),
            ),
          ],
        );
      }
      return FinanceList(onRefresh: _reload, children: _contents(catalog));
    },
  );

  List<Widget> _contents(CardsCatalog catalog) {
    final categories = walletRewardCategories(
      wallet: catalog.wallet,
      products: catalog.products,
      categories: catalog.categories,
    );
    if (selectedCategoryId != null &&
        categories.every((category) => category['id'] != selectedCategoryId)) {
      selectedCategoryId = null;
    }
    if (selectedCategoryId == null && categories.isNotEmpty) {
      selectedCategoryId = label(categories.first['id'], '');
    }
    final selectedCard = selectedCardId == null
        ? null
        : catalog.wallet
              .where((card) => card['id'] == selectedCardId)
              .firstOrNull;
    if (selectedCardId != null && selectedCard == null) {
      selectedCardId = null;
    }
    final category = categories
        .where((row) => row['id'] == selectedCategoryId)
        .firstOrNull;
    final ranked = selectedCategoryId == null
        ? <CardRecommendation>[]
        : rankCardsForCategory(
            wallet: catalog.wallet,
            products: catalog.products,
            categoryId: selectedCategoryId!,
            categories: catalog.categories,
          );
    return [
      const Eyebrow('Card benefits'),
      const SizedBox(height: 6),
      Text(
        'What are you purchasing today?',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 14),
      _CategorySearch(
        categories: categories,
        selectedId: selectedCategoryId,
        onSelected: (value) {
          setState(() => selectedCategoryId = label(value['id'], ''));
          _showCategoryBenefits(catalog, value);
        },
      ),
      if (catalog.wallet.isEmpty) ...[
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No cards in your wallet yet.'),
              if (!widget.client.permissions.canManageSharedFinances)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'An owner or admin can add cards for the household.',
                  ),
                ),
            ],
          ),
        ),
      ],
      SectionTitle('Your cards', action: _addButton(catalog)),
      if (catalog.wallet.isEmpty)
        const Panel(
          child: Text('Linked credit accounts and manual cards appear here.'),
        )
      else
        _WalletCardStack(
          cards: catalog.wallet,
          products: catalog.products,
          selectedCardId: selectedCardId ?? '',
          onSelected: (card) => _showCardDetails(catalog, card),
        ),
      if (category != null) ...[
        const SectionTitle('Best for this purchase'),
        if (ranked.isEmpty)
          Panel(
            child: Text(
              catalog.wallet.isEmpty ? 'Add a card to compare benefits.' : 'No verified rewards match this category. Check the card perks below.',
            ),
          ),
        for (var index = 0; index < ranked.length; index++)
          _RecommendationTile(
            recommendation: ranked[index],
            category: category,
            onTap: () => _showCardDetails(catalog, ranked[index].walletCard),
          ),
      ],
      if (catalog.catalogSource case final source?) ...[
        const SectionTitle('Catalog provenance'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label(source['name'], 'Card catalog')),
              SelectableText(label(source['url'], '')),
              Text('Revision ${label(source['revision'])}'),
              SelectableText('License: ${label(source['licenseUrl'])}'),
            ],
          ),
        ),
      ],
    ];
  }

  Future<void> _showCardDetails(CardsCatalog catalog, Json card) async {
    final cardId = label(card['id'], '');
    setState(() => selectedCardId = cardId);
    var currentCard = card;
    var currentProduct = catalog.products
        .where((row) => row['id'] == card['productId'])
        .firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: .9,
          minChildSize: .48,
          maxChildSize: .96,
          expand: false,
          builder: (context, scrollController) => LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 32)
                  .clamp(0, 480)
                  .toDouble();
              final previewHeight = width / 1.586;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Column(
                      children: [
                        _CardSheetHandle(
                          onClose: () => Navigator.of(sheetContext).pop(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Close card details',
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        Center(
                          child: SizedBox(
                            width: width,
                            child: CardPreview(
                              product: currentProduct,
                              walletCard: currentCard,
                              height: previewHeight,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const SectionTitle('Benefits'),
                        ..._perkWidgets(
                          currentProduct,
                          catalog.categories,
                          currentCard,
                        ),
                        const SizedBox(height: 8),
                        const Eyebrow('Card details'),
                        const SizedBox(height: 8),
                        _CardDetails(
                          client: widget.client,
                          card: currentCard,
                          product: currentProduct,
                          products: catalog.products,
                          categories: catalog.categories,
                          onUpdated: () async {
                            await _reload();
                            final refreshed = await future;
                            final updated = refreshed.wallet
                                .where((item) => item['id'] == cardId)
                                .firstOrNull;
                            if (updated == null || !sheetContext.mounted) {
                              return;
                            }
                            setSheetState(() {
                              currentCard = updated;
                              currentProduct = refreshed.products
                                  .where(
                                    (row) => row['id'] == updated['productId'],
                                  )
                                  .firstOrNull;
                            });
                          },
                          onActivity: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Card activity'),
                                ),
                                body: Activity(
                                  client: widget.client,
                                  initialQuery: {
                                    'accountIds': label(
                                      currentCard['accountId'],
                                      '',
                                    ),
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (currentProduct != null) ...[
                          const SectionTitle('Verified sources'),
                          ..._sourceWidgets(context, currentProduct!),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _addButton(CardsCatalog catalog) => TextButton.icon(
    onPressed: widget.client.permissions.canManageSharedFinances
        ? () => _addCard(catalog)
        : null,
    icon: const Icon(Icons.add_card_outlined),
    label: const Text('Add card'),
  );

  Future<void> _addCard(CardsCatalog catalog) async {
    final product = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPicker(products: catalog.products),
    );
    if (product == null || !mounted) return;
    try {
      await widget.client.request(
        '/cards/wallet',
        method: 'POST',
        body: {'productId': product['id']},
      );
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e));
    }
  }

  Future<void> _showCategoryBenefits(
    CardsCatalog catalog,
    Json category,
  ) async {
    if (!mounted) return;
    final ranked = rankCardsForCategory(
      wallet: catalog.wallet,
      products: catalog.products,
      categoryId: label(category['id'], ''),
      categories: catalog.categories,
    );
    final best = ranked.firstOrNull;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss card recommendations',
      barrierColor: Colors.black.withValues(alpha: .70),
      pageBuilder: (dialog, _, _) => SafeArea(
        child: Center(
          child: Semantics(
            namesRoute: true,
            label: 'Card recommendation for ${label(category['label'])}',
            child: Dialog(
              child: SizedBox(
                width: 480,
                height: MediaQuery.sizeOf(dialog).height * .78,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Card benefits'),
                      const SizedBox(height: 10),
                      Text(
                        'Use this card for the best benefits!',
                        style: Theme.of(dialog).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text('Best for ${label(category['label'])}'),
                      if (best == null) ...[
                        const SizedBox(height: 14),
                        const Panel(
                          child: Text(
                            'No verified rewards are available for this purchase category yet.',
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 14),
                        CardPreview(
                          product: best.product,
                          walletCard: best.walletCard,
                          height: 156,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label(best.product?['name']),
                          style: Theme.of(dialog).textTheme.titleLarge,
                        ),
                        Text(
                          '${rewardRateLabel(best.reward!)} · ${label(category['label'])}${_rewardConditions(best.reward!)}',
                        ),
                        if (hasBenefitOverride(best.walletCard))
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: _UserOverrideBadge(),
                          ),
                        const SectionTitle('Other verified perks'),
                        ..._perkWidgets(
                          best.product,
                          catalog.categories,
                          best.walletCard,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategorySearch extends StatelessWidget {
  const _CategorySearch({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });
  final List<Json> categories;
  final String? selectedId;
  final ValueChanged<Json> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = categories
        .where((row) => row['id'] == selectedId)
        .firstOrNull;
    return Autocomplete<Json>(
      displayStringForOption: (option) => label(option['label']),
      optionsBuilder: (text) {
        final query = text.text.trim().toLowerCase();
        if (query.isEmpty) return categories;
        final matches = categories.where((row) {
          final name = label(row['label'], '').toLowerCase();
          final searchText = label(row['searchText'], '').toLowerCase();
          final searchable = '$name $searchText';
          return searchable.contains(query) || _fuzzyMatch(searchable, query);
        }).toList();
        matches.sort((a, b) {
          final left = '${label(a['label'], '')} ${label(a['searchText'], '')}'
              .toLowerCase();
          final right = '${label(b['label'], '')} ${label(b['searchText'], '')}'
              .toLowerCase();
          return _matchScore(left, query).compareTo(_matchScore(right, query));
        });
        return matches.take(100).toList();
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focus, submit) {
        if (controller.text.isEmpty && selected != null) {
          controller.text = label(selected['label']);
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        }
        return TextField(
          controller: controller,
          focusNode: focus,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            labelText: 'Purchase category',
            hintText: 'Search categories',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Show categories',
              onPressed: () {
                controller.clear();
                focus.requestFocus();
              },
              icon: const Icon(Icons.arrow_drop_down),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 620),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options.elementAt(index);
                return ListTile(
                  title: Text(label(option['label'])),
                  onTap: () => select(option),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

bool _fuzzyMatch(String value, String query) {
  final words = value
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .take(100);
  final wordList = words.toList();
  final initials = wordList.map((word) => word[0]).join();
  return query.split(RegExp(r'\s+')).every((term) {
    if (value.contains(term) || initials.contains(term)) return true;
    if (term.length < 4) return false;
    final maxDistance = term.length >= 9 ? 2 : 1;
    return wordList.any(
      (word) =>
          (word.length - term.length).abs() <= maxDistance &&
          _editDistance(word, term) <= maxDistance,
    );
  });
}

int _editDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var row = 1; row <= left.length; row++) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = row;
    for (var column = 1; column <= right.length; column++) {
      final substitution =
          previous[column - 1] +
          (left.codeUnitAt(row - 1) == right.codeUnitAt(column - 1) ? 0 : 1);
      current[column] = [
        previous[column] + 1,
        current[column - 1] + 1,
        substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

int _matchScore(String value, String query) {
  if (value == query) return 0;
  if (value.startsWith(query)) return 1;
  if (value.contains(query)) return 2;
  return 3;
}

class CardPreview extends StatelessWidget {
  const CardPreview({
    required this.product,
    required this.walletCard,
    this.height = 116,
    super.key,
  });
  final Json? product;
  final Json walletCard;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = object(product?['fallback']);
    final background = _hexColor(
      fallback['backgroundColor'],
      const Color(0xff285b4a),
    );
    final foreground = _hexColor(fallback['foregroundColor'], Colors.white);
    final image = Uri.tryParse(label(product?['imageUrl'], ''));
    final useImage = image?.scheme == 'https';
    final logo = Uri.tryParse(label(fallback['issuerLogoUrl'], ''));
    final useLogo = logo?.scheme == 'https';
    final lightFallback = background.computeLuminance() > .65;
    final showNumber = height >= 140;
    return Semantics(
      label:
          '${label(product?['name'], label(walletCard['displayName'], 'Unknown card'))}, ${_maskLabel(walletCard['mask'])}${hasBenefitOverride(walletCard) ? ', benefits customized' : ''}',
      child: Container(
        height: height,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: useImage
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    background,
                    Color.lerp(
                      background,
                      Colors.black,
                      lightFallback ? .08 : .32,
                    )!,
                  ],
                ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (useImage)
              Image.network(
                image.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: background),
              ),
            if (useImage)
              ColoredBox(color: Colors.black.withValues(alpha: .24)),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 17,
                vertical: showNumber ? 17 : 10,
              ),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: useImage ? Colors.white : foreground),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label(
                              product?['issuer'],
                              label(
                                fallback['label'],
                                label(walletCard['displayName'], 'Card'),
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        if (useLogo)
                          SizedBox(
                            width: 30,
                            height: 22,
                            child: Image.network(
                              logo.toString(),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        if (hasBenefitOverride(walletCard)) ...[
                          if (useLogo) const SizedBox(width: 8),
                          const _CardOverrideMark(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label(product?['name'], 'Unknown product'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (showNumber) ...[
                      const Spacer(),
                      Text(
                        maskedCardDigits(
                          walletCard['mask'],
                          product?['network'] ?? product?['issuer'],
                        ),
                        style: const TextStyle(letterSpacing: 2, fontSize: 18),
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _networkLabel(
                            product?['network'] ?? product?['issuer'],
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String maskedCardDigits(Object? value, Object? network) {
  final digits = label(value, '').replaceAll(RegExp(r'\D'), '');
  final brand = label(network, '').toLowerCase();
  final isAmex = brand.contains('amex') || brand.contains('american');
  final digitCount = isAmex ? 15 : 16;
  final visible = digits.substring(digits.length > 4 ? digits.length - 4 : 0);
  final masked =
      '${List.filled(digitCount - visible.length, '•').join()}$visible';
  final groups = isAmex ? const [4, 6, 5] : const [4, 4, 4, 4];
  var offset = 0;
  final formatted = <String>[];
  for (final length in groups) {
    formatted.add(masked.substring(offset, offset + length));
    offset += length;
  }
  return formatted.join(' ');
}

String _maskLabel(Object? value) {
  final digits = label(value, '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return 'number unavailable';
  final lastFour = digits.substring(digits.length > 4 ? digits.length - 4 : 0);
  return 'ending in $lastFour';
}

String _networkLabel(Object? value) {
  final network = label(value, '').toLowerCase().replaceAll(' ', '');
  if (network.contains('visa')) return 'VISA';
  if (network.contains('master')) return 'mastercard';
  if (network.contains('amex') || network.contains('american')) return 'AMEX';
  return network.isEmpty ? 'CARD' : network.toUpperCase();
}

Color _hexColor(Object? value, Color fallback) {
  final hex = label(value, '').replaceFirst('#', '');
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;
  return Color(hex.length <= 6 ? 0xff000000 | parsed : parsed);
}

class _WalletCardStack extends StatelessWidget {
  const _WalletCardStack({
    required this.cards,
    required this.products,
    required this.selectedCardId,
    required this.onSelected,
  });

  final List<Json> cards;
  final List<Json> products;
  final String selectedCardId;
  final ValueChanged<Json> onSelected;

  @override
  Widget build(BuildContext context) {
    final productsById = {
      for (final product in products) product['id']: product,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = constraints.maxWidth / 1.586;
        final step = (72 * MediaQuery.textScalerOf(context).scale(1))
            .clamp(72, 112)
            .toDouble();
        return SizedBox(
          height: cardHeight + step * (cards.length - 1),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var index = 0; index < cards.length; index++)
                _stackedCard(
                  context,
                  cards[index],
                  index * step,
                  cardHeight,
                  productsById,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _stackedCard(
    BuildContext context,
    Json card,
    double top,
    double height,
    Map<Object?, Json> productsById,
  ) => Positioned(
    top: top,
    left: 0,
    right: 0,
    child: Semantics(
      button: true,
      selected: card['id'] == selectedCardId,
      label:
          '${label(productsById[card['productId']]?['name'], label(card['displayName'], 'Card'))}, ${label(productsById[card['productId']]?['issuer'], 'Unknown issuer')}${hasBenefitOverride(card) ? ', benefits customized' : ''}',
      hint: 'Open card details',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => onSelected(card),
          child: CardPreview(
            product: productsById[card['productId']],
            walletCard: card,
            height: height,
          ),
        ),
      ),
    ),
  );
}

class _CardOverrideMark extends StatelessWidget {
  const _CardOverrideMark();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'User-overridden benefits',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.surface.withValues(alpha: .88),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_outlined, size: 14, color: color.primary),
            const SizedBox(width: 3),
            Text(
              'Edited',
              style: TextStyle(
                color: color.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSheetHandle extends StatefulWidget {
  const _CardSheetHandle({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_CardSheetHandle> createState() => _CardSheetHandleState();
}

class _CardSheetHandleState extends State<_CardSheetHandle> {
  double dragDistance = 0;
  bool closing = false;

  void _close() {
    if (closing) return;
    closing = true;
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Center(
      child: Tooltip(
        message: 'Drag down to close card details',
        child: Semantics(
          button: true,
          label: 'Card details handle',
          hint: 'Swipe down or tap to return to the wallet',
          onTap: widget.onClose,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              if (!closing) dragDistance = 0;
            },
            onVerticalDragUpdate: (details) {
              if (closing) return;
              dragDistance += details.delta.dy;
              if (dragDistance > 96) _close();
            },
            onTap: _close,
            child: SizedBox(
              width: 64,
              height: 24,
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _UserOverrideBadge extends StatelessWidget {
  const _UserOverrideBadge();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'User-overridden benefits',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.edit_note_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'User-overridden benefits',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirmCardProductChange(
  BuildContext context,
  Json walletCard,
) async {
  if (!hasBenefitOverride(walletCard)) return true;
  return await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Replace user-overridden benefits?'),
          content: const Text(
            'Changing this card product clears its user-overridden rewards and perks and uses the selected product’s current catalog details.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ==
      true;
}

class CardProductMatcher extends StatefulWidget {
  const CardProductMatcher({
    required this.client,
    required this.walletCard,
    required this.products,
    this.onUpdated,
    super.key,
  });

  final GreenhouseClient client;
  final Json walletCard;
  final List<Json> products;
  final Future<void> Function()? onUpdated;

  @override
  State<CardProductMatcher> createState() => _CardProductMatcherState();
}

class _CardProductMatcherState extends State<CardProductMatcher> {
  late Json card = widget.walletCard;
  bool busy = false;

  @override
  void didUpdateWidget(covariant CardProductMatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walletCard.hashCode != widget.walletCard.hashCode) {
      card = widget.walletCard;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.client.permissions.canManageSharedFinances;
    final importedName = label(card['importedName'], '');
    final suggestedId = label(card['suggestedProductId'], '');
    final suggested = widget.products
        .where((product) => product['id'] == suggestedId)
        .firstOrNull;
    final candidateIds = card['candidateProductIds'] is List
        ? (card['candidateProductIds'] as List).whereType<String>().toSet()
        : <String>{};
    final candidates = widget.products
        .where((product) => candidateIds.contains(product['id']))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Card product'),
        if (importedName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Imported account name: $importedName'),
          ),
        if (hasBenefitOverride(card)) ...[
          const SizedBox(height: 4),
          const _UserOverrideBadge(),
        ],
        if (suggested != null) ...[
          const SizedBox(height: 8),
          Text('Suggested match: ${label(suggested['name'])}'),
          if (productAvailabilityLabel(suggested) case final status?)
            Text(status, style: Theme.of(context).textTheme.bodySmall),
          if (label(suggested['sourceNotes'], '').isNotEmpty)
            Text(
              label(suggested['sourceNotes']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: busy
                    ? null
                    : () => _selectProduct(label(suggested['id'])),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm card'),
              ),
            )
          else
            const Text('An owner or admin can confirm this match.'),
        ],
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(('candidate', card['id'], card.hashCode)),
            initialValue: null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Possible card matches',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Choose a match'),
              ),
              for (final item in candidates)
                DropdownMenuItem(
                  value: label(item['id']),
                  child: Text(
                    [
                      label(item['name']),
                      ?productAvailabilityLabel(item),
                    ].join(' · '),
                  ),
                ),
            ],
            onChanged: !canEdit || busy
                ? null
                : (value) {
                    if (value != null) _selectProduct(value);
                  },
          ),
        ],
        if (canEdit) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: ValueKey((
              'catalog',
              card['id'],
              card['productId'],
              card.hashCode,
            )),
            initialValue: label(card['productId'], '').isEmpty
                ? null
                : label(card['productId']),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: suggested == null
                  ? 'Choose a card product'
                  : 'Choose another card product',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Unknown product'),
              ),
              for (final item in widget.products)
                DropdownMenuItem<String?>(
                  value: label(item['id']),
                  child: Text(
                    [
                      label(item['name']),
                      ?productAvailabilityLabel(item),
                    ].join(' · '),
                  ),
                ),
            ],
            onChanged: busy ? null : _selectProduct,
          ),
          if (busy) const LinearProgressIndicator(),
        ] else if (suggested == null && candidates.isEmpty)
          const Text('An owner or admin can identify this linked card.'),
      ],
    );
  }

  Future<void> _selectProduct(String? productId) async {
    if (productId == label(card['productId'], '') || busy) return;
    final confirmed = await confirmCardProductChange(context, card);
    if (!confirmed) {
      if (mounted) await widget.onUpdated?.call();
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final response = await widget.client.request(
        '/cards/wallet/${endpoint(card['id'])}',
        method: 'PUT',
        body: {'productId': productId, 'openedOn': card['openedOn']},
      );
      if (!mounted) return;
      final updated = object(response['card']);
      if (updated.isNotEmpty) setState(() => card = updated);
      await widget.onUpdated?.call();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _CardDetails extends StatelessWidget {
  const _CardDetails({
    required this.client,
    required this.card,
    required this.product,
    required this.products,
    required this.categories,
    required this.onUpdated,
    required this.onActivity,
  });
  final GreenhouseClient client;
  final Json card;
  final Json? product;
  final List<Json> products;
  final List<Json> categories;
  final Future<void> Function() onUpdated;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    final id = endpoint(card['id']);
    final openedOn = label(card['openedOn'], '');
    final editable = client.permissions.canManageSharedFinances;
    final isLinked = card['kind'] == 'linked';
    final hasOverride = hasBenefitOverride(card);
    final importedName = label(card['importedName'], '');
    final suggestedId = label(card['suggestedProductId'], '');
    final suggestedProduct = products
        .where((item) => item['id'] == suggestedId)
        .firstOrNull;
    final candidateIds = card['candidateProductIds'] is List
        ? (card['candidateProductIds'] as List).whereType<String>().toSet()
        : <String>{};
    final candidates = products
        .where((item) => candidateIds.contains(item['id']))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label(
                        card['displayName'],
                        label(product?['name'], 'Card'),
                      ),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Chip(
                    label: Text(isLinked ? 'Linked account' : 'Manual card'),
                  ),
                ],
              ),
              if (hasOverride) const _UserOverrideBadge(),
              if (productAvailabilityLabel(product) case final status?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Chip(label: Text(status)),
                ),
              if (label(product?['sourceNotes'], '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label(product?['sourceNotes'])),
                ),
              if (isLinked && importedName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Imported account name: $importedName'),
                ),
              if (product == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    isLinked
                        ? 'This linked card has not been matched to a verified product.'
                        : 'This manual card has no verified product match yet.',
                  ),
                ),
              if (isLinked && product == null && suggestedProduct != null) ...[
                const SizedBox(height: 8),
                Text('Suggested match: ${label(suggestedProduct['name'])}'),
                if (editable)
                  FilledButton.tonalIcon(
                    onPressed: () => _updateProduct(
                      context,
                      id,
                      label(suggestedProduct['id']),
                      openedOn,
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirm card'),
                  )
                else
                  const Text('An owner or admin can confirm this match.'),
              ],
              if (isLinked && product == null && candidates.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Possible card matches',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Choose a match'),
                    ),
                    for (final candidate in candidates)
                      DropdownMenuItem<String>(
                        value: label(candidate['id']),
                        child: Text(
                          label(candidate['name']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: !editable
                      ? null
                      : (value) => _updateProduct(context, id, value, openedOn),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Opened ${openedOn.isEmpty ? 'not set' : humanDate(openedOn)}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Set opened date',
                    onPressed: editable
                        ? () => _editOpenedDate(context, id, openedOn)
                        : null,
                    icon: const Icon(Icons.edit_calendar_outlined),
                  ),
                ],
              ),
              DropdownButtonFormField<String?>(
                key: ValueKey((card['id'], card['productId'], card.hashCode)),
                initialValue: label(card['productId'], '').isEmpty
                    ? null
                    : label(card['productId']),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: isLinked && product == null
                      ? suggestedProduct == null
                            ? 'Choose a card product'
                            : 'Choose another card product'
                      : 'Verified card product',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Unknown product'),
                  ),
                  for (final item in products)
                    DropdownMenuItem<String?>(
                      value: label(item['id']),
                      child: Text(
                        label(item['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: !editable
                    ? null
                    : (value) => _updateProduct(context, id, value, openedOn),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: editable ? () => _editBenefits(context) : null,
                icon: const Icon(Icons.edit_note_outlined),
                label: Text(
                  hasOverride
                      ? 'Edit user-overridden benefits'
                      : 'Edit card benefits',
                ),
              ),
              if (hasOverride && editable)
                TextButton.icon(
                  onPressed: () => _resetBenefits(context, id),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset to defaults'),
                ),
              if (!editable)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'An owner or admin can update shared card details.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (isLinked && label(card['accountId'], '').isNotEmpty) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: onActivity,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View card transactions'),
          ),
        ],
      ],
    );
  }

  Future<void> _editBenefits(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _CardBenefitEditor(
          client: client,
          card: card,
          product: product,
          categories: categories,
          onSaved: onUpdated,
        ),
      ),
    );
  }

  Future<void> _resetBenefits(BuildContext context, String id) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset card benefits?'),
        content: const Text(
          'This restores the current catalog benefits for this card.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    try {
      await client.request(
        '/cards/wallet/$id/benefits',
        method: 'PUT',
        body: {'override': null},
      );
      if (context.mounted) await onUpdated();
    } catch (e) {
      if (context.mounted) showMessage(context, errorMessage(e));
    }
  }

  Future<void> _editOpenedDate(
    BuildContext context,
    String id,
    String current,
  ) async {
    final parsed = DateTime.tryParse(current);
    final date = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      helpText: 'When was this card opened?',
    );
    if (date == null || !context.mounted) return;
    await _save(context, id, product?['id'] as String?, isoDay(date));
  }

  Future<void> _updateProduct(
    BuildContext context,
    String id,
    String? value,
    String current,
  ) async {
    if (value == label(card['productId'], '')) return;
    if (hasBenefitOverride(card)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Replace user-overridden benefits?'),
          content: const Text(
            'Changing this card product clears its user-overridden rewards and perks and uses the selected product’s catalog details.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        if (context.mounted) await onUpdated();
        return;
      }
    }
    if (!context.mounted) return;
    await _save(context, id, value, current.isEmpty ? null : current);
  }

  Future<void> _save(
    BuildContext context,
    String id,
    String? productId,
    String? openedOn,
  ) async {
    try {
      await client.request(
        '/cards/wallet/$id',
        method: 'PUT',
        body: {'productId': productId, 'openedOn': openedOn},
      );
      if (context.mounted) await onUpdated();
    } catch (e) {
      if (context.mounted) showMessage(context, errorMessage(e));
    }
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({
    required this.recommendation,
    required this.category,
    required this.onTap,
  });
  final CardRecommendation recommendation;
  final Json category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Panel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Icons.credit_card_outlined),
          title: Text(
            label(
              recommendation.product?['name'],
              label(recommendation.walletCard['displayName'], 'Unknown card'),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recommendation.reward == null
                    ? 'No verified ${label(category['label']).toLowerCase()} reward'
                    : '${rewardRateLabel(recommendation.reward!)} · ${label(category['label'])}${_rewardConditions(recommendation.reward!)}',
              ),
              if (hasBenefitOverride(recommendation.walletCard))
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: _UserOverrideBadge(),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasBenefitOverride(recommendation.walletCard))
                const Icon(Icons.edit_note_outlined, size: 19),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        ),
      ),
    ),
  );
}

String _rewardConditions(Json reward) {
  final parts = [
    if (label(reward['cap'], '').isNotEmpty) 'cap ${label(reward['cap'])}',
    if (label(reward['conditions'], '').isNotEmpty) label(reward['conditions']),
  ];
  return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
}

List<Widget> _perkWidgets(
  Json? product,
  List<Json> categories,
  Json walletCard,
) {
  final categoryNames = {for (final row in categories) row['id']: row['label']};
  final rewards = effectiveCardRewards(walletCard, product).toList()
    ..sort((a, b) => rewardRate(b).compareTo(rewardRate(a)));
  final benefits = effectiveCardBenefits(walletCard, product);
  return [
    if (rewards.isEmpty && benefits.isEmpty)
      const Panel(child: Text('No verified perks are listed for this card.')),
    for (final reward in rewards)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          child: _PerkText(
            title:
                '${rewardRateLabel(reward)} ${label(categoryNames[reward['categoryId']], 'on purchases')}',
            detail: _rewardConditions(reward).replaceFirst(RegExp(r'^ · '), ''),
            icon: Icons.stars_outlined,
          ),
        ),
      ),
    for (final benefit in benefits)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          child: _PerkText(
            title: label(benefit['title'], 'Card benefit'),
            detail: label(
              benefit['description'],
              'Verified benefit details unavailable.',
            ),
            icon: Icons.card_giftcard_outlined,
          ),
        ),
      ),
    if (product != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Panel(
          child: _PerkText(
            title: 'Annual fee',
            detail: annualFeeDisplay(product['annualFeeCents']),
            icon: Icons.payments_outlined,
          ),
        ),
      ),
  ];
}

class _PerkText extends StatelessWidget {
  const _PerkText({
    required this.title,
    required this.detail,
    required this.icon,
  });
  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (detail.isNotEmpty) ...[const SizedBox(height: 4), Text(detail)],
          ],
        ),
      ),
    ],
  );
}

List<Widget> _sourceWidgets(BuildContext context, Json product) {
  final sources = objects(product['sources']);
  if (sources.isEmpty) {
    return [
      Panel(
        child: Text(
          'GreenHouse catalog reviewed ${label(product['verifiedOn'], 'date unknown')}. No issuer sources were returned.',
        ),
      ),
    ];
  }
  return [
    Panel(
      child: Text(
        'GreenHouse catalog reviewed ${label(product['verifiedOn'], 'date unknown')}. Issuer source dates below are the dates those pages were checked.',
      ),
    ),
    for (final source in sources)
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label(source['label'], 'Source'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            SelectableText(label(source['url'], '')),
            Text(
              'Issuer page checked ${label(source['accessedOn'], 'date unknown')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
  ];
}

class _RewardDraft {
  _RewardDraft({
    required this.isNew,
    required this.categoryId,
    required this.rate,
    required this.unit,
    required this.cap,
    required this.conditions,
    required this.additionalCategoryIds,
    required this.validFrom,
    required this.validThrough,
  });

  factory _RewardDraft.fromJson(Json reward) => _RewardDraft(
    isNew: false,
    categoryId: reward['categoryId'] is String
        ? reward['categoryId'] as String
        : null,
    rate: reward['rate'] is num
        ? '${reward['rate']}'
        : label(reward['rate'], ''),
    unit: reward['unit'] == 'x' ? 'x' : 'percent',
    cap: label(reward['cap'], ''),
    conditions: label(reward['conditions'], ''),
    additionalCategoryIds:
        (reward['additionalCategoryIds'] is List
                ? reward['additionalCategoryIds'] as List
                : const [])
            .whereType<String>()
            .toList(),
    validFrom: reward['validFrom'] is String
        ? reward['validFrom'] as String
        : null,
    validThrough: reward['validThrough'] is String
        ? reward['validThrough'] as String
        : null,
  );

  factory _RewardDraft.blank() => _RewardDraft(
    isNew: true,
    categoryId: null,
    rate: '',
    unit: 'percent',
    cap: '',
    conditions: '',
    additionalCategoryIds: [],
    validFrom: null,
    validThrough: null,
  );

  final Object key = Object();
  final bool isNew;
  String? categoryId;
  String rate;
  String unit;
  String cap;
  String conditions;
  List<String> additionalCategoryIds;
  String? validFrom;
  String? validThrough;

  void changeCategory(String? value) {
    if (categoryId == value) return;
    categoryId = value;
    additionalCategoryIds = [];
    validFrom = null;
    validThrough = null;
  }
}

class _BenefitDraft {
  _BenefitDraft({
    required this.title,
    required this.description,
    required this.categoryId,
  });

  factory _BenefitDraft.fromJson(Json benefit) => _BenefitDraft(
    title: label(benefit['title'], ''),
    description: label(benefit['description'], ''),
    categoryId: benefit['categoryId'] is String
        ? benefit['categoryId'] as String
        : null,
  );

  factory _BenefitDraft.blank() =>
      _BenefitDraft(title: '', description: '', categoryId: null);

  final Object key = Object();
  String title;
  String description;
  String? categoryId;
}

class _CardBenefitEditor extends StatefulWidget {
  const _CardBenefitEditor({
    required this.client,
    required this.card,
    required this.product,
    required this.categories,
    required this.onSaved,
  });

  final GreenhouseClient client;
  final Json card;
  final Json? product;
  final List<Json> categories;
  final Future<void> Function() onSaved;

  @override
  State<_CardBenefitEditor> createState() => _CardBenefitEditorState();
}

class _CardBenefitEditorState extends State<_CardBenefitEditor> {
  final form = GlobalKey<FormState>();
  late final List<_RewardDraft> rewards;
  late final List<_BenefitDraft> benefits;
  String? validationMessage;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final overrides = object(widget.card['benefitOverride']);
    final rewardRows = hasBenefitOverride(widget.card)
        ? objects(overrides['rewards'])
        : objects(widget.product?['rewards']);
    final benefitRows = hasBenefitOverride(widget.card)
        ? objects(overrides['benefits'])
        : objects(widget.product?['benefits']);
    rewards = rewardRows.map(_RewardDraft.fromJson).toList();
    benefits = benefitRows.map(_BenefitDraft.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit card benefits'),
      actions: [
        TextButton(onPressed: busy ? null : _save, child: const Text('Save')),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        child: FilledButton.icon(
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save card benefits'),
        ),
      ),
    ),
    body: Form(
      key: form,
      child: FinanceList(
        children: [
          Panel(
            child: Text(
              'These rewards and perks replace the catalog details for this card in your household.',
            ),
          ),
          if (validationMessage != null) Panel(child: Text(validationMessage!)),
          const SectionTitle('Rewards'),
          for (final row in rewards) ...[
            _rewardEditor(row),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: busy || rewards.length >= 100
                ? null
                : () => setState(() => rewards.add(_RewardDraft.blank())),
            icon: const Icon(Icons.add),
            label: const Text('Add reward'),
          ),
          const SectionTitle('Other perks'),
          for (final row in benefits) ...[
            _benefitEditor(row),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: busy || benefits.length >= 100
                ? null
                : () => setState(() => benefits.add(_BenefitDraft.blank())),
            icon: const Icon(Icons.add),
            label: const Text('Add perk'),
          ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    ),
  );

  Widget _rewardEditor(_RewardDraft row) => Panel(
    key: ValueKey(row.key),
    padding: const EdgeInsets.all(12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Remove reward',
          onPressed: busy ? null : () => setState(() => rewards.remove(row)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reward'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey(('rate', row.key)),
                      initialValue: row.rate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: row.isNew ? 'Rate (required)' : 'Rate',
                      ),
                      onChanged: (value) => row.rate = value,
                      validator: (value) {
                        final rate = num.tryParse(value?.trim() ?? '');
                        return rate == null ||
                                !rate.isFinite ||
                                rate < 0 ||
                                rate > 1000
                            ? 'Enter a number from 0 to 1,000'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: row.unit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: const [
                        DropdownMenuItem(value: 'percent', child: Text('%')),
                        DropdownMenuItem(value: 'x', child: Text('x')),
                      ],
                      onChanged: busy
                          ? null
                          : (value) =>
                                setState(() => row.unit = value ?? 'percent'),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: row.categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final category in widget.categories)
                    DropdownMenuItem(
                      value: label(category['id']),
                      child: Text(label(category['label'])),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => row.changeCategory(value)),
                validator: (value) =>
                    value == null ? 'Choose a category' : null,
              ),
              TextFormField(
                key: ValueKey(('cap', row.key)),
                initialValue: row.cap,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Cap (optional)'),
                onChanged: (value) => row.cap = value,
              ),
              TextFormField(
                key: ValueKey(('conditions', row.key)),
                initialValue: row.conditions,
                maxLength: 8000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Conditions (optional)',
                ),
                onChanged: (value) => row.conditions = value,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _benefitEditor(_BenefitDraft row) => Panel(
    key: ValueKey(row.key),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Remove perk',
          onPressed: busy ? null : () => setState(() => benefits.remove(row)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        TextFormField(
          key: ValueKey(('benefit-title', row.key)),
          initialValue: row.title,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Perk title'),
          onChanged: (value) => row.title = value,
          validator: (value) => value?.trim().isEmpty == true
              ? 'Enter a title or remove this perk'
              : null,
        ),
        TextFormField(
          key: ValueKey(('benefit-description', row.key)),
          initialValue: row.description,
          maxLength: 8000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Perk details'),
          onChanged: (value) => row.description = value,
          validator: (value) => value?.trim().isEmpty == true
              ? 'Enter details or remove this perk'
              : null,
        ),
        DropdownButtonFormField<String?>(
          initialValue: row.categoryId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category (optional)'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Any category'),
            ),
            for (final category in widget.categories)
              DropdownMenuItem<String?>(
                value: label(category['id']),
                child: Text(label(category['label'])),
              ),
          ],
          onChanged: busy
              ? null
              : (value) => setState(() => row.categoryId = value),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    if (busy) return;
    final validRewards = rewards.every((row) {
      final rate = num.tryParse(row.rate.trim());
      return row.categoryId != null &&
          rate != null &&
          rate.isFinite &&
          rate >= 0 &&
          rate <= 1000;
    });
    final validBenefits = benefits.every(
      (row) => row.title.trim().isNotEmpty && row.description.trim().isNotEmpty,
    );
    if (!validRewards || !validBenefits) {
      form.currentState?.validate();
      final message =
          rewards.any((row) {
            final rate = num.tryParse(row.rate.trim());
            return rate == null || !rate.isFinite || rate < 0 || rate > 1000;
          })
          ? 'Enter a valid rate for each reward row, or remove a blank row.'
          : rewards.any((row) => row.categoryId == null)
          ? 'Choose a category for each reward row, or remove a blank row.'
          : 'Enter a title and details for each perk, or remove a blank row.';
      setState(() {
        validationMessage = message;
      });
      showMessage(context, message);
      return;
    }
    final override = {
      'rewards': [
        for (final row in rewards)
          {
            'categoryId': row.categoryId,
            if (row.additionalCategoryIds.isNotEmpty)
              'additionalCategoryIds': row.additionalCategoryIds,
            'rate': num.parse(row.rate.trim()),
            'unit': row.unit,
            'cap': row.cap.trim().isEmpty ? null : row.cap.trim(),
            'conditions': row.conditions.trim().isEmpty
                ? null
                : row.conditions.trim(),
            if (row.validFrom != null) 'validFrom': row.validFrom,
            if (row.validThrough != null) 'validThrough': row.validThrough,
          },
      ],
      'benefits': [
        for (final row in benefits)
          {
            'title': row.title.trim(),
            'description': row.description.trim(),
            'categoryId': row.categoryId,
          },
      ],
    };
    setState(() {
      busy = true;
      validationMessage = null;
    });
    try {
      await widget.client.request(
        '/cards/wallet/${endpoint(widget.card['id'])}/benefits',
        method: 'PUT',
        body: {'override': override},
      );
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products});
  final List<Json> products;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final products = widget.products
        .where(
          (item) => '${label(item['name'])} ${label(item['issuer'])}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a card',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search verified products',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final item = products[index];
                    return ListTile(
                      title: Text(label(item['name'])),
                      subtitle: Text(
                        [
                          label(item['issuer']),
                          ?productAvailabilityLabel(item),
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
              if (products.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'No matching verified products. Linked cards can remain unidentified.',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
