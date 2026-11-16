import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_theme.dart';
import 'plugin_pages.dart';

@immutable
class CompanionRoute {
  const CompanionRoute(this.page, [this.query = const {}]);

  final String page;
  final Map<String, String> query;
}

abstract final class CompanionPage {
  static const overview = 'overview';
  static const activity = 'activity';
  static const accounts = 'accounts';
  static const plan = 'plan';
  static const insights = 'insights';
  static const more = 'more';

  static const corePages = {overview, activity, accounts, plan, insights, more};

  /// Host-owned compatibility destinations. A dynamic link can only navigate
  /// to a target the app already knows how to show.
  static const destinationAliases = {
    '/': overview,
    'overview': overview,
    'activity': activity,
    'accounts': accounts,
    'plan': plan,
    'insights': insights,
    'more': more,
    '/transactions': activity,
    '/budgets': plan,
    '/accounts': accounts,
    '/insights': insights,
    '/plugins': more,
  };

  static bool isCore(String? value) => corePages.contains(value);

  static PluginPageEntry? pluginEntry(
    String? value,
    List<PluginPageEntry> pluginPages,
  ) {
    final navigation = PluginNavigation(pluginPages);
    return navigation.byPath(value) ?? navigation.byLegacyPath(value);
  }

  static String resolveDefault(
    String? value, {
    required List<PluginPageEntry> pluginPages,
  }) {
    if (isCore(value)) return value!;
    final entry = pluginEntry(value, pluginPages);
    if (entry != null && entry.available) return entry.path;
    return overview;
  }

  static String restorePage({
    required String? savedPage,
    required String currentPage,
    required List<PluginPageEntry> pluginPages,
    required int startingRevision,
    required int currentRevision,
  }) => startingRevision == currentRevision
      ? resolveDefault(savedPage, pluginPages: pluginPages)
      : currentPage;

  static List<(String, String)> defaultOptions({
    required List<PluginPageEntry> pluginPages,
  }) => [
    (overview, 'Overview'),
    (activity, 'Activity'),
    (accounts, 'Accounts'),
    (plan, 'Plan'),
    (insights, 'Insights'),
    (more, 'More'),
    for (final page in pluginPages)
      if (page.available) (page.path, page.title),
  ];

  /// Maps a declared host destination to a companion page, if known.
  static String? destination(String? value) {
    if (value == null) return null;
    return destinationAliases[normalizePluginPath(value)];
  }

  /// Safe host-owned route parser. Only known pages and an account-filtered
  /// Activity route are accepted; URLs, schemes, hosts and paths are rejected.
  static CompanionRoute? route(
    String? value,
    List<PluginPageEntry> pluginPages,
  ) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty || raw.contains('..')) return null;
    if (isCore(raw)) return CompanionRoute(raw);
    final navigation = PluginNavigation(pluginPages);
    final plugin = navigation.byPath(raw) ?? navigation.byLegacyPath(raw);
    if (plugin != null && plugin.available) return CompanionRoute(plugin.path);
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.hasScheme || uri.host.isNotEmpty) return null;
    final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    final aliased = destinationAliases[path];
    if (aliased == null) return null;
    if (aliased != activity) return CompanionRoute(aliased);
    final account =
        uri.queryParameters['accountId'] ?? uri.queryParameters['accountIds'];
    return CompanionRoute(
      activity,
      account == null || account.isEmpty ? const {} : {'accountIds': account},
    );
  }

  static Map<String, String> destinationsFor(List<PluginPageEntry> pages) => {
    ...destinationAliases,
    for (final page in pages)
      if (page.available) page.path: page.path,
  };

  static int bottomIndex(String page) => switch (page) {
    overview => 0,
    activity => 1,
    accounts => 2,
    plan => 3,
    _ => 4,
  };
}

class MorePages extends StatelessWidget {
  const MorePages({required this.pluginPages, required this.onOpen, super.key});
  final List<PluginPageEntry> pluginPages;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => FinanceList(
    children: [
      const Eyebrow('More'),
      const SectionTitle('More pages'),
      Panel(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.auto_graph_outlined),
                title: const Text('Insights'),
                subtitle: const Text('Spending trends and recurring payments'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(CompanionPage.insights),
              ),
              for (final page in pluginPages) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(_iconFor(page.icon)),
                  title: Text(page.title),
                  subtitle: Text(
                    page.available
                        ? page.description ??
                              'Open this page from ${page.installationId}'
                        : 'Update GreenHouse to open this page.',
                  ),
                  trailing: page.available
                      ? const Icon(Icons.chevron_right)
                      : const Icon(Icons.system_update_alt),
                  enabled: page.available,
                  onTap: page.available ? () => onOpen(page.path) : null,
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

IconData _iconFor(String token) => switch (token) {
  'wallet' || 'credit-card' => Icons.credit_card_outlined,
  'chart' || 'insights' => Icons.insights_outlined,
  'book' || 'list' => Icons.menu_book_outlined,
  'settings' => Icons.tune,
  'home' => Icons.home_outlined,
  _ => Icons.extension_outlined,
};
