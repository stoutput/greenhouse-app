import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/app_lock.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:greenhouse/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PIN verifier rejects attempts and throttles after three failures',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final lock = AppLock();
      await lock.setPin('123456');
      expect(await lock.verify('000000'), isFalse);
      expect(await lock.verify('000000'), isFalse);
      expect(await lock.verify('000000'), isFalse);
      expect(await lock.verify('123456'), isFalse);
      expect(lock.retryAt, isNotNull);
    },
  );

  testWidgets('cold start automatically attempts the saved biometric session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _Client();
    var signedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(client: client, onSignedIn: (_) => signedIn = true),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.unlocks, 1);
    expect(signedIn, isTrue);
    client.dispose();
  });

  testWidgets(
    'reauthentication stays black until failure, then offers logo and unlock retry',
    (tester) async {
      final pending = Completer<bool>();
      final client = _Client()
        ..deviceSupported = true
        ..pendingAuthentication = pending;
      var revealed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LockScreen(
            lock: AppLock(),
            client: client,
            setup: false,
            onUnlocked: () => revealed = true,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(client.localAttempts, 1);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.black,
      );
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.byType(Text), findsNothing);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
      expect(revealed, isFalse);
      client.pendingAuthentication = null;
      client.localSuccess = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(client.localAttempts, 2);
      expect(revealed, isTrue);
      client.dispose();
    },
  );

  testWidgets(
    'enrollment changes sign out before device or PIN authentication',
    (tester) async {
      final client = _Client()
        ..deviceSupported = true
        ..enrollmentChanged = true;
      var signedOut = false;
      var revealed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LockScreen(
            lock: AppLock(),
            client: client,
            setup: false,
            onUnlocked: () => revealed = true,
            onSignOut: () async => signedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
      expect(revealed, isFalse);
      expect(client.localAttempts, 0);
      client.dispose();
    },
  );

  testWidgets('configured device lock does not fall back after cancellation', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final lock = AppLock();
    await lock.setPin('123456');
    final client = _Client()..deviceSupported = true;
    var revealed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          lock: lock,
          client: client,
          setup: false,
          onUnlocked: () => revealed = true,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.localAttempts, 1);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
    expect(revealed, isFalse);
    client.dispose();
  });

  testWidgets('removed device lock prompts for a new PIN when none exists', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final lock = AppLock();
    final client = _Client();
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          lock: lock,
          client: client,
          setup: false,
          onUnlocked: () {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set an unlock PIN'), findsOneWidget);
    client.dispose();
  });

  testWidgets('configured device lock skips initial PIN setup', (tester) async {
    final lock = AppLock();
    final client = _Client()..deviceSupported = true;
    var revealed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          lock: lock,
          client: client,
          setup: true,
          onUnlocked: () => revealed = true,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(revealed, isTrue);
    expect(find.byType(TextField), findsNothing);
    client.dispose();
  });

  testWidgets('retry checks for a removed device lock and reuses the PIN', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final lock = AppLock();
    await lock.setPin('123456');
    final client = _Client()..deviceSupported = true;
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          lock: lock,
          client: client,
          setup: false,
          onUnlocked: () {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    client.deviceSupported = false;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('GreenHouse is locked'), findsNothing);
    client.dispose();
  });

  testWidgets('setup after background requires device authentication', (
    tester,
  ) async {
    final lock = AppLock();
    final client = _Client()..deviceSupported = true;
    var revealed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          lock: lock,
          client: client,
          setup: true,
          initialUnlockRequired: true,
          onUnlocked: () => revealed = true,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.localAttempts, 1);
    expect(revealed, isFalse);
    client.dispose();
  });

  testWidgets(
    'background during validation invalidates native authentication',
    (tester) async {
      final client = _Client()
        ..deviceSupported = true
        ..localSuccess = true;
      final validation = Completer<void>();
      client.pendingValidation = validation;
      var revealed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LockScreen(
            lock: AppLock(),
            client: client,
            setup: false,
            onUnlocked: () => revealed = true,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(client.localAttempts, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      client.localSuccess = false;
      validation.complete();
      await tester.pumpAndSettle();
      expect(revealed, isFalse);
      expect(client.localAttempts, 2);
      client.dispose();
    },
  );

  testWidgets('a PIN cannot reveal a session that fails server validation', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final lock = AppLock();
    await lock.setPin('123456');
    final client = _Client()..validationFails = true;
    var revealed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LockScreen(
          lock: lock,
          client: client,
          setup: false,
          onUnlocked: () => revealed = true,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(revealed, isFalse);
    expect(
      find.text('Could not verify your session. Retry or sign out.'),
      findsOneWidget,
    );
    client.dispose();
  });
}

class _Client extends GreenhouseClient {
  @override
  Future<bool> checkBiometricEnrollment({required bool lockEnabled}) async =>
      enrollmentChanged;
  bool enrollmentChanged = false;
  int unlocks = 0;
  int localAttempts = 0;
  bool validationFails = false;
  bool deviceSupported = false;
  bool localSuccess = false;
  Completer<void>? pendingValidation;
  Completer<bool>? pendingAuthentication;
  @override
  Future<bool> hasDeviceLock() async => deviceSupported;
  @override
  Uri? get origin => Uri.parse('https://garden.example');
  @override
  bool get hasBiometricSession => true;
  @override
  Future<HouseholdIdentity?> unlock() async {
    unlocks++;
    return HouseholdIdentity.fromJson({
      'id': 'owner-id',
      'email': 'owner@example.test',
      'householdId': 'household-1',
      'role': 'owner',
    });
  }

  @override
  Future<bool> authenticateLocally() async {
    localAttempts++;
    return pendingAuthentication?.future ?? localSuccess;
  }

  @override
  Future<void> validateSession() async {
    if (validationFails) throw Exception('expired');
    await pendingValidation?.future;
  }
}
