import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('connect, sign in and unlink to choose another instance', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'appearance': 'dark'});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(392, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _FixtureClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(GreenHouseApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Search local network'), findsOneWidget);
    await tester.tap(find.text('Search local network'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garden server'));
    await tester.pumpAndSettle();
    expect(client.origin?.host, 'garden.example');

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.test',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'example-password',
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Set an unlock PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enable biometrics?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Your financial picture'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xff101a18),
      ),
      findsOneWidget,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('GreenHouse is locked'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Your financial picture'), findsOneWidget);
    expect(find.text(r'$12,345.67'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Unlink device'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Unlink device'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink this device?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink'));
    await tester.pumpAndSettle();

    expect(client.didUnlink, isTrue);
    expect(client.origin, isNull);
    expect(find.text('Search local network'), findsOneWidget);
    expect(find.text(r'$12,345.67'), findsNothing);
    await tester.enterText(find.byType(TextField), 'https://other.example');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(client.origin?.host, 'other.example');
    expect(find.text('Welcome back'), findsOneWidget);
  });
}

class _FixtureClient extends GreenhouseClient {
  Uri? selected;
  bool didUnlink = false;

  @override
  Uri? get origin => selected;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<DiscoveredGreenhouse>> discover() async => [
    DiscoveredGreenhouse(
      origin: Uri.parse('https://garden.example'),
      name: 'Garden server',
    ),
  ];

  @override
  Future<String> connect(String address) async {
    selected = Uri.parse(address);
    return 'Garden server';
  }

  @override
  Future<Json> signIn(String email, String password) async => {'email': email};

  @override
  Future<void> validateSession() async {}

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<bool> disconnect() async {
    didUnlink = true;
    selected = null;
    return true;
  }

  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    if (path == '/financial-picture') {
      return {
        'data': {
          'netWorth': {'amount': '1234567', 'currency': 'USD'},
          'history': [
            {
              'month': '2026-08',
              'netWorth': {'amount': '650000', 'currency': 'USD'},
            },
            {
              'month': '2026-09',
              'netWorth': {'amount': '720000', 'currency': 'USD'},
            },
            {
              'month': '2026-10',
              'netWorth': {'amount': '1234567', 'currency': 'USD'},
            },
          ],
        },
      };
    }
    return {};
  }
}
