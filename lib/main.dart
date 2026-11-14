import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'ambient_lighting.dart';
import 'app_lock.dart';
import 'cards.dart';
import 'companion_navigation.dart';
import 'finance_widgets.dart';
import 'greenhouse_client.dart';
import 'greenhouse_theme.dart';
import 'onboarding.dart';
import 'overview.dart';
import 'planning.dart';
import 'settings.dart';
import 'transactions.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GreenHouseApp());
}

class GreenHouseApp extends StatefulWidget {
  const GreenHouseApp({super.key, this.client});
  final GreenhouseClient? client;

  @override
  State<GreenHouseApp> createState() => _GreenHouseAppState();
}

class _GreenHouseAppState extends State<GreenHouseApp>
    with WidgetsBindingObserver {
  final appLock = AppLock();
  bool locked = false;
  bool setupPin = false;
  bool setupRequiresAuthentication = false;
  bool offerBiometrics = false;
  bool checkingBiometrics = false;
  bool wasBackgrounded = false;
  bool foreground = true;
  bool privacyCover = false;
  final navigation = GlobalKey<NavigatorState>();
  final messages = GlobalKey<ScaffoldMessengerState>();
  final notificationRevision = ValueNotifier(0);
  late final GreenhouseClient client;
  ThemeMode mode = ThemeMode.system;
  bool lightingEnabled = true;
  HouseholdIdentity? owner;
  bool ready = false;
  int entryRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    client =
        widget.client ??
        GreenhouseClient(
          onUnauthorized: () {
            if (!mounted || owner == null) return;
            endSession();
            notice(
              'Your session has expired or access was revoked. Sign in again.',
            );
          },
          onNotification: () {
            if (!mounted) return;
            notificationRevision.value++;
            if (owner != null) {
              notice('You have a new GreenHouse notification.');
            }
          },
        );
    initialize();
  }

  Future<void> initialize() async {
    await client.initialize();
    await appLock.initialize();
    if (!mounted) return;
    setState(() => ready = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationRevision.dispose();
    if (widget.client == null) client.dispose();
    super.dispose();
  }

  void notice(String text) {
    messages.currentState?.showSnackBar(SnackBar(content: Text(text)));
  }

  void endSession() {
    navigation.currentState?.popUntil((route) => route.isFirst);
    unawaited(appLock.useIdentity(null));
    setState(() {
      owner = null;
      mode = ThemeMode.system;
      lightingEnabled = true;
      locked = false;
      setupPin = false;
      offerBiometrics = false;
      checkingBiometrics = false;
      entryRevision++;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cover = state != AppLifecycleState.resumed && appLock.enabled;
    if (cover != privacyCover) setState(() => privacyCover = cover);
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      foreground = false;
    }
    if (state == AppLifecycleState.resumed) {
      foreground = true;
      if (owner != null && (!appLock.enabled || !locked)) {
        unawaited(refreshIdentity());
      }
    }
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        owner != null &&
        appLock.enabled) {
      wasBackgrounded = true;
      if (setupPin) setupRequiresAuthentication = true;
      if (!locked) setState(() => locked = true);
    } else if (state == AppLifecycleState.resumed && wasBackgrounded) {
      wasBackgrounded = false;
      if (owner != null && appLock.enabled && !locked) {
        setState(() => locked = true);
      }
    }
  }

  @override
  Future<bool> didPopRoute() async => owner != null && locked;

  Future<void> signedIn(HouseholdIdentity value) async {
    final scope = value.preferenceScope(client.origin);
    final appearanceKey = value.preferenceKey('appearance', client.origin);
    final biometricOfferKey = value.preferenceKey(
      'biometric_offer_shown',
      client.origin,
    );
    await appLock.useIdentity(scope);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final restoredMode =
        ThemeMode.values
            .where((item) => item.name == prefs.getString(appearanceKey))
            .firstOrNull ??
        ThemeMode.system;
    setState(() {
      owner = value;
      mode = restoredMode;
      lightingEnabled =
          prefs.getBool(
            value.preferenceKey('ambient_lighting', client.origin),
          ) ??
          true;
      setupPin = appLock.enabled && !appLock.hasPin;
      setupRequiresAuthentication = !foreground;
      offerBiometrics = false;
      checkingBiometrics = !client.hasBiometricSession;
      locked = setupPin || (appLock.enabled && !foreground);
    });
    if (!checkingBiometrics) return;
    try {
      final shown = prefs.getBool(biometricOfferKey) == true;
      final supported = !shown && await client.canUseBiometrics();
      if (!mounted || owner != value) return;
      setState(() {
        checkingBiometrics = false;
        offerBiometrics = supported;
      });
    } catch (_) {
      if (mounted && owner == value) setState(() => checkingBiometrics = false);
    }
  }

  void finishBiometricOffer() {
    setState(() => offerBiometrics = false);
    final key = owner?.preferenceKey('biometric_offer_shown', client.origin);
    if (key == null) return;
    unawaited(
      SharedPreferences.getInstance().then((prefs) => prefs.setBool(key, true)),
    );
  }

  Future<void> setLockEnabled(bool enabled) async {
    if (enabled && !appLock.hasPin) {
      setState(() {
        setupPin = true;
        setupRequiresAuthentication = !foreground;
        locked = true;
      });
      return;
    }
    await appLock.setEnabled(enabled);
    if (mounted) {
      setState(() {
        if (enabled && !foreground && owner != null) locked = true;
      });
    }
  }

  void changeTheme(ThemeMode value) {
    setState(() => mode = value);
    final key = owner?.preferenceKey('appearance', client.origin);
    if (key != null) {
      unawaited(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString(key, value.name),
        ),
      );
    }
  }

  void changeLighting(bool value) {
    setState(() => lightingEnabled = value);
    final key = owner?.preferenceKey('ambient_lighting', client.origin);
    if (key != null) {
      unawaited(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setBool(key, value),
        ),
      );
    }
  }

  Future<void> refreshIdentity() async {
    try {
      await client.validateSession();
      final identity = client.identity;
      if (!mounted || identity == null) return;
      final oldScope = owner?.preferenceScope(client.origin);
      final newScope = identity.preferenceScope(client.origin);
      ThemeMode nextMode = mode;
      bool nextLighting = lightingEnabled;
      if (oldScope != newScope) {
        await appLock.useIdentity(newScope);
        final prefs = await SharedPreferences.getInstance();
        nextLighting =
            prefs.getBool(
              identity.preferenceKey('ambient_lighting', client.origin),
            ) ??
            true;
        nextMode =
            ThemeMode.values
                .where(
                  (item) =>
                      item.name ==
                      prefs.getString(
                        identity.preferenceKey('appearance', client.origin),
                      ),
                )
                .firstOrNull ??
            ThemeMode.system;
      }
      if (mounted) {
        setState(() {
          owner = identity;
          mode = nextMode;
          lightingEnabled = nextLighting;
        });
      }
    } catch (_) {
      // A temporary network error does not end a valid local session.
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GreenHouse',
    debugShowCheckedModeBanner: false,
    navigatorKey: navigation,
    scaffoldMessengerKey: messages,
    themeMode: mode,
    theme: greenhouseTheme(Brightness.light),
    darkTheme: greenhouseTheme(Brightness.dark),
    builder: (context, child) => AmbientLightingScope(
      enabled: lightingEnabled,
      onChanged: changeLighting,
      child: Stack(
        children: [
          ExcludeSemantics(
            excluding: privacyCover,
            child: ExcludeFocus(
              // A password manager may make the app inactive to authenticate.
              // Keep its autofill connection alive until the credentials return.
              excluding: privacyCover && owner != null,
              child: IgnorePointer(
                ignoring: privacyCover,
                child: Stack(
                  children: [
                    if (child != null)
                      ExcludeSemantics(
                        excluding:
                            locked || offerBiometrics || checkingBiometrics,
                        child: ExcludeFocus(
                          excluding:
                              locked || offerBiometrics || checkingBiometrics,
                          child: IgnorePointer(
                            ignoring:
                                locked || offerBiometrics || checkingBiometrics,
                            child: child,
                          ),
                        ),
                      ),
                    if (owner != null &&
                        lightingEnabled &&
                        !locked &&
                        !offerBiometrics &&
                        !checkingBiometrics &&
                        !privacyCover)
                      const Positioned.fill(child: AmbientLighting()),
                    if (owner != null && locked)
                      Overlay(
                        key: ValueKey(setupPin),
                        initialEntries: [
                          OverlayEntry(
                            builder: (_) => LockScreen(
                              lock: appLock,
                              client: client,
                              setup: setupPin,
                              initialUnlockRequired:
                                  setupRequiresAuthentication,
                              onUnlocked: () {
                                if (mounted) {
                                  setState(() {
                                    owner = client.identity ?? owner;
                                    locked = false;
                                    setupPin = false;
                                  });
                                }
                              },
                              onSignOut: () async {
                                await client.signOut();
                                try {
                                  await appLock.clearPin();
                                } catch (_) {}
                                if (mounted) endSession();
                              },
                            ),
                          ),
                        ],
                      )
                    else if (owner != null && checkingBiometrics)
                      const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    else if (owner != null && offerBiometrics)
                      _BiometricOffer(
                        client: client,
                        onDone: finishBiometricOffer,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (privacyCover)
            const Positioned.fill(child: ColoredBox(color: Color(0xff101a18))),
        ],
      ),
    ),
    home: !ready
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : owner == null
        ? EntryScreen(
            key: ValueKey(entryRevision),
            client: client,
            onSignedIn: signedIn,
          )
        : _ControlCenter(
            key: ValueKey((owner!.preferenceScope(client.origin), owner!.role)),
            client: client,
            owner: owner!,
            mode: mode,
            onTheme: changeTheme,
            appLock: appLock,
            onLockEnabled: setLockEnabled,
            notificationRevision: notificationRevision,
            onSessionEnded: (revoked) async {
              try {
                await appLock.clearPin();
              } catch (_) {}
              if (!mounted) return;
              endSession();
              if (!revoked) {
                notice(
                  'This phone was cleared. Revoke the old session from Known devices if it is still listed.',
                );
              }
            },
          ),
  );
}

class _ControlCenter extends StatefulWidget {
  const _ControlCenter({
    super.key,
    required this.client,
    required this.owner,
    required this.mode,
    required this.onTheme,
    required this.appLock,
    required this.onLockEnabled,
    required this.notificationRevision,
    required this.onSessionEnded,
  });
  final GreenhouseClient client;
  final HouseholdIdentity owner;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final AppLock appLock;
  final Future<void> Function(bool) onLockEnabled;
  final ValueListenable<int> notificationRevision;
  final ValueChanged<bool> onSessionEnded;

  @override
  State<_ControlCenter> createState() => _ControlCenterState();
}

class _ControlCenterState extends State<_ControlCenter>
    with WidgetsBindingObserver {
  String page = CompanionPage.overview;
  String defaultPage = CompanionPage.overview;
  String savedDefaultPage = CompanionPage.overview;
  bool cardsEnabled = false;
  String cardsTitle = 'Cards';
  int navigationRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreNavigation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCardsDiscovery());
    }
  }

  Future<void> _restoreNavigation() async {
    final initialRevision = navigationRevision;
    String? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString(
        widget.owner.preferenceKey('default_page', widget.client.origin),
      );
    } catch (_) {}
    if (!mounted) return;
    if (saved != CompanionPage.cards && navigationRevision == initialRevision) {
      setState(() {
        savedDefaultPage = saved ?? CompanionPage.overview;
        defaultPage = CompanionPage.resolveDefault(
          savedDefaultPage,
          cardsEnabled: false,
        );
        page = defaultPage;
      });
    } else {
      savedDefaultPage = saved ?? CompanionPage.overview;
    }

    Json? discovery;
    try {
      discovery = await widget.client.request('/cards/navigation');
    } catch (_) {
      // A missing or unavailable plugin leaves the core destinations usable.
    }
    if (!mounted) return;
    final navigationPage = object(discovery?['navigationPage']);
    final available = discovery?['enabled'] == true && navigationPage.isNotEmpty;
    setState(() {
      cardsEnabled = available;
      cardsTitle = label(navigationPage['title'], 'Cards');
      defaultPage = CompanionPage.resolveDefault(
        savedDefaultPage,
        cardsEnabled: available,
      );
      page = CompanionPage.restorePage(
        savedPage: savedDefaultPage,
        currentPage: page,
        cardsEnabled: available,
        startingRevision: initialRevision,
        currentRevision: navigationRevision,
      );
    });
  }

  Future<void> _refreshCardsDiscovery() async {
    Json? discovery;
    try {
      discovery = await widget.client.request('/cards/navigation');
    } catch (_) {
      // Treat discovery errors like a temporarily unavailable contribution.
    }
    if (!mounted) return;
    final navigationPage = object(discovery?['navigationPage']);
    final available = discovery?['enabled'] == true && navigationPage.isNotEmpty;
    setState(() {
      cardsEnabled = available;
      cardsTitle = label(navigationPage['title'], 'Cards');
      defaultPage = CompanionPage.resolveDefault(
        savedDefaultPage,
        cardsEnabled: available,
      );
      if (!available && page == CompanionPage.cards) {
        page = CompanionPage.resolveDefault(
          savedDefaultPage,
          cardsEnabled: false,
        );
      }
    });
  }

  void _setDefaultPage(String value) {
    setState(() {
      savedDefaultPage = value;
      defaultPage = CompanionPage.resolveDefault(
        value,
        cardsEnabled: cardsEnabled,
      );
    });
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(
          widget.owner.preferenceKey('default_page', widget.client.origin),
          value,
        ),
      ),
    );
  }

  void _cardsDisabled() {
    if (!mounted) return;
    setState(() {
      cardsEnabled = false;
      if (page == CompanionPage.cards) {
        page = CompanionPage.resolveDefault(
          savedDefaultPage,
          cardsEnabled: false,
        );
      }
    });
  }

  void _openPage(String value) {
    navigationRevision++;
    setState(() => page = value);
    if (value == CompanionPage.more) unawaited(_refreshCardsDiscovery());
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final screen = switch (page) {
      CompanionPage.overview => Overview(
        client: client,
        onActivity: () => _openPage(CompanionPage.activity),
      ),
      CompanionPage.activity => Activity(client: client),
      CompanionPage.accounts => Accounts(client: client),
      CompanionPage.plan => Planning(client: client),
      CompanionPage.insights => Insights(client: client),
      CompanionPage.cards => Cards(client: client, onDisabled: _cardsDisabled),
      _ => MorePages(
        cardsEnabled: cardsEnabled,
        cardsTitle: cardsTitle,
        onOpen: _openPage,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: const Brand(),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _Notifications(
                  client: client,
                  revision: widget.notificationRevision,
                ),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _SettingsRoute(
                  client: client,
                  owner: widget.owner,
                  mode: widget.mode,
                  onTheme: widget.onTheme,
                  defaultPage: defaultPage,
                  cardsEnabled: cardsEnabled,
                  onDefaultPage: _setDefaultPage,
                  appLock: widget.appLock,
                  onLockEnabled: widget.onLockEnabled,
                  onSessionEnded: widget.onSessionEnded,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: screen),
      bottomNavigationBar: NavigationBar(
        selectedIndex: CompanionPage.bottomIndex(page),
        onDestinationSelected: (value) => _openPage(
          const [
            CompanionPage.overview,
            CompanionPage.activity,
            CompanionPage.accounts,
            CompanionPage.plan,
            CompanionPage.more,
          ][value],
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _SettingsRoute extends StatefulWidget {
  const _SettingsRoute({
    required this.client,
    required this.owner,
    required this.mode,
    required this.onTheme,
    required this.defaultPage,
    required this.cardsEnabled,
    required this.onDefaultPage,
    required this.appLock,
    required this.onLockEnabled,
    required this.onSessionEnded,
  });
  final GreenhouseClient client;
  final HouseholdIdentity owner;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onTheme;
  final String defaultPage;
  final bool cardsEnabled;
  final ValueChanged<String> onDefaultPage;
  final AppLock appLock;
  final Future<void> Function(bool) onLockEnabled;
  final ValueChanged<bool> onSessionEnded;

  @override
  State<_SettingsRoute> createState() => _SettingsRouteState();
}

class _SettingsRouteState extends State<_SettingsRoute> {
  late ThemeMode mode = widget.mode;
  late String defaultPage = widget.defaultPage;

  @override
  Widget build(BuildContext context) => CompanionSettings(
    client: widget.client,
    owner: widget.owner,
    appLock: widget.appLock,
    onLockEnabled: widget.onLockEnabled,
    mode: mode,
    onSessionEnded: widget.onSessionEnded,
    defaultPage: defaultPage,
    cardsEnabled: widget.cardsEnabled,
    onDefaultPage: (value) {
      setState(() => defaultPage = value);
      widget.onDefaultPage(value);
    },
    onTheme: (value) {
      setState(() => mode = value);
      widget.onTheme(value);
    },
  );
}

class _Notifications extends StatefulWidget {
  const _Notifications({required this.client, required this.revision});
  final GreenhouseClient client;
  final ValueListenable<int> revision;

  @override
  State<_Notifications> createState() => _NotificationsState();
}

class _NotificationsState extends State<_Notifications> {
  String? acknowledging;

  Future<void> acknowledge(
    Json notification,
    Future<void> Function() reload,
  ) async {
    if (acknowledging != null) return;
    final id = endpoint(notification['id']);
    setState(() => acknowledging = id);
    try {
      await widget.client.request('/alerts/$id/acknowledge', method: 'POST');
      if (mounted) await reload();
    } catch (e) {
      if (mounted) showMessage(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => acknowledging = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ValueListenableBuilder<int>(
      valueListenable: widget.revision,
      builder: (context, revision, _) => LoadScreen<Json>(
        key: ValueKey(revision),
        load: () => widget.client.request('/notifications'),
        content: (data, reload) {
          final items = objects(data['items']);
          return [
            Eyebrow('${data['unreadCount'] ?? items.length} unread'),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Panel(child: Text('You’re all caught up.')),
            for (final item in items) ...[
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(humanDate(item['createdAt'])),
                    const SizedBox(height: 5),
                    Text(
                      label(item['title'], 'Notification'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (item['explanation'] != null) ...[
                      const SizedBox(height: 5),
                      Text(label(item['explanation'])),
                    ],
                    if (item['isPersistent'] != true &&
                        widget.client.permissions.canAcknowledgeNotifications)
                      TextButton(
                        onPressed: acknowledging == null
                            ? () => acknowledge(item, reload)
                            : null,
                        child: const Text('Mark as read'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
            ],
          ];
        },
      ),
    ),
  );
}

class _BiometricOffer extends StatefulWidget {
  const _BiometricOffer({required this.client, required this.onDone});
  final GreenhouseClient client;
  final VoidCallback onDone;
  @override
  State<_BiometricOffer> createState() => _BiometricOfferState();
}

class _BiometricOfferState extends State<_BiometricOffer> {
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enable biometrics?',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use your device biometrics to sign in and unlock GreenHouse more quickly.',
                ),
                if (error != null) Text(error!),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          final saved = await widget.client
                              .rememberWithBiometrics();
                          if (!mounted) return;
                          if (saved) {
                            widget.onDone();
                          } else {
                            setState(() {
                              busy = false;
                              error = 'Biometrics could not be enabled. You can try again in Settings.';
                            });
                          }
                        },
                  child: const Text('Enable biometrics'),
                ),
                TextButton(
                  onPressed: busy ? null : widget.onDone,
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
