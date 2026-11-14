import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.greenhouse/biometric_enrollment'),
          (call) async => call.method == 'hasChanged' ? false : null,
        );
  });
  test('every biometric unlock requests fresh storage authentication, including after success', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final origin = Uri.parse('https://garden.example');
    final owner = {
      'id': 'member',
      'email': 'a@example.test',
      'householdId': 'household',
      'role': 'owner',
    };
    final scope = HouseholdIdentity.fromJson(owner)!.preferenceScope(origin);
    SharedPreferences.setMockInitialValues({
      'greenhouse.origin': origin.toString(),
      'greenhouse.biometric_origin': origin.toString(),
      'greenhouse.biometric_scope': scope,
    });
    const storageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    var prompts = 0;
    var cancelled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
          if (call.method == 'read') {
            final arguments = call.arguments as Map;
            final options = arguments['options'] as Map;
            expect(options['enforceBiometrics'], 'true');
            expect(options['biometricType'], 'strongBiometricOnly');
            expect(options['requireBiometricsPerOperation'], 'true');
            prompts++;
            if (cancelled) throw PlatformException(code: 'UserCanceled');
            return jsonEncode({
              'origin': origin.toString(),
              'scope': scope,
              'token': 'saved-token',
            });
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, null),
    );
    var validations = 0;
    final client = _BiometricClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/session');
        expect(request.headers['authorization'], 'Bearer saved-token');
        validations++;
        return http.Response(jsonEncode({'owner': owner}), 200);
      }),
    );
    addTearDown(client.dispose);
    await client.initialize();
    expect((await client.unlock())?.email, 'a@example.test');
    expect((await client.unlock())?.email, 'a@example.test');
    expect(prompts, 2);
    expect(validations, 2);
    cancelled = true;
    expect(await client.unlock(), isNull);
    expect(prompts, 3);
    expect(validations, 2);
  });
}

class _BiometricClient extends GreenhouseClient {
  _BiometricClient({required super.httpClient});

  @override
  Future<bool> canUseBiometrics() async => true;
}
