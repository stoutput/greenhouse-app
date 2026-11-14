import 'package:flutter/services.dart';

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final enabled in [true, false, null]) {
    test(
      'password sign-in follows fresh server Turnstile setting: $enabled',
      () async {
        final requests = <http.Request>[];
        var currentSetting = false;
        final client = GreenhouseClient(
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/mobile/info')) {
              return jsonResponse({
                'service': 'greenhouse',
                'version': 1,
                'name': 'Garden',
                'setupRequired': false,
                if (currentSetting && enabled != null)
                  'turnstileRequired': enabled,
              });
            }
            return jsonResponse({
              'token': 'session-token',
              'owner': {
                'id': 'member',
                'email': 'a@example.test',
                'householdId': 'household',
                'role': 'owner',
              },
            });
          }),
        );
        addTearDown(client.dispose);
        await client.connect('https://garden.example');
        currentSetting = true;
        var verifications = 0;
        final identity = await client.signIn(
          'a@example.test',
          'password',
          verifyChallenge: (url) async {
            verifications++;
            expect(
              url.toString(),
              'https://garden.example/api/v1/mobile/challenge',
            );
            expect(requests.where((r) => r.method == 'POST'), isEmpty);
            return 'single-use-token';
          },
        );
        expect(identity.email, 'a@example.test');
        expect(verifications, enabled == true ? 1 : 0);
        final body = jsonDecode(requests.last.body) as Map;
        if (enabled == true) {
          expect(body['cf-turnstile-response'], 'single-use-token');
        } else {
          expect(body.containsKey('cf-turnstile-response'), isFalse);
        }
      },
    );
  }

  for (final outcome in [
    'cancel',
    'empty',
    'error',
    'missing',
    'switch-server',
  ]) {
    test(
      'does not submit credentials when challenge cannot complete: $outcome',
      () async {
        var posts = 0;
        final client = GreenhouseClient(
          httpClient: MockClient((request) async {
            if (request.method == 'POST') posts++;
            return jsonResponse({
              'service': 'greenhouse',
              'version': 1,
              'name': 'Garden',
              'setupRequired': false,
              'turnstileRequired': true,
            });
          }),
        );
        addTearDown(client.dispose);
        await client.connect('https://garden.example');
        await expectLater(
          client.signIn(
            'a@example.test',
            'password',
            verifyChallenge: outcome == 'missing'
                ? null
                : (_) async {
                    if (outcome == 'error') {
                      throw const GreenhouseException('Unavailable');
                    }
                    if (outcome == 'cancel') return null;
                    if (outcome == 'empty') return '';
                    await client.connect('https://other.example');
                    return 'stale-token';
                  },
          ),
          throwsA(isA<GreenhouseException>()),
        );
        expect(posts, 0);
        expect(client.isSignedIn, isFalse);
      },
    );
  }

  test(
    'failed password attempts acquire a fresh challenge token on retry',
    () async {
      final tokens = <String>[];
      final client = GreenhouseClient(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            tokens.add(
              (jsonDecode(request.body) as Map)['cf-turnstile-response']
                  as String,
            );
            return http.Response('{}', 401);
          }
          return jsonResponse({
            'service': 'greenhouse',
            'version': 1,
            'name': 'Garden',
            'setupRequired': false,
            'turnstileRequired': true,
          });
        }),
      );
      addTearDown(client.dispose);
      await client.connect('https://garden.example');
      var attempt = 0;
      for (var i = 0; i < 2; i++) {
        await expectLater(
          client.signIn(
            'a@example.test',
            'bad-password',
            verifyChallenge: (_) async => 'token-${++attempt}',
          ),
          throwsA(isA<GreenhouseException>()),
        );
      }
      expect(tokens, ['token-1', 'token-2']);
    },
  );
}

http.Response jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
