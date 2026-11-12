import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cards.dart';
import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';
import 'transactions.dart';

class Accounts extends StatelessWidget {
  const Accounts({required this.client, super.key});
  final GreenhouseClient client;

  @override
  Widget build(BuildContext context) => LoadScreen<(Json, Json, Json?)>(
    load: () async {
      final data = await Future.wait<Json?>([
        client.request('/accounts'),
        client.request('/connections'),
        _loadCardsCatalog(client),
      ]);
      return (
        object(data[0]),
        object(data[1]),
        data[2] is Json ? data[2] as Json : null,
      );
    },
    content: (data, reload) => [
      _AccountsContent(
        client: client,
        accounts: objects(data.$1['items']),
        connections: objects(data.$2['items']),
        cards: data.$3,
        onReload: reload,
      ),
    ],
  );
}

Future<Json?> _loadCardsCatalog(GreenhouseClient client) async {
  try {
    return await client.request('/cards');
  } catch (_) {
    // Cards may be disabled or unavailable on older GreenHouse servers.
    return null;
  }
}

class _AccountsContent extends StatefulWidget {
  const _AccountsContent({
    required this.client,
    required this.accounts,
    required this.connections,
    required this.cards,
    required this.onReload,
  });

  final GreenhouseClient client;
  final List<Json> accounts;
  final List<Json> connections;
  final Json? cards;
  final Future<void> Function() onReload;

  @override
  State<_AccountsContent> createState() => _AccountsContentState();
}

class _AccountsContentState extends State<_AccountsContent>
    with WidgetsBindingObserver {
  Set<String> seenAccountIds = {};
  Set<String> dismissedPromptIds = {};
  bool historyLoaded = false;
  bool processingNewAccounts = false;

  String? get seenKey => widget.client.identity?.preferenceKey(
    'accounts_seen_ids',
    widget.client.origin,
  );
  String? get dismissedKey => widget.client.identity?.preferenceKey(
    'accounts_card_match_dismissed_ids',
    widget.client.origin,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeHistory();
  }

  @override
  void didUpdateWidget(covariant _AccountsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (historyLoaded) unawaited(_findNewCardAccounts());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.onReload());
  }

  Set<String> _accountIds() =>
      objects(widget.accounts.map((row) => row['account']).toList())
          .map((account) => label(account['id'], ''))
          .where((id) => id.isNotEmpty)
          .toSet();

  Future<void> _initializeHistory() async {
    final key = seenKey;
    final ignoredKey = dismissedKey;
    if (key == null || ignoredKey == null) {
      seenAccountIds = _accountIds();
      historyLoaded = true;
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getStringList(key);
      dismissedPromptIds = (preferences.getStringList(ignoredKey) ?? [])
          .toSet();
      if (saved == null) {
        // Existing accounts on first use are a baseline, not new discoveries.
        seenAccountIds = _accountIds();
        await preferences.setStringList(key, seenAccountIds.toList());
      } else {
        seenAccountIds = saved.toSet();
      }
    } catch (_) {
      // If local history cannot be read, do not prompt for all current accounts.
      seenAccountIds = _accountIds();
    }
    if (!mounted) return;
    setState(() => historyLoaded = true);
    unawaited(_findNewCardAccounts());
  }

  Future<void> _findNewCardAccounts() async {
    if (!historyLoaded || processingNewAccounts) return;
    processingNewAccounts = true;
    try {
      final current = _accountIds();
      final newIds = current.difference(seenAccountIds).toList();
      if (newIds.isEmpty) return;
      seenAccountIds.addAll(current);
      await _persistIds(seenKey, seenAccountIds);

      final catalog = widget.cards;
      final enabled =
          catalog?['enabled'] == true &&
          object(catalog?['navigationPage']).isNotEmpty;
      final products = enabled ? objects(catalog?['products']) : <Json>[];
      final wallet = enabled ? objects(catalog?['wallet']) : <Json>[];
      for (final id in newIds) {
        if (dismissedPromptIds.contains(id)) continue;
        final card = wallet
            .where(
              (candidate) =>
                  candidate['kind'] == 'linked' &&
                  candidate['accountId'] == id &&
                  label(candidate['productId'], '').isEmpty,
            )
            .firstOrNull;
        if (card == null || !_hasMeaningfulCandidates(card, products)) continue;
        dismissedPromptIds.add(id);
        await _persistIds(dismissedKey, dismissedPromptIds);
        if (mounted) await _showNewCardPrompt(card, products);
      }
    } catch (_) {
      // A discovery prompt must not block ordinary account browsing.
    } finally {
      processingNewAccounts = false;
      if (mounted && _accountIds().difference(seenAccountIds).isNotEmpty) {
        unawaited(_findNewCardAccounts());
      }
    }
  }

  bool _hasMeaningfulCandidates(Json card, List<Json> products) {
    final productIds = products.map((item) => item['id']).toSet();
    if (productIds.contains(card['suggestedProductId'])) return true;
    final candidates = card['candidateProductIds'];
    return candidates is List && candidates.any(productIds.contains);
  }

  Future<void> _showNewCardPrompt(Json card, List<Json> products) async {
    final suggested = products
        .where((item) => item['id'] == card['suggestedProductId'])
        .firstOrNull;
    final candidates = objects(
      card['candidateProductIds'] is List
          ? products
                .where(
                  (item) => (card['candidateProductIds'] as List).contains(
                    item['id'],
                  ),
                )
                .toList()
          : [],
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialog) => AlertDialog(
        title: const Text('New card account found'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label(
                card['importedName'],
                label(card['displayName'], 'Card account'),
              ),
            ),
            const SizedBox(height: 8),
            if (suggested != null)
              Text('Suggested match: ${label(suggested['name'])}')
            else if (candidates.isNotEmpty)
              Text(
                'Possible matches: ${candidates.map((item) => label(item['name'])).join(', ')}',
              ),
            if (suggested != null &&
                productAvailabilityLabel(suggested) != null)
              Text(productAvailabilityLabel(suggested)!),
            if (suggested != null &&
                label(suggested['sourceNotes'], '').isNotEmpty)
              Text(label(suggested['sourceNotes'])),
            const SizedBox(height: 8),
            const Text(
              'Review the card match in Accounts. No product is selected until you confirm it.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Got it'),
          ),
          if (suggested != null &&
              widget.client.permissions.canManageSharedFinances)
            FilledButton(
              onPressed: () async {
                if (!await confirmCardProductChange(dialog, card) || !mounted) {
                  return;
                }
                try {
                  await widget.client.request(
                    '/cards/wallet/${endpoint(card['id'])}',
                    method: 'PUT',
                    body: {
                      'productId': suggested['id'],
                      'openedOn': card['openedOn'],
                    },
                  );
                  if (dialog.mounted) Navigator.pop(dialog);
                  if (mounted) await widget.onReload();
                } catch (e) {
                  if (dialog.mounted) showMessage(dialog, errorMessage(e));
                }
              },
              child: const Text('Confirm match'),
            ),
        ],
      ),
    );
  }

  Future<void> _persistIds(String? key, Set<String> ids) async {
    if (key == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(key, ids.toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    final enabled =
        cards?['enabled'] == true &&
        object(cards?['navigationPage']).isNotEmpty;
    final products = enabled ? objects(cards?['products']) : <Json>[];
    final wallet = enabled ? objects(cards?['wallet']) : <Json>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Linked and manual'),
        const SectionTitle('Your accounts'),
        if (widget.accounts.isEmpty)
          const Panel(
            child: Text('Accounts added to this instance will appear here.'),
          ),
        for (final row in widget.accounts) ...[
          Builder(
            builder: (context) {
              final accountId = label(object(row['account'])['id'], '');
              final linkedCard = wallet
                  .where(
                    (card) =>
                        card['kind'] == 'linked' &&
                        card['accountId'] == accountId &&
                        label(card['productId'], '').isEmpty,
                  )
                  .firstOrNull;
              return Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _AccountTile(
                      row: row,
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => _AccountDetail(
                              client: widget.client,
                              summary: row,
                              linkedCard: linkedCard,
                              products: products,
                            ),
                          ),
                        );
                        if (context.mounted) await widget.onReload();
                      },
                    ),
                    if (linkedCard != null) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: CardProductMatcher(
                          key: ValueKey((
                            linkedCard['id'],
                            linkedCard['productId'],
                            linkedCard.hashCode,
                          )),
                          client: widget.client,
                          walletCard: linkedCard,
                          products: products,
                          onUpdated: widget.onReload,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        const SectionTitle('Connections'),
        if (widget.connections.isEmpty)
          const Panel(child: Text('No bank connections.')),
        if (widget.connections.isNotEmpty)
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final connection in widget.connections)
                  ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: Text(label(connection['displayName'], 'Connection')),
                    subtitle: Text(
                      [
                        connection['isPaused'] == true
                            ? 'Paused'
                            : words(connection['health']),
                        if (connection['lastSuccessfulSyncAt'] != null)
                          'Synced ${humanDate(connection['lastSuccessfulSyncAt'])}',
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.row, required this.onTap});
  final Json row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final account = object(row['account']);
    final balances = objects(row['balances']);
    final preferred = account['kind'] == 'investment'
        ? 'investment-value'
        : 'current';
    final balance =
        balances
            .where((item) => item['balanceType'] == preferred)
            .firstOrNull ??
        balances.where((item) => item['balanceType'] == 'current').firstOrNull;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(label(account['displayName'], 'Account')),
        subtitle: Text(
          [
            label(row['connectionName'], words(account['kind'])),
            if (account['mask'] != null) '••${account['mask']}',
          ].join(' · '),
        ),
        trailing: Text(
          money(balance?['amount']),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({
    required this.client,
    required this.summary,
    required this.linkedCard,
    required this.products,
  });
  final GreenhouseClient client;
  final Json summary;
  final Json? linkedCard;
  final List<Json> products;

  @override
  Widget build(BuildContext context) {
    final account = object(summary['account']);
    final id = endpoint(account['id']);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: LoadScreen<Json>(
        load: () => client.request('/accounts/$id'),
        content: (data, reload) {
          final item = object(data['account']);
          return [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(words(item['kind'])),
                  const SizedBox(height: 7),
                  Text(
                    label(item['displayName'], 'Account'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(label(data['connectionName'], 'Manual account')),
                ],
              ),
            ),
            if (linkedCard != null) ...[
              Panel(
                child: CardProductMatcher(
                  client: client,
                  walletCard: linkedCard!,
                  products: products,
                  onUpdated: reload,
                ),
              ),
            ],
            const SectionTitle('Reported balances'),
            if (objects(data['balances']).isEmpty)
              const Panel(child: Text('No balances available.')),
            for (final balance in objects(data['balances']))
              ListTile(
                title: Text(words(balance['balanceType'])),
                subtitle: Text('Observed ${humanDate(balance['observedAt'])}'),
                trailing: Text(money(balance['amount'])),
              ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Account activity')),
                    body: Activity(
                      client: client,
                      initialQuery: {'accountIds': label(item['id'])},
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View transactions'),
            ),
            if (client.permissions.canManageSharedFinances)
              OutlinedButton(
                onPressed: () async {
                  final name = await _requestName(
                    context,
                    label(item['displayName'], ''),
                  );
                  if (name == null || !context.mounted) return;
                  try {
                    await client.request(
                      '/accounts/$id/name',
                      method: 'PATCH',
                      body: {
                        'displayName': name,
                        'expectedRevision': item['revision'],
                      },
                    );
                    if (context.mounted) await reload();
                  } catch (e) {
                    if (context.mounted) showMessage(context, errorMessage(e));
                  }
                },
                child: const Text('Rename account'),
              ),
          ];
        },
      ),
    );
  }
}

Future<String?> _requestName(BuildContext context, String initial) async {
  var name = initial;
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Rename account'),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        maxLength: 200,
        onChanged: (value) => name = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (name.trim().isNotEmpty) Navigator.pop(dialog, name.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
