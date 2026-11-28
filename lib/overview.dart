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
          _CashFlow(summary: summary, month: now),
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

class _CashFlow extends StatelessWidget {
  const _CashFlow({required this.summary, required this.month});
  final Json summary;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final income = minor(summary['income']);
    final expense = minor(summary['postedSpending']);
    final sameCurrency =
        object(summary['income'])['currency'] ==
        object(summary['postedSpending'])['currency'];
    final pending = minor(summary['pendingForecast']);
    Widget metric(String title, Object? value, IconData icon) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(title, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 5),
        Text(money(value), style: theme.textTheme.titleMedium),
      ],
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.yMMMM().format(month),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Posted transactions · transfers excluded',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: metric(
                  'Income',
                  summary['income'],
                  Icons.south_east_rounded,
                ),
              ),
              Expanded(
                child: metric(
                  'Expenses',
                  summary['postedSpending'],
                  Icons.north_east_rounded,
                ),
              ),
            ],
          ),
          if (income != null && expense != null && sameCurrency) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Net cash flow',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  money({
                    'amount': (income - expense).toString(),
                    'currency': object(summary['income'])['currency'],
                  }),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ],
          if (pending != null && pending > BigInt.zero) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pending expenses',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  money(summary['pendingForecast']),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
          if (income == null &&
              summary['incomeUnavailableReason'] is String) ...[
            const SizedBox(height: 8),
            Text(
              summary['incomeUnavailableReason'] as String,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
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

List<TrendPoint> _sideHistory(List<Json> categories, String side) {
  final selected = categories
      .where((category) => category['side'] == side)
      .toList();
  final dates = <String>{
    for (final category in selected)
      for (final point in objects(category['history']))
        if (point['date'] is String) point['date'] as String,
  }.toList()..sort();
  final latest = <String, Json>{};
  return [
    for (final date in dates)
      if (DateTime.tryParse(date) case final parsed?)
        () {
          final todays = <String, Json>{};
          for (final category in selected) {
            final id = label(category['id'], '');
            for (final point in objects(category['history'])) {
              if (point['date'] == date) {
                todays[id] = point;
                if (point['estimated'] != true) latest[id] = point;
                break;
              }
            }
          }
          final values = [
            for (final category in selected)
              minor(
                (todays[label(category['id'], '')] ??
                    latest[label(category['id'], '')])?['total'],
              ),
          ];
          final known = values.whereType<BigInt>();
          return TrendPoint(
            parsed,
            known.isEmpty
                ? null
                : known
                      .fold<BigInt>(BigInt.zero, (sum, value) => sum + value)
                      .toDouble(),
          );
        }(),
  ];
}

class _NetWorthState extends State<_NetWorth> {
  String? side;
  String? selectedId;
  double horizontalDrag = 0;

  void _showSide(String? next) {
    setState(() {
      side = next;
      selectedId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final picture = widget.picture;
    final daily = picture['dailyHistory'] is List;
    final history = objects(picture[daily ? 'dailyHistory' : 'history']);
    final netWorthPoints = [
      for (final point in history)
        if (DateTime.tryParse(
              label(daily ? point['date'] : '${point['month']}-01', ''),
            )
            case final date?)
          TrendPoint(date, minor(point['netWorth'])?.toDouble()),
    ];
    final breakdown = object(picture['breakdown']);
    final categories = objects(breakdown['categories']);
    final hasBreakdown = picture['breakdown'] != null;
    final points = side == null
        ? netWorthPoints
        : _sideHistory(categories, side!);
    final hasHistory = points.any((point) => point.value != null);
    final shown = categories
        .where((category) => category['side'] == side)
        .toList();
    final selected = shown
        .where((category) => category['id'] == selectedId)
        .firstOrNull;
    return GestureDetector(
      key: const ValueKey('growth-trajectory'),
      onHorizontalDragStart: (_) => horizontalDrag = 0,
      onHorizontalDragUpdate: (details) => horizontalDrag += details.delta.dx,
      onHorizontalDragEnd: (_) {
        if (!hasBreakdown || horizontalDrag.abs() < 45) return;
        final panels = <String?>['assets', null, 'liabilities'];
        final index = panels.indexOf(side);
        _showSide(panels[(index + (horizontalDrag < 0 ? 1 : -1)).clamp(0, 2)]);
      },
      child: Container(
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
            Eyebrow(side == null ? 'Net worth' : 'Net balance'),
            const SizedBox(height: 6),
            Text(
              money(side == null ? picture['netWorth'] : breakdown[side]),
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 9),
            if (hasHistory)
              TrendChart(
                points,
                color: colors.primary,
                label: side == null
                    ? 'Net worth history'
                    : '${side == 'assets' ? 'Assets' : 'Liabilities'} history',
                height: 82,
              )
            else
              const SizedBox(
                height: 82,
                child: Center(
                  child: Text(
                    'Your trend will appear as balance history builds',
                  ),
                ),
              ),
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  if (points.isNotEmpty)
                    Expanded(
                      child: Text(
                        DateFormat.yMMMd().format(points.first.date),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  if (points.length > 1 &&
                      points.first.date != points.last.date)
                    Expanded(
                      child: Text(
                        DateFormat.yMMMd().format(points.last.date),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            if (hasBreakdown) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: side == null
                    ? null
                    : TextButton.icon(
                        onPressed: () => _showSide(null),
                        icon: const Icon(Icons.arrow_back),
                        label: Semantics(
                          label: 'Back to assets and liabilities',
                          child: Text(
                            side == 'assets' ? 'Assets' : 'Liabilities',
                          ),
                        ),
                      ),
              ),
              IndexedStack(
                index: <String?>['assets', null, 'liabilities'].indexOf(side),
                children: [
                  for (final panel in <String?>['assets', null, 'liabilities'])
                    SegmentedBar(
                      selectedId: panel == side ? selectedId : null,
                      segments:
                          (panel == null
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
                                  : categories.where(
                                      (category) => category['side'] == panel,
                                    ))
                              .map(
                                (segment) => BalanceSegment(
                                  id: label(segment['id'], ''),
                                  label: label(segment['label'], ''),
                                  value: minor(segment['total']),
                                  amount: money(segment['total']),
                                ),
                              )
                              .toList(),
                      onSelect: (id) {
                        if (panel == null) {
                          _showSide(id);
                        } else {
                          setState(
                            () => selectedId = selectedId == id ? null : id,
                          );
                        }
                      },
                    ),
                ],
              ),
              SizedBox(
                height: 36,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final panel in <String?>[
                      'assets',
                      null,
                      'liabilities',
                    ])
                      Semantics(
                        button: true,
                        selected: side == panel,
                        label: panel == null
                            ? 'Combined balances'
                            : panel == 'assets'
                            ? 'Asset categories'
                            : 'Liability categories',
                        child: InkWell(
                          onTap: () => _showSide(panel),
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: Center(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: side == panel
                                      ? colors.primary
                                      : colors.onSurfaceVariant.withValues(
                                          alpha: .4,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
