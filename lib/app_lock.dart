import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';

/// The PIN protects only the current in-memory session, never the saved token.
class AppLock {
  static const _legacyKey = 'greenhouse.lock_pin';
  static const _legacyEnabledKey = 'greenhouse.lock_enabled';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'greenhouse_app_lock'),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  bool enabled = true;
  bool hasPin = false;
  String? _identityScope;
  int _identityGeneration = 0;
  int failures = 0;
  DateTime? retryAt;

  Future<void> initialize() async {
    enabled = true;
    hasPin = false;
  }

  Future<void> useIdentity(String? scope) async {
    final generation = ++_identityGeneration;
    _identityScope = scope;
    enabled = true;
    hasPin = false;
    if (scope == null) return;
    try {
      final stored = await _storage.read(key: _pinKey);
      final prefs = await SharedPreferences.getInstance();
      if (generation == _identityGeneration) {
        hasPin = stored != null;
        enabled = prefs.getBool(_enabledPreferenceKey) ?? true;
      }
    } catch (_) {
      // A fresh sign-in can set a new PIN if the device storage was reset.
    }
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    hasPin = false;
    failures = 0;
    retryAt = null;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_enabledPreferenceKey, value)) {
      throw Exception('Could not save lock setting.');
    }
    enabled = value;
  }

  String _derive(String pin, String salt) {
    List<int> value = utf8.encode('$salt:$pin');
    for (var i = 0; i < 20000; i++) {
      value = sha256.convert(value).bytes;
    }
    return base64Encode(value);
  }

  Future<void> setPin(String pin) async {
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    await _storage.write(key: _pinKey, value: '$salt:${_derive(pin, salt)}');
    hasPin = true;
    failures = 0;
    retryAt = null;
  }

  Future<bool> verify(String pin) async {
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) return false;
    final stored = await _storage.read(key: _pinKey);
    final parts = stored?.split(':');
    if (parts == null || parts.length != 2) {
      throw Exception('PIN unavailable. Sign in again.');
    }
    final actual = _derive(pin, parts[0]);
    var diff = actual.length ^ parts[1].length;
    for (var i = 0; i < min(actual.length, parts[1].length); i++) {
      diff |= actual.codeUnitAt(i) ^ parts[1].codeUnitAt(i);
    }
    if (diff == 0) {
      failures = 0;
      retryAt = null;
      return true;
    }
    failures++;
    if (failures >= 3) {
      retryAt = DateTime.now().add(
        Duration(seconds: min(300, 30 * (failures - 2))),
      );
    }
    return false;
  }

  String get _pinKey {
    final scope = _identityScope;
    if (scope == null) return _legacyKey;
    final digest = sha256.convert(utf8.encode(scope)).toString();
    return 'greenhouse.lock_pin.$digest';
  }

  String get _enabledPreferenceKey {
    final scope = _identityScope;
    if (scope == null) return _legacyEnabledKey;
    final digest = sha256.convert(utf8.encode(scope)).toString();
    return 'greenhouse.lock_enabled.$digest';
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.client,
    required this.setup,
    this.initialUnlockRequired = false,
    required this.onUnlocked,
    required this.onSignOut,
  });
  final AppLock lock;
  final GreenhouseClient client;
  final bool setup;
  final bool initialUnlockRequired;
  final VoidCallback onUnlocked;
  final Future<void> Function() onSignOut;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  final pin = TextEditingController();
  String? first;
  String? error;
  bool busy = false;
  bool foreground = true;
  int generation = 0;
  bool checkingMethod = true;
  bool deviceLock = false;
  bool settingPin = false;
  bool prompting = false;
  bool methodError = false;
  bool backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    settingPin = widget.setup;
    WidgetsBinding.instance.addPostFrameCallback((_) => checkMethod());
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      foreground = false;
      if (!prompting) {
        backgrounded = true;
        generation++;
      }
    } else if (state == AppLifecycleState.resumed) {
      foreground = true;
      if (!prompting && !busy) {
        WidgetsBinding.instance.addPostFrameCallback((_) => checkMethod());
      }
    }
  }

  Future<void> complete(int attempt) async {
    if (await widget.client.checkBiometricEnrollment(
      lockEnabled: widget.lock.enabled,
    )) {
      if (mounted) await widget.onSignOut();
      return;
    }
    await widget.client.validateSession();
    if (mounted && foreground && attempt == generation) widget.onUnlocked();
  }

  Future<void> checkMethod() async {
    if (!mounted || busy || !foreground) return;
    final attempt = generation;
    setState(() {
      busy = true;
      checkingMethod = true;
      methodError = false;
      error = null;
    });
    try {
      if (await widget.client.checkBiometricEnrollment(
        lockEnabled: widget.lock.enabled,
      )) {
        if (mounted) await widget.onSignOut();
        return;
      }
      final supported = await widget.client.hasDeviceLock();
      if (!mounted || !foreground || attempt != generation) return;
      deviceLock = supported;
      if (supported &&
          widget.setup &&
          !widget.initialUnlockRequired &&
          !backgrounded) {
        if (!widget.lock.enabled) await widget.lock.setEnabled(true);
        await complete(attempt);
      } else if (supported) {
        setState(() {
          checkingMethod = false;
        });
        await deviceAuthenticate(attempt);
      } else {
        setState(() {
          checkingMethod = false;
          settingPin = widget.setup || !widget.lock.hasPin;
        });
      }
    } catch (_) {
      if (mounted && attempt == generation) {
        setState(() {
          checkingMethod = false;
          methodError = true;
          error = 'Could not check device security. Retry or sign out.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (foreground && attempt != generation) {
          WidgetsBinding.instance.addPostFrameCallback((_) => checkMethod());
        }
      }
    }
  }

  Future<void> deviceAuthenticate(int attempt) async {
    final bool success;
    prompting = true;
    try {
      success = await widget.client.authenticateLocally();
    } finally {
      prompting = false;
    }
    if (!mounted || attempt != generation || !foreground) return;
    if (success) {
      if (widget.setup && !widget.lock.enabled) {
        await widget.lock.setEnabled(true);
      }
      await complete(attempt);
    } else {
      setState(
        () => error = 'Device authentication did not unlock. Try again.',
      );
    }
  }

  Future<void> submit() async {
    if (busy) return;
    final value = pin.text;
    if (!RegExp(r'^\d{6,12}$').hasMatch(value)) {
      setState(() => error = 'Enter a PIN of 6 to 12 digits.');
      return;
    }
    if (settingPin && first == null) {
      setState(() {
        first = value;
        pin.clear();
        error = null;
      });
      return;
    }
    if (settingPin && first != value) {
      setState(() {
        first = null;
        pin.clear();
        error = 'PINs did not match. Try again.';
      });
      return;
    }
    final attempt = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (settingPin) {
        await widget.lock.setPin(value);
        if (!widget.lock.enabled) await widget.lock.setEnabled(true);
        await complete(attempt);
      } else if (await widget.lock.verify(value)) {
        await complete(attempt);
      } else if (mounted && attempt == generation) {
        setState(
          () => error =
              widget.lock.retryAt != null &&
                  DateTime.now().isBefore(widget.lock.retryAt!)
              ? 'Too many attempts. Wait before trying again.'
              : 'Incorrect PIN.',
        );
      }
    } catch (_) {
      if (mounted && attempt == generation) {
        setState(
          () => error = 'Could not verify your session. Retry or sign out.',
        );
      }
    } finally {
      if (mounted) {
        pin.clear();
        setState(() => busy = false);
        if (foreground && attempt != generation) {
          WidgetsBinding.instance.addPostFrameCallback((_) => checkMethod());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (checkingMethod || (busy && deviceLock)) {
      return const AuthenticationScreen();
    }
    if (deviceLock || methodError) {
      return AuthenticationScreen(onUnlock: busy ? null : checkMethod);
    }
    return Theme(
      data: greenhouseTheme(Brightness.dark),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  if (settingPin)
                    Text(
                      first == null ? 'Set an unlock PIN' : 'Confirm your PIN',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: Colors.white),
                    )
                  else
                    SvgPicture.asset(
                      'assets/greenhouse-mark.svg',
                      height: 80,
                      semanticsLabel: 'GreenHouse',
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: pin,
                    enabled: !busy,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(labelText: 'Unlock PIN'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(settingPin ? 'Continue' : 'Unlock'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            generation++;
                            await widget.onSignOut();
                          },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty while the OS authenticates; a failed attempt exposes only a retry.
class AuthenticationScreen extends StatelessWidget {
  const AuthenticationScreen({super.key, this.onUnlock});
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) => Theme(
    data: greenhouseTheme(Brightness.dark),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: onUnlock == null
          ? null
          : SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/greenhouse-mark.svg',
                      height: 80,
                      width: 80,
                      semanticsLabel: 'GreenHouse',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: onUnlock,
                      child: const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
