import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';
import 'transactions.dart';

class Accounts extends StatelessWidget {
  const Accounts({required this.client, super.key});
  final GreenhouseClient client;

  @override
  Widget build(BuildContext context) => LoadScreen<List<Json>>(
    load: () => Future.wait([
      client.request('/accounts'),
      client.request('/connections'),
    ]),
    content: (data, reload) {
      final accounts = objects(data[0]['items']);
      final connections = objects(data[1]['items']);
      return [
        const Eyebrow('Linked and manual'),
        const SectionTitle('Your accounts'),
        if (accounts.isEmpty)
          const Panel(
            child: Text('Accounts added to this instance will appear here.'),
          ),
        for (final row in accounts) ...[
          Panel(
            padding: EdgeInsets.zero,
            child: _AccountTile(
              row: row,
              onTap: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        _AccountDetail(client: client, summary: row),
                  ),
                );
                if (context.mounted) await reload();
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SectionTitle('Connections'),
        if (connections.isEmpty)
          const Panel(child: Text('No bank connections.')),
        if (connections.isNotEmpty)
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final connection in connections)
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
      ];
    },
  );
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
  const _AccountDetail({required this.client, required this.summary});
  final GreenhouseClient client;
  final Json summary;

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
