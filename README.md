# GreenHouse Mobile Companion

This Flutter app is the Android-first companion for a self-hosted [GreenHouse](https://github.com/stoutput/greenhouse) instance. The source also includes an iOS target. The initial release workflow builds Android.

The app covers the financial overview, transaction search and annotation, account balances and renaming, spending plan review, recurring payments and spending insights, and the notification inbox. Owner setup, provider enrollment and repair, imports, and plugin administration are handled in the web app.

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

1. Complete owner setup in GreenHouse web. Use a server build that exposes `/api/v1/mobile/info` and an HTTPS address with a certificate trusted by the phone.
2. At the app’s setup screen, search the LAN or enter the HTTPS origin. LAN search uses the `_greenhouse._tcp` DNS-SD service with an `origin` TXT record.
3. Sign in with your existing owner credentials. Enable biometric unlock in app Settings if your device supports it.

For a reverse-proxy installation, set the backend’s `GREENHOUSE_PUBLIC_ORIGIN` and `GREENHOUSE_MOBILE_TRUSTED_PROXIES` to the public HTTPS origin and the exact immediate proxy IPs. The proxy must overwrite `X-Forwarded-Proto` with `https` for secure requests, and the backend port must be reachable only through the intended proxy. See the GreenHouse deployment guide for DNS-SD publishing with Docker.

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

The app sends your owner credentials and financial requests to the HTTPS instance you select.
It stores the selected server address on the device. If you enable biometric unlock, the app
stores the session token in biometric-protected storage. Optional push uses Firebase Cloud
Messaging to deliver a generic notice. The app fetches the alert details directly from GreenHouse.

See [SECURITY.md](SECURITY.md) to report a vulnerability privately.

## License

The app is licensed under the [Apache License 2.0](LICENSE). The GreenHouse mark and launcher
artwork come from the [GreenHouse brand assets](https://github.com/stoutput/greenhouse/tree/main/assets/brand).
Open **Settings → Open-source licenses** for bundled license notices.
