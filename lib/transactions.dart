import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';

String transactionTitle(Json row) {
  final fact = object(row['transaction']);
  return label(fact['merchantName'], label(fact['description'], 'Transaction'));
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.row, required this.onTap, super.key});
  final Json row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fact = object(row['transaction']);
    final incoming = (minor(fact['amount']) ?? BigInt.zero) > BigInt.zero;
    final color = Theme.of(context).colorScheme.primary;
    final subtitle = [
      humanDate(fact['postedDate'] ?? fact['date']),
      label(row['categoryName'], 'Uncategorized'),
      if (fact['isPending'] == true) 'Pending',
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .12),
        foregroundColor: color,
        child: Icon(
          incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
          size: 19,
        ),
      ),
      title: Text(
        transactionTitle(row),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        money(fact['amount']),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: incoming ? color : null,
        ),
      ),
      onTap: onTap,
    );
  }
}

class Activity extends StatefulWidget {
  const Activity({
    required this.client,
    this.initialQuery = const {},
    super.key,
  });
  final GreenhouseClient client;
  final Map<String, String> initialQuery;

  @override
  State<Activity> createState() => _ActivityState();
}

class _ActivityState extends State<Activity> {
  final search = TextEditingController();
  List<Json> rows = [];
  String? cursor;
  String? error;
  String? direction;
  bool busy = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && (busy || cursor == null)) return;
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
      if (!more) cursor = null;
    });
    try {
      final data = await widget.client.request(
        '/transactions',
        query: {
          ...widget.initialQuery,
          'limit': '40',
          if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
          'direction': ?direction,
          if (more) 'cursor': cursor!,
        },
      );
      if (!mounted || current != generation) return;
      setState(() {
        rows = [if (more) ...rows, ...objects(data['items'])];
        cursor = data['nextCursor'] as String?;
      });
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = errorMessage(e));
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FinanceList(
    onRefresh: load,
    children: [
      TextField(
        controller: search,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => load(),
        decoration: InputDecoration(
          labelText: 'Search transactions',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () {
              FocusScope.of(context).unfocus();
              load();
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final (value, text) in [
            (null, 'All'),
            ('incoming', 'Incoming'),
            ('outgoing', 'Outgoing'),
          ])
            ChoiceChip(
              label: Text(text),
              selected: direction == value,
              onSelected: (_) {
                setState(() => direction = value);
                load();
              },
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (busy) const LinearProgressIndicator(),
      if (error case final message?) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(message),
        ),
        OutlinedButton(onPressed: () => load(), child: const Text('Try again')),
      ],
      if (!busy && error == null && rows.isEmpty)
        const Panel(child: Text('No matching transactions.')),
      if (rows.isNotEmpty)
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final row in rows)
                TransactionTile(
                  row: row,
                  onTap: () async {
                    if (await openTransaction(context, widget.client, row) &&
                        mounted) {
                      await load();
                    }
                  },
                ),
            ],
          ),
        ),
      if (cursor != null)
        TextButton(
          onPressed: busy ? null : () => load(more: true),
          child: const Text('Load more'),
        ),
    ],
  );
}

Future<bool> openTransaction(
  BuildContext context,
  GreenhouseClient client,
  Json row,
) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TransactionDetail(client: client, row: row),
      ),
    ) ??
    false;

class _TransactionDetail extends StatefulWidget {
  const _TransactionDetail({required this.client, required this.row});
  final GreenhouseClient client;
  final Json row;

  @override
  State<_TransactionDetail> createState() => _TransactionDetailState();
}

class _TransactionDetailState extends State<_TransactionDetail> {
  late final Json fact = object(widget.row['transaction']);
  late final Json annotation = object(widget.row['annotation']);
  late final TextEditingController notes = TextEditingController(
    text: label(annotation['notes'], ''),
  );
  late String category = label(annotation['categoryId'], '');
  late bool excluded = annotation['isExcluded'] == true;
  late bool reviewed = annotation['reviewState'] == 'reviewed';
  late final Future<Json> categories = widget.client.request('/categories');
  bool saving = false;

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await widget.client.request(
        '/transactions/${endpoint(fact['id'])}/annotation',
        method: 'PATCH',
        body: {
          'expectedRevision': annotation['revision'] ?? 0,
          if (category != label(annotation['categoryId'], ''))
            'categoryId': category.isEmpty ? null : category,
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          'isExcluded': excluded,
          if (reviewed != (annotation['reviewState'] == 'reviewed'))
            'reviewState': reviewed ? 'reviewed' : 'none',
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaction')),
    body: FinanceList(
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(words(fact['status'])),
              const SizedBox(height: 6),
              Text(
                money(fact['amount']),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 8),
              Text(
                transactionTitle(widget.row),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${label(object(widget.row['account'])['displayName'])} · ${humanDate(fact['postedDate'] ?? fact['date'])}',
              ),
            ],
          ),
        ),
        const SectionTitle('Details'),
        FutureBuilder<Json>(
          future: categories,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Categories unavailable. ${errorMessage(snapshot.error!)}',
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final choices = objects(snapshot.data!['data']);
            return DropdownButtonFormField<String>(
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Automatic category'),
                ),
                for (final choice in choices)
                  DropdownMenuItem(
                    value: label(choice['id']),
                    child: Text(label(choice['name'])),
                  ),
                if (category.isNotEmpty &&
                    !choices.any((choice) => choice['id'] == category))
                  DropdownMenuItem(
                    value: category,
                    child: Text(
                      label(widget.row['categoryName'], 'Current category'),
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => category = value ?? ''),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          enabled: !saving,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes',
            alignLabelWithHint: true,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Exclude from spending'),
          value: excluded,
          onChanged: saving
              ? null
              : (value) => setState(() => excluded = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mark as reviewed'),
          value: reviewed,
          onChanged: saving
              ? null
              : (value) => setState(() => reviewed = value),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Save changes'),
        ),
      ],
    ),
  );
}
