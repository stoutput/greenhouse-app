import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/companion_navigation.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/plugin_pages.dart';

PluginPageEntry _entry({
  String pageId = 'wallet',
  String title = 'Cards',
  String? path,
  String availability = 'available',
  List<String> legacyPaths = const ['/cards'],
}) => PluginPageEntry(
  installationId: 'install-1',
  pageId: pageId,
  title: title,
  description: 'Compare benefits',
  path: path ?? pluginPagePath('install-1', pageId),
  icon: 'wallet',
  version: 2,
  availability: availability,
  requiredCapabilities: const ['collection.v1'],
  legacyPaths: legacyPaths,
);

void main() {
  test('root home alias is accepted and external origins are rejected', () {
    expect(CompanionPage.destination('/'), CompanionPage.overview);
    expect(CompanionPage.route('/', const [])?.page, CompanionPage.overview);
    expect(CompanionPage.route('https://example.test/', const []), isNull);
    expect(CompanionPage.route('//example.test/', const []), isNull);
  });
  test('default pages include only available navigation pages', () {
    final pages = [
      _entry(),
      _entry(
        pageId: 'old-page',
        title: 'Old page',
        availability: 'update-required',
        legacyPaths: const [],
      ),
    ];
    final walletPath = pluginPagePath('install-1', 'wallet');
    expect(
      CompanionPage.resolveDefault('/cards', pluginPages: pages),
      walletPath,
    );
    expect(
      CompanionPage.resolveDefault('unknown-plugin-page', pluginPages: pages),
      CompanionPage.overview,
    );
    expect(
      CompanionPage.resolveDefault(
        pluginPagePath('install-1', 'old-page'),
        pluginPages: pages,
      ),
      CompanionPage.overview,
    );
    expect(
      CompanionPage.defaultOptions(pluginPages: pages).map((item) => item.$1),
      contains(walletPath),
    );
    expect(
      CompanionPage.defaultOptions(pluginPages: pages).map((item) => item.$1),
      isNot(contains(pluginPagePath('install-1', 'old-page'))),
    );
  });

  test('legacy aliases migrate only through discovery', () {
    final navigation = PluginNavigation([
      _entry(legacyPaths: const ['/cards', '/cards/']),
    ]);
    expect(
      navigation.resolvePath('/cards'),
      pluginPagePath('install-1', 'wallet'),
    );
    expect(
      navigation.resolvePath('/plugins/install-1/pages/wallet/'),
      pluginPagePath('install-1', 'wallet'),
    );
    expect(navigation.resolvePath('/unknown'), isNull);
    expect(
      CompanionPage.resolveDefault('/cards', pluginPages: const []),
      CompanionPage.overview,
    );
  });

  test('account and server scopes keep default-page choices isolated', () {
    final first = HouseholdIdentity.fromJson({
      'id': 'member-1',
      'email': 'one@example.test',
      'householdId': 'household-1',
      'role': 'owner',
    })!;
    final second = HouseholdIdentity.fromJson({
      'id': 'member-2',
      'email': 'two@example.test',
      'householdId': 'household-1',
      'role': 'owner',
    })!;
    final key = first.preferenceKey(
      'default_page',
      Uri.parse('https://garden.example'),
    );
    expect(
      key,
      isNot(
        second.preferenceKey(
          'default_page',
          Uri.parse('https://garden.example'),
        ),
      ),
    );
    expect(
      key,
      isNot(
        first.preferenceKey('default_page', Uri.parse('https://other.example')),
      ),
    );
  });

  test('a delayed discovery cannot override a page chosen in the meantime', () {
    final pages = [_entry()];
    expect(
      CompanionPage.restorePage(
        savedPage: '/cards',
        currentPage: CompanionPage.activity,
        pluginPages: pages,
        startingRevision: 0,
        currentRevision: 1,
      ),
      CompanionPage.activity,
    );
    expect(
      CompanionPage.restorePage(
        savedPage: '/cards',
        currentPage: CompanionPage.overview,
        pluginPages: pages,
        startingRevision: 0,
        currentRevision: 0,
      ),
      pluginPagePath('install-1', 'wallet'),
    );
  });

  testWidgets('More lists Insights and navigation pages, disabling updates', (
    tester,
  ) async {
    var opened = '';
    final pages = [
      _entry(),
      _entry(
        pageId: 'old-page',
        title: 'Old page',
        availability: 'update-required',
        legacyPaths: const [],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MorePages(pluginPages: pages, onOpen: (page) => opened = page),
        ),
      ),
    );
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Old page'), findsOneWidget);
    expect(find.text('Update GreenHouse to open this page.'), findsOneWidget);
    await tester.tap(find.text('Insights'));
    expect(opened, CompanionPage.insights);
    await tester.tap(find.text('Cards'));
    expect(opened, pluginPagePath('install-1', 'wallet'));
    await tester.tap(find.text('Old page'));
    expect(opened, pluginPagePath('install-1', 'wallet'));
  });
}
