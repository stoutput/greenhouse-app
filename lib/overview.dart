import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';
import 'transactions.dart';

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
          _NetWorth(client, picture, object(data[0]['freshness'])),
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
  const _NetWorth(this.client, this.picture, this.freshness);
  final GreenhouseClient client;
  final Json picture;
  final Json freshness;

  @override
  State<_NetWorth> createState() => _NetWorthState();
}

class _NetWorthState extends State<_NetWorth> {
  String side = 'assets';

  @override
  void initState() {
    super.initState();
    final categories = objects(
      object(widget.picture['breakdown'])['categories'],
    );
    final hasAssets = categories.any(
      (category) => category['side'] == 'assets',
    );
    if (!hasAssets &&
        categories.any((category) => category['side'] == 'liabilities')) {
      side = 'liabilities';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final picture = widget.picture;
    final freshness = widget.freshness;
    final history = objects(picture['history']);
    final points = [
      for (final point in history)
        if (minor(point['netWorth']) case final value?) value.toDouble(),
    ];
    final breakdown = object(picture['breakdown']);
    final categories = objects(breakdown['categories']);
    final hasBreakdown = categories.isNotEmpty;
    final shown = categories
        .where((category) => category['side'] == side)
        .toList();
    final color = side == 'assets' ? colors.primary : colors.error;
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
          if (points.length >= 2) ...[
            const SizedBox(height: 9),
            BalanceChart(points),
            Row(
              children: [
                Expanded(
                  child: Text(
                    humanDate('${history.first['month']}-01'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    humanDate('${history.last['month']}-01'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (hasBreakdown) ...[
            const SizedBox(height: 16),
            _SideTabs(
              side: side,
              onChanged: (value) => setState(() => side = value),
            ),
            const SizedBox(height: 14),
            Text(
              side == 'assets' ? 'Total assets' : 'Total liabilities',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(money(breakdown[side]), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No ${side == 'assets' ? 'asset' : 'liability'} categories with balances.',
                ),
              ),
            for (final category in shown)
              _CategoryRow(
                category: category,
                color: color,
                onTap: () => _openCategory(context, category),
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
          if (freshness['asOf'] != null) ...[
            const SizedBox(height: 12),
            Text(
              'Balances as of ${humanDate(freshness['asOf'])}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openCategory(BuildContext context, Json category) async {
    final ids =
        (category['accountIds'] as List?)?.whereType<String>().toSet() ??
        const <String>{};
    final height = MediaQuery.sizeOf(context).height * .7;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: height,
        child: _CategoryAccountsSheet(
          client: widget.client,
          title: label(category['label'], 'Accounts'),
          accountIds: ids,
        ),
      ),
    );
  }
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({required this.side, required this.onChanged});
  final String side;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget tab(String value, String text) {
      final selected = side == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color: selected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: selected ? null : () => onChanged(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? colors.onPrimary : colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          tab('assets', 'Assets'),
          const SizedBox(width: 4),
          tab('liabilities', 'Liabilities'),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.color,
    required this.onTap,
  });
  final Json category;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = objects(category['history']);
    final points = [
      for (final entry in history)
        if (DateTime.tryParse(label(entry['date'], '')) case final date?)
          TrendPoint(date, minor(entry['total'])?.toDouble()),
    ]..sort((a, b) => a.date.compareTo(b.date));
    final known = points.where((point) => point.value != null).length;
    final estimated = history.any((entry) => entry['estimated'] == true);
    final title = label(category['label'], words(category['id']));
    final total = category['total'];
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == null ? 'Unavailable' : money(total),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (known < 2)
                      Text(
                        known == 0 ? 'No recorded history' : 'Limited history',
                        style: theme.textTheme.bodySmall,
                      ),
                    if (estimated)
                      Text(
                        'Includes estimates',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TrendChart(
                  points,
                  color: color,
                  label:
                      '$title trend, $known recorded ${known == 1 ? 'point' : 'points'}${estimated ? ', includes estimates' : ''}',
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryAccountsSheet extends StatefulWidget {
  const _CategoryAccountsSheet({
    required this.client,
    required this.title,
    required this.accountIds,
  });
  final GreenhouseClient client;
  final String title;
  final Set<String> accountIds;

  @override
  State<_CategoryAccountsSheet> createState() => _CategoryAccountsSheetState();
}

class _CategoryAccountsSheetState extends State<_CategoryAccountsSheet> {
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleLarge),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Json>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          errorMessage(snapshot.error!),
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: () => setState(() => future = _load()),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No open accounts in this category.'),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 56, endIndent: 16),
                itemBuilder: (context, index) =>
                    _accountTile(context, rows[index]),
              );
            },
          ),
        ),
      ],
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
        navigator.pop();
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
