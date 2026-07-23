# Falconer

A Chucker-style HTTP inspector for the [Dio](https://pub.dev/packages/dio)
client. Add one interceptor and inspect every request/response in a native
on-device UI — method, URL, headers, bodies, timing, status — with search,
JSON pretty-printing, image preview and cURL/text export.

> **Android and iOS supported.** All capture and redaction logic is pure Dart
> behind a platform interface; each platform has a native inspection UI
> (Jetpack Compose on Android, SwiftUI on iOS).

## Status

**v0.2.0 — development release.** Feature-complete on **Android and iOS**:
capture, storage, the native inspection UI, search and export all work on both.
The API is pre-1.0 and may change.

## Features

- One-line setup: add `FalconerInterceptor` to any Dio client; multiple clients
  share a single list.
- Native Jetpack Compose inspector: transaction list, detail tabs
  (overview / request / response) with swipe navigation.
- In-body search with match highlighting, JSON pretty-printing, image preview.
- Export a transaction as cURL or text, or save it to a `.txt` file.
- Room-backed storage with configurable retention and a live transaction count.
- Notification entry point that opens the inspector in its own task.

## Requirements

- Flutter 3.35.4+ / Dart 3.9+
- Android: `minSdk 21`, `compileSdk 36`, Kotlin 2.1.x, Jetpack Compose
- iOS: deployment target **15.0+**, SwiftUI (Xcode 15+)

## Install

Not yet on pub.dev — add it as a git dependency:

```yaml
dependencies:
  dio: ^5.7.0
  falconer:
    git:
      url: https://github.com/alifhasnain/falconer-flutter.git
      ref: 0.2.0   # or `main` to track the latest
```

On iOS this is a one-line install — the native inspector ships inside the plugin
pod and `flutter build ipa --release` strips it automatically (see below); no
Podfile edit is required for the default path.

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';

void main() {
  // Configure once at startup. Disabled in release builds by default.
  Falconer.configure(const FalconerConfig());

  final dio = Dio()..interceptors.add(FalconerInterceptor());
}
```

Open the inspector by calling `Falconer.launchUi()`, or:

- **Android** — tap the Falconer notification.
- **iOS** — **shake the device** (debug builds), since iOS has no
  notification-to-task model. `showNotification` is a no-op on iOS.

## Security & data privacy

Falconer persists captured HTTP data **on the device**.

- **Release builds are inert by default.** Capture requires an explicit opt-in
  (`enabled: true` **and** `enableInReleaseBuilds: true`).
- **Sensitive headers are redacted in Dart before they cross the channel** —
  `Authorization`, `Cookie`, `Set-Cookie`, `Proxy-Authorization`, `X-Api-Key`,
  `X-Auth-Token` by default; secrets never reach native logs or the database.
- **Do not capture cardholder data (PAN/CVV) or other regulated PII.** In
  payment/PCI-DSS contexts, exclude such endpoints from capture and keep
  release capture disabled. Body-content redaction patterns are not yet
  implemented.
- **The inspector is physically absent from release builds on both platforms.**
  Android strips it via build-variant-scoped native artifacts + R8; iOS compiles
  the whole inspector behind `#if DEBUG`, so a release IPA contains no capture,
  storage or UI code (verified by symbol inspection). The on-device database
  surface does not exist in release.

### iOS: advanced stripping (Option B)

The default iOS mechanism (`#if DEBUG`) relies on the `DEBUG` compilation
condition being unset in Release, which is true for standard Flutter builds.
Teams with custom build configurations or a hard audit requirement can instead
ship the inspector as a separate Debug-only pod and look it up at runtime; this
decouples stripping from the `DEBUG` macro at the cost of a one-line Podfile
edit. See `DOCUMENTATION.md` for details. Both paths keep the Dart runtime gate
(`enableInReleaseBuilds`) as defence in depth.

## Example

See [`example/`](example/) — a demo app with two Dio clients sharing one list,
configuration with header redaction, and buttons that exercise JSON / form /
image / error / slow requests.

## License

[MIT](LICENSE).
