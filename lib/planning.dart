import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';

class Planning extends StatefulWidget {
  const Planning({required this.client, super.key});
  final GreenhouseClient client;

  @override
  State<Planning> createState() => _PlanningState();
}

class _PlanningState extends State<Planning> {
  DateTime month = DateTime.now();
  String? selected;

  @override
  Widget build(BuildContext context) => LoadScreen<(List<Json>, Json?)>(
    key: ValueKey((isoMonth(month), selected)),
    load: () async {
      final plans = objects(
        (await widget.client.request('/budget-plans'))['items'],
      );
      final plan =
          plans.where((item) => item['id'] == selected).firstOrNull ??
          plans.firstOrNull;
      if (plan == null ||
          label(plan['startMonth']).compareTo(isoMonth(month)) > 0) {
        return (plans, null);
      }
      final id = endpoint(plan['id']);
      final data = await widget.client.request(
        '/budget-plans/$id/months/${isoMonth(month)}',
      );
      return (plans, object(data['data']));
    },
    content: (result, reload) {
      final (plans, budget) = result;
      return [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (plans.isEmpty)
          const Panel(
            child: Text('Create a spending plan in GreenHouse to see it here.'),
          ),
        if (plans.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: plans.any((plan) => plan['id'] == selected)
                ? selected
                : label(plans.first['id']),
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Spending plan'),
            items: [
              for (final plan in plans)
                DropdownMenuItem(
                  value: label(plan['id']),
                  child: Text(label(plan['name'])),
                ),
            ],
            onChanged: (id) => setState(() => selected = id),
          ),
        if (plans.isNotEmpty && budget == null)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Panel(
              child: Text(
                'The selected plan has no allocations for this month.',
              ),
            ),
          ),
        if (budget != null) ...[
          const SectionTitle('Available to spend'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Everyday remaining'),
                const SizedBox(height: 6),
                Text(
                  money(budget['everydayRemaining']),
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: Metric('Posted', money(budget['posted']))),
                    Expanded(
                      child: Metric('Pending', money(budget['pending'])),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('Allocations'),
          for (final row in objects(budget['rows'])) ...[
            Panel(
              child: Row(
                children: [
                  Expanded(
                    child: Metric(
                      words(object(row['group'])['kind']),
                      label(object(row['group'])['name']),
                    ),
                  ),
                  Metric('Remaining', money(row['remaining'])),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ];
    },
  );
}

class Insights extends StatelessWidget {
  const Insights({required this.client, super.key});
  final GreenhouseClient client;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return LoadScreen<Json>(
      load: () => client.request(
        '/insights',
        query: {
          'from': isoDay(DateTime(now.year, now.month - 5)),
          'to': isoDay(DateTime(now.year, now.month, now.day + 1)),
        },
      ),
      content: (data, _) {
        final insights = object(data['insights']);
        final recurring = objects(insights['recurringPayments']);
        final trends = objects(insights['monthlyTrend']);
        final patterns = objects(insights['spendingPatterns']);
        return [
          const Eyebrow('Last six months'),
          const SectionTitle('Recurring payments'),
          if (recurring.isEmpty)
            const Panel(
              child: Text('No recurring payments detected in this period.'),
            ),
          if (recurring.isNotEmpty)
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final payment in recurring)
                    ListTile(
                      title: Text(
                        label(payment['merchant'], 'Recurring payment'),
                      ),
                      subtitle: Text(
                        '${words(payment['cadence'])} · Next expected ${humanDate(payment['nextExpectedDate'])}',
                      ),
                      trailing: Text(money(payment['latestAmount'])),
                    ),
                ],
              ),
            ),
          const SectionTitle('Monthly cash flow'),
          if (trends.isEmpty)
            const Panel(child: Text('No monthly history available.')),
          for (final point in trends)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(humanDate(point['bucket'])),
              subtitle: Text('Income ${money(point['income'])}'),
              trailing: Text('Spent ${money(point['spending'])}'),
            ),
          if (patterns.isNotEmpty) ...[
            const SectionTitle('Spending changes'),
            for (final pattern in patterns)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label(pattern['merchant'])),
                subtitle: Text(
                  '${money(pattern['previousAmount'])} → ${money(pattern['currentAmount'])}',
                ),
              ),
          ],
        ];
      },
    );
  }
}
