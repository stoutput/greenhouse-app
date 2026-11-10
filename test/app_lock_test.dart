import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  testWidgets('return attempts biometrics and falls back to PIN', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final lock = AppLock();
    await lock.setPin('123456');
    final client = _Client();
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
    expect(
      find.text('Biometrics did not unlock. Enter your PIN.'),
      findsOneWidget,
    );
    expect(revealed, isFalse);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(revealed, isTrue);
    client.dispose();
  });

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
  int unlocks = 0;
  int localAttempts = 0;
  bool validationFails = false;
  @override
  Uri? get origin => Uri.parse('https://garden.example');
  @override
  bool get hasBiometricSession => true;
  @override
  Future<Json?> unlock() async {
    unlocks++;
    return {'email': 'owner@example.test'};
  }

  @override
  Future<bool> authenticateLocally() async {
    localAttempts++;
    return false;
  }

  @override
  Future<void> validateSession() async {
    if (validationFails) throw Exception('expired');
  }
}
