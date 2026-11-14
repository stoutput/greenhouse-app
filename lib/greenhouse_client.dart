import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';

typedef Json = Map<String, dynamic>;

/// A greenhouse found on the local network.
@immutable
class DiscoveredGreenhouse {
  const DiscoveredGreenhouse({required this.origin, required this.name});

  final Uri origin;
  final String name;

  @override
  String toString() => 'DiscoveredGreenhouse($name, $origin)';
}

/// An error returned by, or while talking to, a greenhouse.
class GreenhouseException implements Exception {
  const GreenhouseException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => statusCode == null
      ? 'GreenhouseException: $message'
      : 'GreenhouseException($statusCode): $message';
}

enum HouseholdRole { owner, admin, gardener, unknown }

@immutable
class HouseholdPermissions {
  const HouseholdPermissions(this.role);

  final HouseholdRole role;

  bool get canManageSharedFinances =>
      role == HouseholdRole.owner || role == HouseholdRole.admin;

  bool get canAcknowledgeNotifications =>
      role != HouseholdRole.gardener && role != HouseholdRole.unknown;
}

@immutable
class HouseholdIdentity {
  const HouseholdIdentity({
    required this.memberId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.householdId,
    required this.owner,
  });

  final String email;
  final String memberId;
  final String? displayName;
  final HouseholdRole role;
  final String householdId;
  final Json owner;

  HouseholdPermissions get permissions => HouseholdPermissions(role);

  static HouseholdIdentity? fromJson(Object? value) {
    if (value is! Map) return null;
    final owner = value.map((key, value) => MapEntry('$key', value));
    final email = owner['email'];
    final memberId = owner['id'];
    final householdId = owner['householdId'];
    final rawRole = owner['role'];
    if (memberId is! String ||
        memberId.trim().isEmpty ||
        email is! String ||
        email.trim().isEmpty ||
        householdId is! String ||
        householdId.trim().isEmpty ||
        rawRole is! String ||
        rawRole.trim().isEmpty) {
      return null;
    }
    return HouseholdIdentity(
      memberId: memberId.trim(),
      email: email.trim(),
      displayName: owner['displayName'] is String
          ? (owner['displayName'] as String).trim()
          : null,
      role: switch (rawRole) {
        'owner' => HouseholdRole.owner,
        'admin' => HouseholdRole.admin,
        'gardener' => HouseholdRole.gardener,
        _ => HouseholdRole.unknown,
      },
      householdId: householdId.trim(),
      owner: owner,
    );
  }

  String preferenceScope(Uri? origin) => sha256
      .convert(
        utf8.encode('${origin?.toString() ?? ''}|$householdId|$memberId'),
      )
      .toString();

  String preferenceKey(String name, Uri? origin) =>
      'greenhouse.$name.${preferenceScope(origin)}';
}

/// Client for a single greenhouse.
///
/// One instance is expected to live for the lifetime of the app. The origin is
/// the only network state that is persisted; the bearer token lives in memory
/// unless the user explicitly enables biometric unlock.
class GreenhouseClient {
  GreenhouseClient({
    this.onUnauthorized,
    this.onNotification,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const _originKey = 'greenhouse.origin';
  static const _deviceIdKey = 'greenhouse.device_id';
  static const _pushEnabledKey = 'greenhouse.push_enabled';
  static const _biometricKey = 'greenhouse.biometric_session';
  static const _biometricOriginKey = 'greenhouse.biometric_origin';
  static const _biometricScopeKey = 'greenhouse.biometric_scope';
  static const _serviceType = '_greenhouse._tcp';
  static const _requestTimeout = Duration(seconds: 15);
  static const _discoveryWindow = Duration(seconds: 4);

  // Optional push is enabled only when every Firebase value is supplied.
  static const _firebaseApiKey = String.fromEnvironment(
    'GREENHOUSE_FIREBASE_API_KEY',
  );
  static const _firebaseAppId = String.fromEnvironment(
    'GREENHOUSE_FIREBASE_APP_ID',
  );
  static const _firebaseSenderId = String.fromEnvironment(
    'GREENHOUSE_FIREBASE_SENDER_ID',
  );
  static const _firebaseProjectId = String.fromEnvironment(
    'GREENHOUSE_FIREBASE_PROJECT_ID',
  );

  final VoidCallback? onUnauthorized;
  final VoidCallback? onNotification;

  final http.Client _http;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );

  SharedPreferences? _preferences;
  Uri? _origin;
  String? _token;
  HouseholdIdentity? _identity;
  bool _initialized = false;
  bool _hasBiometricSession = false;
  bool _pushEnabled = false;

  // Incremented whenever the authenticated session is replaced or ended, so
  // in-flight unlocks and sign-ins cannot commit state after a logout.
  int _authGeneration = 0;
  int _originGeneration = 0;
  int _pushGeneration = 0;

  FirebaseMessaging? _messaging;
  bool _firebaseReady = false;
  String? _pushToken;
  Future<void> _pushUpdates = Future.value();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  /// The currently selected greenhouse, if any.
  Uri? get origin => _origin;

  /// Whether a token for the selected origin is held in secure storage.
  ///
  /// This only checks for the credential's existence; it is never validated by
  /// [initialize].
  bool get hasBiometricSession => _hasBiometricSession;

  /// Whether a bearer token is currently held in memory.
  bool get isSignedIn => _token != null;

  HouseholdIdentity? get identity => _identity;

  HouseholdPermissions get permissions =>
      _identity?.permissions ??
      const HouseholdPermissions(HouseholdRole.unknown);

  /// Whether Firebase is configured and initialized.
  bool get pushAvailable => _firebaseReady;

  /// Whether the user has opted in to push for this device.
  bool get pushEnabled => _pushEnabled;

  /// Restores the selected origin and checks for a saved biometric credential.
  ///
  /// No network request, biometric prompt, or password read happens here.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await _preferencesInstance();
      final savedOrigin = prefs.getString(_originKey);
      if (savedOrigin != null) {
        _origin = _canonicalOrigin(savedOrigin);
        if (_origin == null) {
          await prefs.remove(_originKey);
        }
      }
      _pushEnabled = false;
    } catch (_) {
      // Preferences are recoverable; manual connection still works.
    }

    await _refreshBiometricMarker();
    await _initializeFirebase();
  }

  /// Scans the local network for greenhouses and validates their HTTPS info
  /// endpoints. Returns the candidates that responded correctly.
  Future<List<DiscoveredGreenhouse>> discover() async {
    nsd.Discovery? discovery;
    final candidates = <String, _Candidate>{};

    try {
      discovery = await nsd.startDiscovery(_serviceType);
      await Future<void>.delayed(_discoveryWindow);
      for (final service in discovery.services) {
        final candidate = _candidateFromService(service);
        if (candidate != null) {
          candidates.putIfAbsent(candidate.origin.toString(), () => candidate);
        }
      }
    } catch (_) {
      // Missing Bonjour permission, no network, or no NSD support: no results.
    } finally {
      if (discovery != null) {
        try {
          await nsd.stopDiscovery(discovery);
        } catch (_) {}
      }
    }

    final validated = await Future.wait(
      candidates.values.map((candidate) async {
        try {
          final info = await _fetchInfo(
            candidate.origin,
            timeout: const Duration(seconds: 3),
          );
          return DiscoveredGreenhouse(
            origin: candidate.origin,
            name: info.name,
          );
        } catch (_) {
          return null;
        }
      }),
    );

    return List.unmodifiable(validated.whereType<DiscoveredGreenhouse>());
  }

  /// Validates and selects a greenhouse. The origin is persisted only after
  /// the greenhouse confirms it is initialized and speaks the expected API.
  Future<String> connect(String address) async {
    final origin = _canonicalOrigin(address);
    if (origin == null) {
      throw const GreenhouseException(
        'Enter a valid HTTPS greenhouse address.',
      );
    }

    final info = await _fetchInfo(origin);
    if (info.service != 'greenhouse' || info.version != 1) {
      throw const GreenhouseException(
        'That address does not look like a greenhouse.',
      );
    }
    if (info.setupRequired) {
      throw const GreenhouseException(
        'This greenhouse still needs to be set up.',
      );
    }

    final changed = _origin != origin;
    _origin = origin;
    if (changed) {
      _originGeneration++;
      _authGeneration++;
      _token = null;
      _identity = null;
      _pushEnabled = false;
      _pushToken = null;
    }

    try {
      final prefs = await _preferencesInstance();
      await prefs.setString(_originKey, origin.toString());
    } catch (_) {
      // The connection is still usable for this run without persistence.
    }

    await _refreshBiometricMarker();
    return info.name;
  }

  /// Signs in and returns the current household identity. The token stays in
  /// memory only.
  Future<HouseholdIdentity> signIn(
    String email,
    String password, {
    Future<String?> Function(Uri challengeUrl)? verifyChallenge,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const GreenhouseException('Email and password are required.');
    }

    final origin = _origin;
    if (origin == null) {
      throw const GreenhouseException('Choose a greenhouse first.');
    }

    final generation = ++_authGeneration;
    // Refresh before each password attempt: server settings can change while
    // this device stays linked. Older servers omit the optional flag.
    final info = await _fetchInfo(origin);
    if (generation != _authGeneration || _origin != origin) {
      throw const GreenhouseException('Sign in was cancelled.');
    }
    String? challengeToken;
    if (info.turnstileRequired) {
      if (verifyChallenge == null) {
        throw const GreenhouseException('Complete verification to sign in.');
      }
      challengeToken = await verifyChallenge(
        origin.resolve('/api/v1/mobile/challenge'),
      );
      if (challengeToken == null) {
        throw const GreenhouseException('Verification was cancelled.');
      }
      if (challengeToken.trim().isEmpty || challengeToken.length > 2048) {
        throw const GreenhouseException('Verification failed. Try again.');
      }
    }
    if (generation != _authGeneration || _origin != origin) {
      throw const GreenhouseException('Sign in was cancelled.');
    }
    final devices = await _deviceDetails();
    if (generation != _authGeneration || _origin != origin) {
      throw const GreenhouseException('Sign in was cancelled.');
    }
    final result = await _send(
      origin: origin,
      path: '/mobile/login',
      method: 'POST',
      publicRoute: true,
      body: {
        'email': email.trim(),
        'password': password,
        ...devices,
        'cf-turnstile-response': ?challengeToken,
      },
    );

    if (generation != _authGeneration || _origin != origin) {
      throw const GreenhouseException('Sign in was cancelled.');
    }

    final token = result['token'];
    final identity = HouseholdIdentity.fromJson(result['owner']);
    if (token is! String || token.isEmpty || identity == null) {
      throw const GreenhouseException(
        'The greenhouse returned an invalid sign-in response.',
      );
    }

    // A successful password sign-in replaces this device's server session, so
    // any saved biometric token for the prior identity is stale.
    if (!await _clearBiometricCredential()) {
      throw const GreenhouseException(
        'Could not clear the previous biometric session. Sign in again after restarting the app.',
      );
    }
    if (generation != _authGeneration || _origin != origin) {
      throw const GreenhouseException('Sign in was cancelled.');
    }

    _authGeneration++;
    _token = token;
    _identity = identity;
    final sessionGeneration = _authGeneration;
    await _restoreAccountPreferences(identity, sessionGeneration);
    if (sessionGeneration != _authGeneration || _token != token) {
      throw const GreenhouseException('Sign in was cancelled.');
    }
    unawaited(_syncPushAfterAuth());
    return identity;
  }

  /// Prompts for biometrics, then validates the saved session with the server.
  ///
  /// Returns the owner on success, or null when biometrics were unavailable,
  /// cancelled, or the saved session is no longer valid.
  Future<HouseholdIdentity?> unlock() async {
    final origin = _origin;
    if (origin == null) return null;

    final generation = _authGeneration;
    final originGeneration = _originGeneration;
    if (!await canUseBiometrics()) return null;

    // The secure-store read itself is gated by the OS biometric prompt.
    final saved = await _readBiometricSession();
    if (saved == null || saved.origin != origin) return null;
    if (generation != _authGeneration ||
        originGeneration != _originGeneration ||
        _origin != origin) {
      return null;
    }

    Json response;
    try {
      response = await _send(
        origin: origin,
        path: '/auth/session',
        token: saved.token,
        publicRoute: true,
      );
    } on GreenhouseException catch (error) {
      if (error.statusCode == 401) {
        if (generation == _authGeneration &&
            originGeneration == _originGeneration) {
          await _clearBiometricCredential();
        }
        return null;
      }
      rethrow;
    }

    if (generation != _authGeneration ||
        originGeneration != _originGeneration ||
        _origin != origin) {
      return null;
    }

    final identity = _sessionOwner(response);
    if (identity == null || saved.scope != identity.preferenceScope(origin)) {
      await _discardStaleCredential(saved.token);
      return null;
    }

    _authGeneration++;
    _token = saved.token;
    _identity = identity;
    _hasBiometricSession = true;
    final sessionGeneration = _authGeneration;
    await _restoreAccountPreferences(identity, sessionGeneration);
    if (sessionGeneration != _authGeneration || _token != saved.token) {
      return null;
    }
    unawaited(_syncPushAfterAuth());
    return identity;
  }

  /// Checks that the current in-memory session remains valid on the server.
  Future<void> validateSession() async {
    final response = await request('/auth/session');
    final identity = _sessionOwner(response);
    if (identity == null) {
      throw const GreenhouseException('Invalid session response.');
    }
    final previousScope = _identity?.preferenceScope(_origin);
    _identity = identity;
    if (previousScope != identity.preferenceScope(_origin)) {
      await _restoreAccountPreferences(identity, _authGeneration);
    }
  }

  bool _sharedMutation(String path, String method) {
    if (method.toUpperCase() == 'GET' || method.toUpperCase() == 'HEAD') {
      return false;
    }
    final normalized = path.startsWith('/') ? path : '/$path';
    return RegExp(r'^/accounts/[^/]+/name$').hasMatch(normalized) ||
        RegExp(r'^/transactions/[^/]+/annotation$').hasMatch(normalized);
  }

  String _pushPreferenceKey(HouseholdIdentity? identity, Uri? origin) =>
      identity == null
      ? _pushEnabledKey
      : identity.preferenceKey('push_enabled', origin);

  Future<void> _restoreAccountPreferences(
    HouseholdIdentity identity,
    int generation,
  ) async {
    var enabled = false;
    try {
      enabled =
          (await _preferencesInstance()).getBool(
            _pushPreferenceKey(identity, _origin),
          ) ==
          true;
    } catch (_) {}
    if (generation != _authGeneration || _identity != identity) return;
    _pushEnabled = enabled;
    try {
      await _messaging?.setAutoInitEnabled(enabled);
    } catch (_) {}
  }

  /// Authenticates locally without reading or recovering a session token.
  Future<bool> hasDeviceLock() => _localAuth.isDeviceSupported();

  Future<bool> authenticateLocally() => _localAuth.authenticate(
    localizedReason: 'Unlock GreenHouse',
    biometricOnly: false,
    persistAcrossBackgrounding: false,
  );

  /// Whether this device has biometric hardware with an enrolment.
  Future<bool> canUseBiometrics() async {
    try {
      final available = await _localAuth.getAvailableBiometrics();
      return Platform.isAndroid
          ? available.contains(BiometricType.strong)
          : available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Explicitly prompts for biometrics, then saves the current token.
  Future<bool> rememberWithBiometrics() async {
    final origin = _origin;
    final token = _token;
    final identity = _identity;
    if (origin == null || token == null || identity == null) return false;
    if (!await canUseBiometrics()) return false;

    final generation = _authGeneration;
    final originGeneration = _originGeneration;
    if (!Platform.isAndroid &&
        !await _promptBiometrics('Enable biometric unlock')) {
      return false;
    }
    if (generation != _authGeneration ||
        originGeneration != _originGeneration ||
        _origin != origin ||
        _token != token) {
      return false;
    }

    try {
      await _secureStorage.write(
        key: _biometricKey,
        value: jsonEncode({
          'origin': origin.toString(),
          'scope': identity.preferenceScope(origin),
          'token': token,
        }),
      );
      if (generation != _authGeneration ||
          originGeneration != _originGeneration ||
          _origin != origin ||
          _token != token) {
        await _discardStaleCredential(token, force: true);
        return false;
      }
      final prefs = await _preferencesInstance();
      if (!await prefs.setString(_biometricOriginKey, origin.toString())) {
        await _discardStaleCredential(token, force: true);
        return false;
      }
      if (!await prefs.setString(
        _biometricScopeKey,
        identity.preferenceScope(origin),
      )) {
        await _discardStaleCredential(token, force: true);
        return false;
      }
      if (generation != _authGeneration ||
          originGeneration != _originGeneration ||
          _origin != origin ||
          _token != token) {
        await _discardStaleCredential(token, force: true);
        return false;
      }
      _hasBiometricSession = true;
      return true;
    } catch (_) {
      await _discardStaleCredential(token, force: true);
      return false;
    }
  }

  /// Removes the biometric credential without ending the current session.
  Future<void> forgetBiometrics() async {
    _authGeneration++;
    await _clearBiometricCredential();
  }

  /// Ends the current session and removes its biometric credential.
  ///
  /// Returns true when there was no token to revoke or the server confirmed
  /// the DELETE with 204, and local cleanup succeeded.
  Future<bool> signOut() => _endSession(clearOrigin: false);

  /// Clears the selected origin, push opt-in, and session.
  Future<bool> disconnect() => _endSession(clearOrigin: true);

  Future<bool> _endSession({required bool clearOrigin}) async {
    final origin = _origin;
    final token = _token;
    final identity = _identity;
    final hadBiometricSession = _hasBiometricSession;
    final removePushToken = clearOrigin && _pushEnabled;

    _authGeneration++;
    _pushGeneration++;
    if (clearOrigin) {
      _originGeneration++;
      _origin = null;
      _pushEnabled = false;
      _pushToken = null;
    }
    _token = null;
    _identity = null;
    _pushEnabled = false;

    var localOk = await _clearBiometricCredential();
    if (clearOrigin) {
      try {
        final prefs = await _preferencesInstance();
        if (prefs.containsKey(_originKey) && !await prefs.remove(_originKey)) {
          localOk = false;
        }
        final pushKey = _pushPreferenceKey(identity, origin);
        if (prefs.containsKey(pushKey) && !await prefs.remove(pushKey)) {
          localOk = false;
        }
      } catch (_) {
        localOk = false;
      }
    }
    try {
      await _messaging?.setAutoInitEnabled(false);
    } catch (_) {
      localOk = false;
    }
    if (clearOrigin) {
      try {
        if (removePushToken) {
          // Invalidate this installation's Firebase token even if the old instance is offline.
          await _messaging?.deleteToken().timeout(const Duration(seconds: 5));
        }
      } catch (_) {
        localOk = false;
      }
    }

    var revoked = token == null && !hadBiometricSession;
    if (token != null && origin != null) {
      revoked = await _revokeSession(origin, token);
    }
    return localOk && revoked;
  }

  Future<bool> _revokeSession(Uri origin, String token) async {
    try {
      await _send(
        origin: origin,
        path: '/mobile/session',
        method: 'DELETE',
        token: token,
        publicRoute: true,
        expectedStatus: 204,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Calls an app route under `/api/v1` on the selected greenhouse.
  Future<Json> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    final origin = _origin;
    if (origin == null) {
      throw const GreenhouseException('Choose a greenhouse first.');
    }
    if (_token == null) {
      throw const GreenhouseException('Sign in first.');
    }
    if (_sharedMutation(path, method) && !permissions.canManageSharedFinances) {
      throw const GreenhouseException(
        'Your household role does not allow this change.',
        statusCode: 403,
      );
    }
    final token = _token!;
    final generation = _authGeneration;
    final response = await _send(
      origin: origin,
      path: path,
      method: method,
      body: body,
      query: query,
      token: token,
    );
    if (generation != _authGeneration || _origin != origin || _token != token) {
      throw const GreenhouseException(
        'This request belongs to an older session.',
      );
    }
    return response;
  }

  /// Enables or disables push for the selected greenhouse.
  ///
  /// Permission is requested only when enabling. Returns false when push is
  /// unavailable, permission is denied, or registration fails.
  Future<bool> setPushEnabled(bool enabled) async {
    final pushGeneration = ++_pushGeneration;
    if (!enabled) {
      final wasEnabled = _pushEnabled;
      _pushEnabled = false;
      if (_token != null) {
        if (_origin == null) return false;
        try {
          await _sendPushToken(null, pushGeneration: pushGeneration);
        } catch (_) {
          if (pushGeneration == _pushGeneration) _pushEnabled = wasEnabled;
          return false;
        }
        if (pushGeneration != _pushGeneration) return false;
      }
      try {
        final prefs = await _preferencesInstance();
        if (!await prefs.setBool(
          _pushPreferenceKey(_identity, _origin),
          false,
        )) {
          return false;
        }
        await _messaging?.setAutoInitEnabled(false);
      } catch (_) {
        return false;
      }
      return true;
    }

    final origin = _origin;
    if (!pushAvailable || origin == null || _token == null) return false;

    final generation = _authGeneration;
    final originGeneration = _originGeneration;
    try {
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      if (pushGeneration != _pushGeneration ||
          generation != _authGeneration ||
          originGeneration != _originGeneration ||
          _origin != origin ||
          _token == null) {
        return false;
      }

      await _messaging!.setAutoInitEnabled(true);
      final token = await _loadPushToken();
      if (token == null) {
        if (pushGeneration == _pushGeneration) _pushEnabled = false;
        return false;
      }
      await _sendPushToken(
        token,
        generation: generation,
        originGeneration: originGeneration,
        pushGeneration: pushGeneration,
      );
      if (pushGeneration != _pushGeneration ||
          generation != _authGeneration ||
          originGeneration != _originGeneration ||
          _origin != origin ||
          _token == null) {
        if (pushGeneration == _pushGeneration) _pushEnabled = false;
        return false;
      }
      final prefs = await _preferencesInstance();
      if (!await prefs.setBool(_pushPreferenceKey(_identity, origin), true)) {
        await _sendPushToken(null, pushGeneration: pushGeneration);
        return false;
      }
      _pushEnabled = true;
      return true;
    } catch (_) {
      if (pushGeneration == _pushGeneration) _pushEnabled = false;
      return false;
    }
  }

  /// Releases client resources. The instance cannot be used afterwards.
  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    _http.close();
  }

  Future<void> _initializeFirebase() async {
    if (_firebaseApiKey.isEmpty ||
        _firebaseAppId.isEmpty ||
        _firebaseSenderId.isEmpty ||
        _firebaseProjectId.isEmpty) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: _firebaseApiKey,
            appId: _firebaseAppId,
            messagingSenderId: _firebaseSenderId,
            projectId: _firebaseProjectId,
          ),
        );
      }

      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      _firebaseReady = true;

      _tokenSubscription = messaging.onTokenRefresh.listen(_tokenRefreshed);
      _messageSubscription = FirebaseMessaging.onMessage.listen((_) {
        onNotification?.call();
      });
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((_) {
        onNotification?.call();
      });

      try {
        await messaging.setAutoInitEnabled(_pushEnabled);
      } catch (_) {}

      try {
        final initial = await messaging.getInitialMessage().timeout(
          const Duration(seconds: 5),
        );
        if (initial != null) onNotification?.call();
      } catch (_) {}
    } catch (_) {
      _firebaseReady = false;
    }
  }

  void _tokenRefreshed(String token) {
    _pushToken = token;
    if (!_pushEnabled || _token == null || _origin == null) return;
    final generation = _authGeneration;
    final originGeneration = _originGeneration;
    final pushGeneration = _pushGeneration;
    unawaited(
      _sendPushToken(
        token,
        generation: generation,
        originGeneration: originGeneration,
        pushGeneration: pushGeneration,
      ).catchError((_) {}),
    );
  }

  Future<String?> _loadPushToken() async {
    if (!_firebaseReady) return null;
    try {
      final token = await _messaging!.getToken();
      if (token != null && token.isNotEmpty) _pushToken = token;
      return _pushToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncPushAfterAuth() async {
    if (!_pushEnabled || !pushAvailable || _origin == null || _token == null) {
      return;
    }
    final generation = _authGeneration;
    final originGeneration = _originGeneration;
    final pushGeneration = _pushGeneration;
    try {
      final token = await _loadPushToken();
      if (token == null) return;
      await _sendPushToken(
        token,
        generation: generation,
        originGeneration: originGeneration,
        pushGeneration: pushGeneration,
      );
    } catch (_) {}
  }

  Future<void> _sendPushToken(
    String? token, {
    int? generation,
    int? originGeneration,
    int? pushGeneration,
  }) {
    final origin = _origin;
    final authToken = _token;
    final update = _pushUpdates.then((_) async {
      if (generation != null &&
          (generation != _authGeneration ||
              originGeneration != _originGeneration)) {
        return;
      }
      if (pushGeneration != null && pushGeneration != _pushGeneration) return;
      if (origin == null ||
          authToken == null ||
          _origin != origin ||
          _token != authToken) {
        return;
      }
      await _send(
        origin: origin,
        path: '/mobile/push-token',
        method: 'PUT',
        token: authToken,
        body: {'token': token},
      );
    });
    // Keep the queue usable after a failed request while returning that error to its caller.
    _pushUpdates = update.catchError((_) {});
    return update;
  }

  Future<_Info> _fetchInfo(Uri origin, {Duration? timeout}) async {
    final json = await _send(
      origin: origin,
      path: '/mobile/info',
      publicRoute: true,
      timeout: timeout,
    );
    final service = json['service'];
    final version = json['version'];
    final name = json['name'];
    final setupRequired = json['setupRequired'];
    if (service != 'greenhouse' ||
        version is! num ||
        version != 1 ||
        name is! String ||
        name.trim().isEmpty ||
        setupRequired is! bool ||
        (json['turnstileRequired'] != null &&
            json['turnstileRequired'] is! bool)) {
      throw const GreenhouseException(
        'The greenhouse returned an invalid info response.',
      );
    }
    return _Info(
      service: service as String,
      version: version,
      name: name.trim(),
      setupRequired: setupRequired,
      turnstileRequired: json['turnstileRequired'] == true,
    );
  }

  _Candidate? _candidateFromService(nsd.Service service) {
    final bytes = service.txt?['origin'];
    if (bytes == null) return null;
    try {
      final raw = utf8.decode(bytes);
      final origin = _canonicalOrigin(raw);
      if (origin == null) return null;
      return _Candidate(origin: origin);
    } catch (_) {
      return null;
    }
  }

  Future<Json> _send({
    required Uri origin,
    required String path,
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
    String? token,
    bool publicRoute = false,
    Duration? timeout,
    int? expectedStatus,
  }) async {
    final normalizedPath = _normalizePath(path);
    var uri = Uri.parse('${origin.toString()}/api/v1$normalizedPath');
    if (!uri.path.startsWith('/api/v1/')) {
      throw const GreenhouseException('Invalid API path.');
    }
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    final request = http.Request(method, uri)..followRedirects = false;
    request.headers['accept'] = 'application/json';
    if (token != null) {
      request.headers['authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? _requestTimeout);
    } on TimeoutException catch (error) {
      throw GreenhouseException(
        'The greenhouse took too long to respond.',
        cause: error,
      );
    } on HandshakeException {
      throw const GreenhouseException(
        'The phone could not verify this server’s HTTPS certificate.',
      );
    } catch (error) {
      throw GreenhouseException(
        'Could not reach the greenhouse.',
        cause: error,
      );
    }

    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw GreenhouseException(
        'The greenhouse redirected the request.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 401) {
      if (!publicRoute) {
        await _handleUnauthorized(token);
      }
      throw GreenhouseException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GreenhouseException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    }
    if (expectedStatus != null && response.statusCode != expectedStatus) {
      throw GreenhouseException(
        'The greenhouse did not confirm the request.',
        statusCode: response.statusCode,
      );
    }

    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    final decoded = _decodeJson(response.body);
    if (decoded == null) {
      throw const GreenhouseException(
        'The greenhouse returned an invalid response.',
      );
    }
    return decoded;
  }

  Future<void> _handleUnauthorized(String? tokenUsed) async {
    // A stale 401 must not clear a session that has since been replaced.
    if (tokenUsed != _token) return;
    _authGeneration++;
    _pushGeneration++;
    _token = null;
    _identity = null;
    _pushEnabled = false;
    await _clearBiometricCredential();
    try {
      await _messaging?.setAutoInitEnabled(false);
    } catch (_) {}
    onUnauthorized?.call();
  }

  String _normalizePath(String path) {
    var normalized = path.trim();
    if (normalized.isEmpty) normalized = '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.startsWith('//') ||
        normalized.contains('://') ||
        normalized.contains('?') ||
        normalized.contains('#')) {
      throw const GreenhouseException('Invalid API path.');
    }
    return normalized;
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
        if (error is String && error.trim().isNotEmpty) return error.trim();
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return response.statusCode == 403
        ? 'You do not have permission to make this change.'
        : 'The greenhouse returned error ${response.statusCode}.';
  }

  Json? _decodeJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {}
    return null;
  }

  HouseholdIdentity? _sessionOwner(Json response) =>
      HouseholdIdentity.fromJson(response['owner'] ?? response);

  Uri? _canonicalOrigin(String address) {
    var raw = address.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'https://$raw';

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.hasPort && uri.port < 1)) {
      return null;
    }

    final port = uri.hasPort && uri.port != 443 ? uri.port : null;
    return Uri(scheme: 'https', host: uri.host.toLowerCase(), port: port);
  }

  Future<Json> _deviceDetails() async {
    var hostname = 'unknown';
    var deviceName = 'unknown';
    final platform = Platform.isAndroid ? 'android' : 'ios';

    try {
      final local = Platform.localHostname.trim();
      if (local.isNotEmpty) hostname = local;
    } catch (_) {}

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        deviceName = '${android.manufacturer} ${android.model}'.trim();
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        deviceName = ios.name.isNotEmpty ? ios.name : ios.model;
      }
    } catch (_) {}

    return {
      'deviceId': await _deviceId(),
      'hostname': hostname,
      'deviceName': deviceName,
      'platform': platform,
    };
  }

  Future<String> _deviceId() async {
    try {
      final prefs = await _preferencesInstance();
      final existing = prefs.getString(_deviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final generated = _generateDeviceId();
      await prefs.setString(_deviceIdKey, generated);
      return generated;
    } catch (_) {
      return _generateDeviceId();
    }
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<bool> _promptBiometrics(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<({Uri origin, String token, String scope})?>
  _readBiometricSession() async {
    try {
      final raw = await _secureStorage.read(key: _biometricKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final origin = decoded['origin'];
      final token = decoded['token'];
      final scope = decoded['scope'];
      if (origin is! String ||
          token is! String ||
          token.isEmpty ||
          scope is! String ||
          scope.isEmpty) {
        return null;
      }
      final parsed = _canonicalOrigin(origin);
      if (parsed == null) return null;
      return (origin: parsed, token: token, scope: scope);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshBiometricMarker() async {
    final origin = _origin;
    if (origin == null) {
      _hasBiometricSession = false;
      return;
    }
    try {
      final prefs = await _preferencesInstance();
      final marker = prefs.getString(_biometricOriginKey);
      final scope = prefs.getString(_biometricScopeKey);
      _hasBiometricSession =
          marker != null &&
          _canonicalOrigin(marker) == origin &&
          scope != null &&
          scope.isNotEmpty;
      if (marker != null &&
          _canonicalOrigin(marker) == origin &&
          scope == null) {
        await _clearBiometricCredential();
      }
    } catch (_) {
      _hasBiometricSession = false;
    }
  }

  Future<bool> _clearBiometricCredential({bool force = false}) async {
    var ok = true;
    var marker = false;
    try {
      final prefs = await _preferencesInstance();
      marker = prefs.containsKey(_biometricOriginKey);
      final scopeMarker = prefs.containsKey(_biometricScopeKey);
      final hadCredential =
          force || marker || scopeMarker || _hasBiometricSession;
      if (hadCredential) {
        try {
          await _secureStorage.delete(key: _biometricKey);
        } catch (_) {
          ok = false;
        }
      }
      if (marker && !await prefs.remove(_biometricOriginKey)) ok = false;
      if (scopeMarker && !await prefs.remove(_biometricScopeKey)) ok = false;
      _hasBiometricSession = false;
    } catch (_) {
      ok = false;
    }
    return ok;
  }

  Future<void> _discardStaleCredential(
    String token, {
    bool force = false,
  }) async {
    if (_token == null || _token == token) {
      await _clearBiometricCredential(force: force);
    }
  }

  Future<SharedPreferences> _preferencesInstance() async =>
      _preferences ??= await SharedPreferences.getInstance();
}

class _Info {
  const _Info({
    required this.service,
    required this.version,
    required this.name,
    required this.setupRequired,
    required this.turnstileRequired,
  });

  final String service;
  final num version;
  final String name;
  final bool setupRequired;
  final bool turnstileRequired;
}

class _Candidate {
  const _Candidate({required this.origin});

  final Uri origin;
}
