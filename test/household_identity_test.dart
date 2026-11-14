import 'package:flutter/services.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/app_lock.dart';
import 'package:greenhouse/greenhouse_client.dart';
import 'package:http/http.dart' as http;
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

  test('identity parsing requires household fields and fails closed', () {
    expect(HouseholdIdentity.fromJson({'email': 'a@example.test'}), isNull);
    final unknown = _identity('a@example.test', role: 'future-role');
    expect(unknown.role, HouseholdRole.unknown);
    expect(unknown.permissions.canManageSharedFinances, isFalse);
    expect(unknown.permissions.canAcknowledgeNotifications, isFalse);
    expect(
      _identity(
        'a@example.test',
        role: 'gardener',
      ).permissions.canManageSharedFinances,
      isFalse,
    );
    expect(
      _identity(
        'a@example.test',
        role: 'admin',
      ).permissions.canManageSharedFinances,
      isTrue,
    );
  });

  test('account preference keys separate users and selected origins', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const origin = 'https://garden.example';
    final alice = _identity('alice@example.test');
    final bob = _identity('bob@example.test', role: 'gardener');
    final aliceKey = alice.preferenceKey('appearance', Uri.parse(origin));
    final bobKey = bob.preferenceKey('appearance', Uri.parse(origin));
    final otherServerKey = alice.preferenceKey(
      'appearance',
      Uri.parse('https://other.example'),
    );

    await preferences.setString(aliceKey, 'dark');
    expect(preferences.getString(bobKey), isNull);
    expect(preferences.getString(otherServerKey), isNull);
    expect(
      alice.preferenceKey('push_enabled', Uri.parse(origin)),
      isNot(aliceKey),
    );
  });

  test(
    'password sign-in replaces biometric identity and stale requests',
    () async {
      const origin = 'https://garden.example';
      final previous = _identity('previous@example.test');
      SharedPreferences.setMockInitialValues({
        'greenhouse.biometric_origin': origin,
        'greenhouse.biometric_scope': previous.preferenceScope(
          Uri.parse(origin),
        ),
        'greenhouse.push_enabled': true,
        previous.preferenceKey('push_enabled', Uri.parse(origin)): true,
      });
      FlutterSecureStorage.setMockInitialValues({
        'greenhouse.biometric_session': jsonEncode({
          'origin': origin,
          'scope': previous.preferenceScope(Uri.parse(origin)),
          'token': 'old-token',
        }),
      });
      final httpClient = _AuthSwitchHttpClient();
      final client = GreenhouseClient(httpClient: httpClient);
      addTearDown(client.dispose);

      await client.initialize();
      await client.connect(origin);
      expect(client.hasBiometricSession, isTrue);

      final first = await client.signIn('first@example.test', 'password');
      expect(first.email, 'first@example.test');
      expect(client.hasBiometricSession, isFalse);
      expect(client.pushEnabled, isFalse);

      final staleRequest = client.request('/financial-picture');
      await Future<void>.delayed(Duration.zero);
      final second = await client.signIn('second@example.test', 'password');
      expect(client.identity?.email, second.email);
      httpClient.completeOldRequest();
      await expectLater(staleRequest, throwsA(isA<GreenhouseException>()));
      expect(client.identity?.email, 'second@example.test');
    },
  );

  test(
    'app lock PIN and enabled state are scoped to the signed-in identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final lock = AppLock();
      await lock.initialize();

      await lock.useIdentity('household-a/member-a');
      await lock.setPin('123456');
      await lock.setEnabled(false);
      expect(await lock.verify('123456'), isTrue);

      await lock.useIdentity('household-a/member-b');
      expect(lock.enabled, isTrue);
      expect(lock.hasPin, isFalse);
      await expectLater(lock.verify('123456'), throwsException);

      await lock.useIdentity('household-a/member-a');
      expect(lock.enabled, isFalse);
      expect(await lock.verify('123456'), isTrue);
    },
  );
}

HouseholdIdentity _identity(String email, {String role = 'owner'}) =>
    HouseholdIdentity.fromJson({
      'id': email,
      'email': email,
      'displayName': email,
      'householdId': 'household-1',
      'role': role,
    })!;

class _AuthSwitchHttpClient extends http.BaseClient {
  final oldResponse = Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/mobile/info')) {
      return _json({
        'service': 'greenhouse',
        'version': 1,
        'name': 'Garden',
        'setupRequired': false,
      });
    }
    if (request.url.path.endsWith('/mobile/login')) {
      final body = jsonDecode((request as http.Request).body) as Map;
      final email = body['email'] as String;
      return _json({
        'token': 'token-$email',
        'owner': {
          'id': email,
          'email': email,
          'displayName': email,
          'householdId': 'household-1',
          'role': 'gardener',
        },
      });
    }
    if (request.url.path.endsWith('/financial-picture')) {
      return oldResponse.future;
    }
    return _json({});
  }

  void completeOldRequest() {
    oldResponse.complete(_json({'netWorth': 'old response'}));
  }

  http.StreamedResponse _json(Object body) => http.StreamedResponse(
    Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(jsonEncode(body)))),
    200,
    headers: {'content-type': 'application/json'},
  );
}
