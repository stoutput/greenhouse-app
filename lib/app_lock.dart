import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'greenhouse_client.dart';

/// The PIN protects only the current in-memory session, never the saved token.
class AppLock {
  static const _key = 'greenhouse.lock_pin';
  static const _enabledKey = 'greenhouse.lock_enabled';
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'greenhouse_app_lock'),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  bool enabled = true;
  bool hasPin = false;
  int failures = 0;
  DateTime? retryAt;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_enabledKey) ?? true;
    try {
      hasPin = await _storage.read(key: _key) != null;
    } catch (_) {
      // A fresh sign-in can set a new PIN if the device storage was reset.
      hasPin = false;
    }
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _key);
    hasPin = false;
    failures = 0;
    retryAt = null;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_enabledKey, value)) {
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
    await _storage.write(key: _key, value: '$salt:${_derive(pin, salt)}');
    hasPin = true;
    failures = 0;
    retryAt = null;
  }

  Future<bool> verify(String pin) async {
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) return false;
    final stored = await _storage.read(key: _key);
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
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.lock,
    required this.client,
    required this.setup,
    required this.onUnlocked,
    required this.onSignOut,
  });
  final AppLock lock;
  final GreenhouseClient client;
  final bool setup;
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
  int biometricFailures = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!widget.setup) {
      WidgetsBinding.instance.addPostFrameCallback((_) => biometric());
    }
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
      generation++;
    } else if (state == AppLifecycleState.resumed) {
      foreground = true;
      if (!widget.setup) {
        WidgetsBinding.instance.addPostFrameCallback((_) => biometric());
      }
    }
  }

  Future<void> complete(int attempt) async {
    await widget.client.validateSession();
    if (mounted && foreground && attempt == generation) widget.onUnlocked();
  }

  Future<void> biometric() async {
    if (busy ||
        widget.setup ||
        !widget.client.hasBiometricSession ||
        biometricFailures >= 3 ||
        !foreground) {
      return;
    }
    final attempt = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final success = await widget.client.authenticateLocally();
      if (!mounted || attempt != generation || !foreground) return;
      if (success) {
        await complete(attempt);
      } else {
        biometricFailures++;
        if (mounted) {
          setState(() => error = 'Biometrics did not unlock. Enter your PIN.');
        }
      }
    } catch (_) {
      if (mounted && attempt == generation) {
        setState(
          () => error = 'Could not verify your session. Retry or sign out.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    final value = pin.text;
    if (!RegExp(r'^\d{6,12}$').hasMatch(value)) {
      setState(() => error = 'Enter a PIN of 6 to 12 digits.');
      return;
    }
    if (widget.setup && first == null) {
      setState(() {
        first = value;
        pin.clear();
        error = null;
      });
      return;
    }
    if (widget.setup && first != value) {
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
      if (widget.setup) {
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
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.setup
                    ? (first == null ? 'Set an unlock PIN' : 'Confirm your PIN')
                    : 'GreenHouse is locked',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                widget.setup
                    ? 'Use this PIN to unlock your current session when you return to the app.'
                    : 'Enter your PIN to return to your session.',
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(widget.setup ? 'Continue' : 'Unlock'),
              ),
              if (!widget.setup &&
                  widget.client.hasBiometricSession &&
                  biometricFailures < 3)
                TextButton(
                  onPressed: busy ? null : biometric,
                  child: const Text('Use biometrics'),
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
  );
}
