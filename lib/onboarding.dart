import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'greenhouse_client.dart';
import 'app_lock.dart';
import 'greenhouse_theme.dart';
import 'login_challenge.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({
    required this.client,
    required this.onSignedIn,
    super.key,
  });
  final GreenhouseClient client;
  final ValueChanged<HouseholdIdentity> onSignedIn;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final address = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  List<DiscoveredGreenhouse> results = [];
  bool searched = false;
  bool busy = false;
  bool hidden = true;
  bool unlocking = false;
  bool biometricRetry = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.client.hasBiometricSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unlock());
    }
  }

  Future<void> unlock() => run(() async {
    setState(() {
      unlocking = true;
      biometricRetry = false;
    });
    var succeeded = false;
    try {
      final identity = await widget.client.unlock();
      if (!mounted) return;
      if (identity != null) {
        succeeded = true;
        widget.onSignedIn(identity);
      } else {
        biometricRetry = widget.client.hasBiometricSession;
        if (!biometricRetry) {
          error = 'Your saved session expired or device security changed. Sign in with your password.';
        }
      }
    } catch (_) {
      biometricRetry = widget.client.hasBiometricSession;
      rethrow;
    } finally {
      if (mounted && !succeeded) setState(() => unlocking = false);
    }
  });

  @override
  void dispose() {
    address.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signIn() async {
    if (form.currentState?.validate() != true) return;
    await run(() async {
      final identity = await widget.client.signIn(
        email.text.trim(),
        password.text,
        verifyChallenge: (url) async {
          if (!mounted) return null;
          return Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => LoginChallenge(url: url)),
          );
        },
      );
      if (!mounted) return;
      TextInput.finishAutofillContext();
      password.clear();
      widget.onSignedIn(identity);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (unlocking || biometricRetry) {
      return AuthenticationScreen(onUnlock: unlocking ? null : unlock);
    }
    final theme = Theme.of(context);
    final origin = widget.client.origin;
    final connecting = origin == null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
              shrinkWrap: true,
              children: [
                const Align(alignment: Alignment.centerLeft, child: Brand()),
                const SizedBox(height: 24),
                _EntryBanner(connecting: connecting),
                const SizedBox(height: 20),
                if (connecting) ...[
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final found = await widget.client.discover();
                            if (mounted) {
                              setState(() {
                                results = found;
                                searched = true;
                              });
                            }
                          }),
                    icon: const Icon(Icons.wifi_find_rounded),
                    label: const Text('Search local network'),
                  ),
                  if (searched) ...[
                    const SizedBox(height: 10),
                    if (results.isEmpty)
                      const Text(
                        'No instances found on this network. You can still enter an address below.',
                      ),
                    for (final result in results)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(result.name),
                        subtitle: Text(result.origin.toString()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: busy
                            ? null
                            : () => run(() async {
                                await widget.client.connect(
                                  result.origin.toString(),
                                );
                              }),
                      ),
                  ],
                  const SizedBox(height: 24),
                  Text('Enter an address', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: address,
                    enabled: !busy,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    decoration: const InputDecoration(
                      labelText: 'Instance address',
                      hintText: 'https://greenhouse.example.com',
                    ),
                    onSubmitted: (value) => run(() async {
                      await widget.client.connect(value);
                    }),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.client.connect(address.text);
                          }),
                    child: const Text('Connect'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 17,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          origin.host,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                if (!await widget.client.disconnect() &&
                                    context.mounted) {
                                  showMessage(
                                    context,
                                    'Revoke the old session in Known devices if it is still listed.',
                                  );
                                }
                              }),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (widget.client.hasBiometricSession) ...[
                    FilledButton.icon(
                      onPressed: busy ? null : unlock,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock with biometrics'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  AutofillGroup(
                    onDisposeAction: AutofillContextAction.cancel,
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: email,
                            enabled: !busy,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter your email'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: password,
                            enabled: !busy,
                            obscureText: hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.go,
                            onFieldSubmitted: (_) => signIn(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                tooltip: hidden
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () =>
                                    setState(() => hidden = !hidden),
                                icon: Icon(
                                  hidden
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Enter your password'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: busy ? null : signIn,
                            child: const Text('Sign in'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryBanner extends StatelessWidget {
  const _EntryBanner({required this.connecting});
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.alphaBlend(
                      colors.primary.withValues(alpha: 0.14),
                      colors.surfaceContainer,
                    ),
                    colors.surfaceContainer,
                  ],
                ),
              ),
              child: CustomPaint(
                painter: _GlasshouseLines(
                  colors.primary.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(connecting ? 'Your own instance' : 'Owner access'),
                const SizedBox(height: 14),
                Text(
                  connecting ? 'Find your\nGreenHouse' : 'Welcome back',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  connecting
                      ? 'Connect to the server that holds your accounts, budgets, and activity.'
                      : 'Sign in with your GreenHouse owner account.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlasshouseLines extends CustomPainter {
  const _GlasshouseLines(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final x = size.width * 0.82;
    final y = size.height * 0.32;
    for (var i = 0; i < 5; i++) {
      final inset = i * 13.0;
      final roof = Path()
        ..moveTo(x - 70 + inset, size.height)
        ..lineTo(x - 70 + inset, y + 28 + inset)
        ..lineTo(x, y - 27 + inset)
        ..lineTo(x + 70 - inset, y + 28 + inset)
        ..lineTo(x + 70 - inset, size.height);
      canvas.drawPath(roof, line);
    }
  }

  @override
  bool shouldRepaint(_GlasshouseLines oldDelegate) =>
      oldDelegate.color != color;
}
