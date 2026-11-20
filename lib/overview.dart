import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';
import 'transactions.dart';
import 'segmented_bar.dart';

class Overview extends StatelessWidget {
  const Overview({required this.client, required this.onActivity, super.key});
  final GreenhouseClient client;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return LoadScreen<List<Json>>(
      load: () => Future.wait([
        client.request('/financial-picture'),
        client.request('/months/${isoMonth(now)}/summary'),
        client.request('/transactions', query: {'limit': '5'}),
      ]),
      content: (data, reload) {
        final picture = object(data[0]['data']);
        final summary = object(data[1]['data']);
        final rows = objects(data[2]['items']);
        return [
          Eyebrow(DateFormat('MMMM yyyy').format(now)),
          const SizedBox(height: 6),
          Text(
            'Your financial picture',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          _NetWorth(client, picture),
          const SectionTitle('Cash flow'),
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Metric('Income', money(summary['income']))),
                Expanded(
                  child: Metric(
                    'Posted spending',
                    money(summary['postedSpending']),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(
            'Recent activity',
            action: TextButton(
              onPressed: onActivity,
              child: const Text('View all'),
            ),
          ),
          if (rows.isEmpty) const Panel(child: Text('No transactions yet.')),
          if (rows.isNotEmpty)
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final row in rows)
                    TransactionTile(
                      row: row,
                      onTap: () async {
                        if (await openTransaction(context, client, row)) {
                          await reload();
                        }
                      },
                    ),
                ],
              ),
            ),
        ];
      },
    );
  }
}

class _NetWorth extends StatefulWidget {
  const _NetWorth(this.client, this.picture);
  final GreenhouseClient client;
  final Json picture;

  @override
  State<_NetWorth> createState() => _NetWorthState();
}

class _NetWorthState extends State<_NetWorth> {
  String? side;
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final picture = widget.picture;
    final daily = picture['dailyHistory'] is List;
    final history = objects(picture[daily ? 'dailyHistory' : 'history']);
    final points = [
      for (final point in history)
        if (DateTime.tryParse(
              label(daily ? point['date'] : '${point['month']}-01', ''),
            )
            case final date?)
          TrendPoint(date, minor(point['netWorth'])?.toDouble()),
    ];
    final hasHistory = points.any((point) => point.value != null);
    final breakdown = object(picture['breakdown']);
    final categories = objects(breakdown['categories']);
    final hasBreakdown = picture['breakdown'] != null;
    final shown = categories
        .where((category) => category['side'] == side)
        .toList();
    final selected = shown
        .where((category) => category['id'] == selectedId)
        .firstOrNull;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              colors.primary.withValues(alpha: .16),
              colors.surfaceContainer,
            ),
            colors.surfaceContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Net worth'),
          const SizedBox(height: 6),
          Text(money(picture['netWorth']), style: theme.textTheme.displaySmall),
          if (hasHistory) ...[
            const SizedBox(height: 9),
            TrendChart(
              points,
              color: colors.primary,
              label: 'Net worth history',
              height: 82,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat.yMMMd().format(points.first.date),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (points.first.date != points.last.date)
                  Expanded(
                    child: Text(
                      DateFormat.yMMMd().format(points.last.date),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
          if (hasBreakdown) ...[
            const SizedBox(height: 16),
            if (side != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  side = null;
                  selectedId = null;
                }),
                icon: const Icon(Icons.arrow_back),
                label: Semantics(
                  label: 'Back to assets and liabilities',
                  child: Text(side == 'assets' ? 'Assets' : 'Liabilities'),
                ),
              ),
            SegmentedBar(
              selectedId: selectedId,
              segments:
                  (side == null
                          ? [
                              {
                                'id': 'assets',
                                'label': 'Assets',
                                'total': breakdown['assets'],
                              },
                              {
                                'id': 'liabilities',
                                'label': 'Liabilities',
                                'total': breakdown['liabilities'],
                              },
                            ]
                          : shown)
                      .map(
                        (segment) => BalanceSegment(
                          id: label(segment['id'], ''),
                          label: label(segment['label'], ''),
                          value: minor(segment['total']),
                          amount: money(segment['total']),
                        ),
                      )
                      .toList(),
              onSelect: (id) => setState(() {
                if (side == null) {
                  side = id;
                } else {
                  selectedId = selectedId == id ? null : id;
                }
              }),
            ),
            if (side != null && shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No accounts'),
              ),
            if (selected != null)
              _CategoryAccounts(
                key: ValueKey(selected['id']),
                client: widget.client,
                accountIds:
                    (selected['accountIds'] as List?)
                        ?.whereType<String>()
                        .toSet() ??
                    const <String>{},
              ),
          ] else ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Metric('Cash', money(picture['cash']))),
                Expanded(
                  child: Metric('Investments', money(picture['investments'])),
                ),
                Expanded(child: Metric('Debt', money(picture['debt']))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryAccounts extends StatefulWidget {
  const _CategoryAccounts({
    required this.client,
    required this.accountIds,
    super.key,
  });
  final GreenhouseClient client;
  final Set<String> accountIds;

  @override
  State<_CategoryAccounts> createState() => _CategoryAccountsState();
}

class _CategoryAccountsState extends State<_CategoryAccounts> {
  late Future<List<Json>> future = _load();

  Future<List<Json>> _load() async {
    final data = await widget.client.request('/accounts');
    return [
      for (final row in objects(data['items']))
        if (object(row['account'])['isClosed'] != true &&
            widget.accountIds.contains(label(object(row['account'])['id'], '')))
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Json>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(() => future = _load()),
            child: const Text('Retry accounts'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) return const Text('No open accounts');
        return Column(
          children: [for (final row in rows) _accountTile(context, row)],
        );
      },
    );
  }

  Widget _accountTile(BuildContext context, Json row) {
    final account = object(row['account']);
    final kind = label(account['kind'], label(row['kind'], ''));
    final unknownTypes =
        (row['unknownBalanceTypes'] as List?)?.whereType<String>().toSet() ??
        const <String>{};
    final balance = _preferredBalance(
      objects(row['balances']),
      kind,
      unknownTypes,
    );
    final subtitle = [
      label(row['connectionName'], ''),
      if (account['mask'] != null) '••${account['mask']}',
    ].where((part) => part.isNotEmpty).join(' · ');
    return ListTile(
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: Text(label(account['displayName'], 'Account')),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Text(
        balance == null || minor(balance['amount']) == null
            ? 'Unavailable'
            : moneyWithCurrency(balance['amount']),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      onTap: () {
        final navigator = Navigator.of(context);
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Account activity')),
              body: Activity(
                client: widget.client,
                initialQuery: {'accountIds': label(account['id'], '')},
              ),
            ),
          ),
        );
      },
    );
  }

  /// A partial account read can include older observations: pick by timestamp.
  /// An unknown latest value stays unknown. The server omits null observations,
  /// so `unknownBalanceTypes` identifies which latest types are unavailable;
  /// only fall back from investment-value to current when no investment-value
  /// observation is known at all.
  Json? _preferredBalance(
    List<Json> balances,
    String kind,
    Set<String> unknownTypes,
  ) {
    Json? latest(String type) {
      if (unknownTypes.contains(type)) return null;
      final candidates =
          balances.where((balance) => balance['balanceType'] == type).toList()
            ..sort(
              (a, b) => label(
                b['observedAt'],
                '',
              ).compareTo(label(a['observedAt'], '')),
            );
      return candidates.firstOrNull;
    }

    final preferred = kind == 'investment' ? 'investment-value' : 'current';
    if (unknownTypes.contains(preferred)) return null;
    return latest(preferred) ??
        (kind == 'investment' ? latest('current') : null);
  }
}
