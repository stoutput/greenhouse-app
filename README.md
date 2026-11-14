# GreenHouse Mobile Companion

This Flutter app is the Android-first companion for a self-hosted [GreenHouse](https://github.com/stoutput/greenhouse) instance. The source also includes an iOS target. The initial release workflow builds Android.

The app covers the financial overview, transaction search and annotation, account balances and renaming, spending plan review, recurring payments and spending insights, and the notification inbox. Owner setup, provider enrollment and repair, imports, and plugin administration are handled in the web app.

Ambient daylight and moonlight are enabled by default. Turn them off under **Settings → Appearance**.
The subtle rays use the device clock for a decorative day/night cycle, without requesting location
access or running a continuous animation. The preference is saved per account and instance on this device.

## Run on Android

Install Flutter 3.47.9 and Android Studio with the Android SDK. The app requires Android 9 or later.

```sh
git clone https://github.com/stoutput/greenhouse-app.git
cd greenhouse-app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

Build a local development APK with `flutter build apk --debug`.

## GitHub releases

The Android workflow analyzes, tests, and builds the app on pull requests and pushes to `main`.
When `main` contains a new version in `pubspec.yaml`, it publishes a signed
`greenhouse-v<VERSION>.apk` and its SHA-256 checksum to GitHub Releases.
Increase both the version name and the Android build number for each release, for example
`0.1.0+1` to `0.1.1+2`. A version with an existing release is skipped. |

To enable push in the release APK, set all four `GREENHOUSE_FIREBASE_*` values listed below
as Actions **variables**. Leave them all unset to build without push.

## Connect an instance

1. Complete owner setup in GreenHouse web. Invited household members accept their invitation and finish account setup through the web link before signing in here. Use a server build that exposes `/api/v1/mobile/info` and an HTTPS address with a certificate trusted by the phone.
2. At the app’s setup screen, search the LAN or enter the HTTPS origin. LAN search uses the `_greenhouse._tcp` DNS-SD service with an `origin` TXT record.
3. Sign in with your existing GreenHouse credentials. The app shows your household role in Settings. Owners and admins can make shared financial changes; gardeners can view household finances and manage personal device settings. Household invitations and role management remain in GreenHouse web. Use your device screen lock, or set an unlock PIN if your device has none, and authenticate once to save biometric unlock automatically when supported biometrics are enrolled. The app-lock setting remains available in Settings.

When the server enables Cloudflare Turnstile, password sign-in opens an embedded verification screen before submitting your credentials. The screen loads from your selected server and uses its existing widget configuration; the app needs no Turnstile keys or build settings. Register the hostname used by the app on the server's Turnstile widget and in `TURNSTILE_HOSTNAMES`. This requires a server version with mobile Turnstile support. Biometric unlock of an existing session does not repeat the challenge.

The app connects to the server you select. Household identity and permissions come from that server; the mobile app does not provide cloud-wide tenant selection or household administration.

For a reverse-proxy installation, set the backend’s `GREENHOUSE_PUBLIC_ORIGIN` and `GREENHOUSE_MOBILE_TRUSTED_PROXIES` to the public HTTPS origin and the exact immediate proxy IPs. The proxy must overwrite `X-Forwarded-Proto` with `https` for secure requests, and the backend port must be reachable only through the intended proxy. See the GreenHouse deployment guide for DNS-SD publishing with Docker.

Each biometric unlock requires fresh authentication, including after a successful unlock earlier in the same app session. Re-authentication shows a black screen; a failed or cancelled attempt shows only the GreenHouse logo and an **Unlock** button to retry. Phones without a device screen lock retain the PIN fallback.

GreenHouse checks the OS biometric enrollment state before restoring a saved session and when returning to the app. An enrollment change clears saved biometric access. It also signs out an active session if it was restored with biometrics or **Lock GreenHouse when navigating away** is enabled. A password-authenticated session with app locking disabled can continue. After upgrading from a version without enrollment checks, sign in once with your password to establish the enrollment baseline.

Settings → **Unlink device** revokes the device session when the instance is reachable, clears the saved connection and returns to setup. If the app cannot confirm remote revocation, use **Settings → Known devices** on the web to remove the old registration. **Sign out** retains the selected instance.

## Android push

Register the Android app ID `app.greenhouse.greenhouse` in Firebase. Use values from that Android Firebase app to build:

```sh
flutter build apk --debug \
  --dart-define=GREENHOUSE_FIREBASE_API_KEY=... \
  --dart-define=GREENHOUSE_FIREBASE_APP_ID=... \
  --dart-define=GREENHOUSE_FIREBASE_SENDER_ID=... \
  --dart-define=GREENHOUSE_FIREBASE_PROJECT_ID=...
```

Enable Firebase Cloud Messaging HTTP v1 for that project. Set `GREENHOUSE_FIREBASE_SERVICE_ACCOUNT_JSON` only on the GreenHouse server, using credentials with permission to send messages for that project. On a compatible Android device with Google Play services, enable **Push notifications** in app Settings. The app requests notification permission and registers the device with GreenHouse. Push uses the notification types enabled under **In GreenHouse** in web Settings. Firebase receives a generic alert without financial details.

iOS push also requires an Apple signing and APNs configuration for the iOS target.

## Data and security

The app sends your GreenHouse credentials and financial requests to the HTTPS instance you select.
It stores the selected server address on the device. When supported biometrics are enrolled, the app
automatically stores the session token in biometric-protected storage. By default, returning to the app requires your device screen lock or, if none is configured, the GreenHouse unlock PIN, and a valid server session. The PIN protects only an active session;
a fresh app launch requires biometrics or your account credentials. The app hides its contents in
the app switcher while this lock is enabled. On Android, this also blocks screenshots while the app is open. Optional push uses Firebase Cloud
Messaging to deliver a generic notice. The app fetches the alert details directly from GreenHouse.

See [SECURITY.md](SECURITY.md) to report a vulnerability privately.

## License

The app is licensed under the [Apache License 2.0](LICENSE). The GreenHouse mark and launcher
artwork come from the [GreenHouse brand assets](https://github.com/stoutput/greenhouse/tree/main/assets/brand).
Open **Settings → Open-source licenses** for bundled license notices.
