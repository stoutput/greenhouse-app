import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.greenhouse/biometric_enrollment');
  const origin = 'https://garden.example';
  final owner = {
    'id': 'member',
    'email': 'a@example.test',
    'householdId': 'household',
    'role': 'owner',
  };
  var changed = false;
  var resets = 0;
  var revocations = 0;
  var passwordLogins = 0;
  var saved = false;
  setUp(() {
    changed = false;
    resets = 0;
    revocations = 0;
    passwordLogins = 0;
    saved = false;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/local_auth'),
          (call) async => true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'hasChanged') return changed;
          if (call.method == 'reset') {
            changed = false;
            resets++;
          }
          return null;
        });
  });
  _Client makeClient() => _Client(
    httpClient: MockClient((request) async {
      Object response = {};
      if (request.url.path.endsWith('/mobile/info')) {
        response = {
          'service': 'greenhouse',
          'version': 1,
          'name': 'Garden',
          'setupRequired': false,
        };
      } else if (request.url.path.endsWith('/mobile/login')) {
        passwordLogins++;
        response = {'token': 'token', 'owner': owner};
      } else if (request.url.path.endsWith('/auth/session')) {
        response = {'owner': owner};
      } else if (request.method == 'DELETE') {
        revocations++;
        return http.Response('', 204);
      }
      return http.Response(jsonEncode(response), 200);
    }),
  );

  for (final biometricLogin in [false, true]) {
    for (final lockEnabled in [false, true]) {
      test(
        'changed enrollment: biometric login=$biometricLogin, app lock=$lockEnabled',
        () async {
          final client = makeClient();
          addTearDown(client.dispose);
          await client.connect(origin);
          await client.signIn('a@example.test', 'password');
          expect(resets, 1);
          expect(await client.rememberWithBiometrics(), isTrue);
          saved = client.hasBiometricSession;
          expect(saved, isTrue);
          if (biometricLogin) {
            expect(await client.unlock(), isNotNull);
          }
          expect(client.signedInWithBiometrics, biometricLogin);
          changed = true;
          final shouldLogout = biometricLogin || lockEnabled;
          expect(
            await client.checkBiometricEnrollment(lockEnabled: lockEnabled),
            shouldLogout,
          );
          expect(client.isSignedIn, !shouldLogout);
          expect(client.hasBiometricSession, isFalse);
          expect(revocations, shouldLogout ? 1 : 0);
          // A protected session must not silently trust the new biometric set.
          expect(resets, shouldLogout ? 1 : 2);
          expect(passwordLogins, 1);
        },
      );
    }
  }

  test(
    'a changed saved session is discarded before prompting or restoring it',
    () async {
      final client = makeClient();
      addTearDown(client.dispose);
      await client.connect(origin);
      await client.signIn('a@example.test', 'password');
      expect(await client.rememberWithBiometrics(), isTrue);
      changed = true;
      expect(await client.unlock(), isNull);
      expect(client.isSignedIn, isFalse);
      expect(client.hasBiometricSession, isFalse);
      expect(resets, 1);
      expect(await client.unlock(), isNull);
      expect(resets, 1);
    },
  );

  test('legacy saved sessions require a password to establish an enrollment baseline', () async {
    final scope = HouseholdIdentity.fromJson(owner)!
        .preferenceScope(Uri.parse(origin));
    SharedPreferences.setMockInitialValues({
      'greenhouse.origin': origin,
      'greenhouse.biometric_origin': origin,
      'greenhouse.biometric_scope': scope,
    });
    FlutterSecureStorage.setMockInitialValues({
      'greenhouse.biometric_session': jsonEncode({
        'origin': origin,
        'scope': scope,
        'token': 'legacy-token',
      }),
    });
    changed = true;
    final client = makeClient();
    addTearDown(client.dispose);
    await client.initialize();
    expect(await client.unlock(), isNull);
    expect(client.hasBiometricSession, isFalse);
    expect(client.isSignedIn, isFalse);
    expect(resets, 0);
  });

  test(
    'unchanged enrollment leaves the existing session and credential usable',
    () async {
      final client = makeClient();
      addTearDown(client.dispose);
      await client.connect(origin);
      await client.signIn('a@example.test', 'password');
      expect(await client.rememberWithBiometrics(), isTrue);
      expect(await client.checkBiometricEnrollment(lockEnabled: true), isFalse);
      expect(client.isSignedIn, isTrue);
      expect(client.hasBiometricSession, isTrue);
      expect(revocations, 0);
    },
  );
}

class _Client extends GreenhouseClient {
  _Client({required super.httpClient});
  @override
  Future<bool> canUseBiometrics() async => true;
}
