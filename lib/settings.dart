import 'package:flutter/material.dart';

import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';

class CompanionSettings extends StatefulWidget {
  const CompanionSettings({
    required this.client,
    required this.owner,
    required this.mode,
    required this.onTheme,
    required this.onSessionEnded,
    super.key,
  });
  final GreenhouseClient client;
  final Json owner;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<bool> onSessionEnded;

  @override
  State<CompanionSettings> createState() => _CompanionSettingsState();
}

class _CompanionSettingsState extends State<CompanionSettings> {
  late final Future<bool> biometricSupport = widget.client.canUseBiometrics();
  bool busy = false;

  Future<void> apply(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> unlink() async {
    final host = widget.client.origin?.host ?? 'this instance';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Unlink this device?'),
        content: Text(
          'This signs this device out of $host and returns you to instance setup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await apply(() async {
      final revoked = await widget.client.disconnect();
      if (mounted) widget.onSessionEnded(revoked);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: FinanceList(
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Connected instance'),
              const SizedBox(height: 8),
              Text(
                widget.client.origin?.host ?? 'GreenHouse',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(label(widget.owner['email'])),
            ],
          ),
        ),
        const SectionTitle('Appearance'),
        DropdownButtonFormField<ThemeMode>(
          initialValue: widget.mode,
          decoration: const InputDecoration(labelText: 'Theme'),
          items: const [
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Text('System default'),
            ),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
          ],
          onChanged: (value) {
            if (value != null) widget.onTheme(value);
          },
        ),
        const SectionTitle('This device'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: biometricSupport,
                builder: (context, snapshot) {
                  final enabled = widget.client.hasBiometricSession;
                  return SwitchListTile(
                    title: const Text('Biometric unlock'),
                    subtitle: Text(
                      snapshot.data == true || enabled
                          ? 'Unlock a saved session using your device.'
                          : 'Enroll a biometric in device settings to use this.',
                    ),
                    value: enabled,
                    onChanged: !busy && (enabled || snapshot.data == true)
                        ? (value) => apply(() async {
                            if (value) {
                              final saved = await widget.client
                                  .rememberWithBiometrics();
                              if (!saved && context.mounted) {
                                showMessage(
                                  context,
                                  'Biometric unlock was not enabled.',
                                );
                              }
                            } else {
                              await widget.client.forgetBiometrics();
                            }
                          })
                        : null,
                  );
                },
              ),
              SwitchListTile(
                title: const Text('Push notifications'),
                subtitle: Text(
                  widget.client.pushAvailable
                      ? 'Receive GreenHouse alerts on this device.'
                      : 'Push is unavailable on this build.',
                ),
                value: widget.client.pushEnabled,
                onChanged: busy || !widget.client.pushAvailable
                    ? null
                    : (value) => apply(() async {
                        if (!await widget.client.setPushEnabled(value) &&
                            context.mounted) {
                          showMessage(
                            context,
                            'Could not update push notifications. Check permissions and server setup.',
                          );
                        }
                      }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => apply(() async {
                  final revoked = await widget.client.signOut();
                  if (mounted) widget.onSessionEnded(revoked);
                }),
          child: const Text('Sign out'),
        ),
        TextButton.icon(
          onPressed: busy ? null : unlink,
          icon: const Icon(Icons.link_off),
          label: const Text('Unlink device'),
        ),
        TextButton(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'GreenHouse'),
          child: const Text('Open-source licenses'),
        ),
        if (busy) const LinearProgressIndicator(),
      ],
    ),
  );
}
