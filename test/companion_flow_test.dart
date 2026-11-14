import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/ambient_lighting.dart';
import 'package:greenhouse/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'password-manager authentication keeps the login autofill connection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final client = _FixtureClient();
      addTearDown(client.dispose);
      await tester.pumpWidget(GreenHouseApp(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search local network'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden server'));
      await tester.pumpAndSettle();
      final fields = find.byType(EditableText);
      await tester.showKeyboard(find.byType(TextFormField).first);
      final email = tester.widget<EditableText>(fields.first);
      final password = tester.widget<EditableText>(fields.last);
      expect(email.focusNode.hasFocus, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(email.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        const JSONMethodCodec().encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithTag', [
            0,
            {
              tester.state<EditableTextState>(fields.first).autofillId:
                  const TextEditingValue(text: 'saved@example.test').toJSON(),
              tester.state<EditableTextState>(fields.last).autofillId:
                  const TextEditingValue(text: 'saved-password').toJSON(),
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
      expect(email.controller.text, 'saved@example.test');
      expect(password.controller.text, 'saved-password');
    },
  );

  testWidgets('a delayed Cards lookup does not override a selected page', (
    tester,
  ) async {
    final identity = HouseholdIdentity.fromJson({
      'id': 'owner-id',
      'email': 'owner@example.test',
      'displayName': 'Garden Owner',
      'householdId': 'household-1',
      'role': 'owner',
    })!;
    SharedPreferences.setMockInitialValues({
      identity.preferenceKey(
        'default_page',
        Uri.parse('https://garden.example'),
      ): '/cards',
    });
    FlutterSecureStorage.setMockInitialValues({});
    final navigationResponse = Completer<Json>();
    final client = _FixtureClient(navigationResponse: navigationResponse);
    addTearDown(client.dispose);
    await tester.pumpWidget(GreenHouseApp(client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search local network'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garden server'));
    await tester.pumpAndSettle();
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
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Your financial picture'), findsOneWidget);
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.text('Search transactions'), findsOneWidget);
    navigationResponse.complete({
      'enabled': true,
      'navigationPage': {'id': 'cards', 'title': 'Cards'},
    });
    await tester.pumpAndSettle();
    expect(find.text('Search transactions'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Cards'), findsOneWidget);
    expect(client.requests, contains('/cards/navigation'));
    expect(client.requests, isNot(contains('/cards')));
  });

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

    expect(
      tester.testTextInput.log.any(
        (call) =>
            call.method == 'TextInput.finishAutofillContext' &&
            call.arguments == true,
      ),
      isTrue,
    );
    expect(find.text('Set an unlock PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(client.hasBiometricSession, isTrue);
    expect(find.text('Enable biometrics?'), findsNothing);

    expect(find.text('Your financial picture'), findsOneWidget);
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Cards'), findsNothing);
    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
      findsOneWidget,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('GreenHouse is locked'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Your financial picture'), findsOneWidget);
    expect(find.text(r'$12,345.67'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Default page'));
    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    expect(find.byType(AmbientLighting), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(
        client.identity!.preferenceKey('default_page', client.origin),
      ),
      'activity',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Your financial picture'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final lightingSwitch = find.widgetWithText(
      SwitchListTile,
      'Ambient daylight and moonlight',
    );
    await tester.ensureVisible(lightingSwitch);
    await tester.tap(lightingSwitch);
    await tester.pumpAndSettle();
    expect(find.byType(AmbientLighting), findsNothing);
    expect(
      preferences.getBool(
        client.identity!.preferenceKey('ambient_lighting', client.origin),
      ),
      isFalse,
    );
    await tester.tap(lightingSwitch);
    await tester.pumpAndSettle();
    expect(find.byType(AmbientLighting), findsOneWidget);
    expect(
      preferences.getBool(
        client.identity!.preferenceKey('ambient_lighting', client.origin),
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Unlink device'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Unlink device'));
    await tester.pumpAndSettle();
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
  _FixtureClient({this.navigationResponse});

  final Completer<Json>? navigationResponse;
  final requests = <String>[];
  Uri? selected;
  bool didUnlink = false;
  bool savedBiometrics = false;
  @override
  bool get hasBiometricSession => savedBiometrics;
  @override
  Future<bool> rememberWithBiometrics() async => savedBiometrics = true;
  @override
  Future<bool> checkBiometricEnrollment({required bool lockEnabled}) async =>
      false;
  HouseholdIdentity? selectedIdentity;

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
  HouseholdIdentity? get identity => selectedIdentity;

  @override
  Future<HouseholdIdentity> signIn(
    String email,
    String password, {
    Future<String?> Function(Uri challengeUrl)? verifyChallenge,
  }) async {
    return selectedIdentity = HouseholdIdentity.fromJson({
      'id': 'owner-id',
      'email': email,
      'displayName': 'Garden Owner',
      'householdId': 'household-1',
      'role': 'owner',
    })!;
  }

  @override
  Future<void> validateSession() async {}

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<bool> hasDeviceLock() async => false;

  @override
  Future<bool> disconnect() async {
    didUnlink = true;
    savedBiometrics = false;
    selected = null;
    selectedIdentity = null;
    return true;
  }

  @override
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    requests.add(path);
    if (path == '/cards/navigation') {
      return navigationResponse?.future ??
          {'enabled': false, 'navigationPage': null};
    }
    if (path == '/cards') {
      return {
        'enabled': false,
        'navigationPage': null,
        'products': [],
        'categories': [],
        'wallet': [],
      };
    }
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
