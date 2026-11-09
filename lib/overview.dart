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
          _NetWorth(picture, object(data[0]['freshness'])),
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

class _NetWorth extends StatelessWidget {
  const _NetWorth(this.picture, this.freshness);
  final Json picture;
  final Json freshness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final history = objects(picture['history']);
    final points = [
      for (final point in history)
        if (minor(point['netWorth']) case final value?) value.toDouble(),
    ];
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  humanDate('${history.first['month']}-01'),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  humanDate('${history.last['month']}-01'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
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
}
