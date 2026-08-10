# Falconer

A Chucker-style HTTP inspector for the [Dio](https://pub.dev/packages/dio)
client. Add one interceptor and inspect every request/response in a native
on-device UI — method, URL, headers, bodies, timing, status — with search,
JSON pretty-printing, image preview and cURL/text export.

> **Android and iOS supported.** All capture and redaction logic is pure Dart
> behind a platform interface; each platform has a native inspection UI
> (Jetpack Compose on Android, SwiftUI on iOS).

| Android — Jetpack Compose | iOS — SwiftUI |
|:---:|:---:|
| <img src="https://raw.githubusercontent.com/alifhasnain/falconer-flutter/main/media/android_showcase.gif" width="400" alt="Android inspector: transaction list with method, status and timing, opening into detail tabs with in-body search and JSON pretty-printing"> | <img src="https://raw.githubusercontent.com/alifhasnain/falconer-flutter/main/media/ios_showcase.gif" width="400" alt="iOS inspector: the same transaction list and detail tabs rendered in SwiftUI, at feature parity with Android"> |

The same Dart capture pipeline, a native UI on each platform — not a Flutter
overlay competing with your app's widget tree.

## Status

**v0.3.0 — development release.** Feature-complete on **Android and iOS**:
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

- Flutter 3.35.0+ / Dart 3.9+
- Android: `minSdk 21`, `compileSdk 36`, Kotlin 2.1.x, Jetpack Compose
- iOS: deployment target **15.0+**, SwiftUI (Xcode 15+)

## Install

```sh
flutter pub add falconer
```

Falconer is a Dio interceptor, so your app already declares `dio` — leave that
entry as it is:

```yaml
dependencies:
  dio: ^5.7.0        # already yours; Falconer does not change it
  falconer: ^0.3.1
```

Keep `dio` declared even though Falconer depends on it too: your own code
imports `package:dio/dio.dart` to build the client, and `depend_on_referenced_packages`
(active under the default `flutter_lints`) requires a package you import to be a
direct dependency rather than a transitive one.

`falconer` belongs in `dependencies`, not `dev_dependencies` — your app code
references `FalconerInterceptor` in every build. Capture is still debug-only:
release builds cannot capture, and the native inspector is absent from the
release binary on both platforms (see [Security & data privacy](#security--data-privacy)).

On iOS this is a one-line install — the native inspector ships inside the plugin
pod and `flutter build ipa --release` strips it automatically (see below); no
Podfile edit is required for the default path.

## Usage

### 1. Configure once, at startup

```dart
import 'package:falconer/falconer.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  // `configure` reaches the native side over a platform channel, so the binding
  // must exist before it runs.
  WidgetsFlutterBinding.ensureInitialized();

  // Capture is debug-only — release builds cannot capture at all, and there is
  // no opt-in.
  await Falconer.configure(const FalconerConfig());

  runApp(const MyApp());
}
```

`Falconer.configure` needs a live binding to reach the platform channel. Call
`WidgetsFlutterBinding.ensureInitialized()` first whenever it runs at the top of
`main` — otherwise the call fails with `Binding has not yet been initialized`.
It won't throw into your app (a channel failure is swallowed and reported via
`debugPrint`), but the native side then keeps its own defaults, so your
`redactHeaders` and `retention` settings are silently ignored on the native
side. `configure` returns a `Future` — `await` it so capture is fully
configured before the first request goes out.

### 2. Add the interceptor to your Dio clients

This part has nothing to do with `main` — put it wherever your clients already
live (a service locator, a provider, a plain top-level file):

```dart
// lib/api_clients.dart
import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';

final Dio api = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(FalconerInterceptor());

// Multiple clients are fine — every interceptor feeds the same list.
final Dio auth = Dio(BaseOptions(baseUrl: 'https://auth.example.com'))
  ..interceptors.add(FalconerInterceptor());
```

Add `FalconerInterceptor()` to each client you want captured. They share one
sink, so traffic from all of them lands in a single inspector list.

### 3. Open the inspector

Call `Falconer.launchUi()` from anywhere, or:

- **Android** — tap the Falconer notification.
- **iOS** — **shake the device** (debug builds), since iOS has no
  notification-to-task model. `showNotification` is a no-op on iOS.

## Security & data privacy

Falconer persists captured HTTP data **on the device**.

- **Release builds cannot capture — there is no opt-in.** `resolveEnabled`
  returns `false` for every release build, so no configuration (`enabled: true`
  included) turns capture on in release. Nothing to enable means nothing to
  forget to disable.
- **Sensitive headers are redacted in Dart before they cross the channel** —
  `Authorization`, `Cookie`, `Set-Cookie`, `Proxy-Authorization`, `X-Api-Key`,
  `X-Auth-Token` by default; secrets never reach native logs or the database.
- **Do not capture cardholder data (PAN/CVV) or other regulated PII.** In
  payment/PCI-DSS contexts, exclude such endpoints from capture. Body-content
  redaction is not yet implemented — only header *names* are redacted, so a PAN
  inside a JSON body is stored verbatim in a debug build.
- **Captured data never leaves the device.** Falconer has no remote/network sink
  by design — there is no code path that transmits captured traffic anywhere.
- **The inspector is physically absent from release builds on both platforms.**
  Android strips it via build-variant-scoped native artifacts + R8; iOS compiles
  the whole inspector behind `#if DEBUG`, so a release IPA contains no capture,
  storage or UI code (verified by symbol inspection). The on-device database
  surface does not exist in release.

### iOS: verifying the strip

The iOS strip keys off the `DEBUG` compilation condition, which the plugin's
podspec sets for the `Debug` configuration only — true for standard Flutter
builds. If your app adds build configurations beyond `Debug` / `Profile` /
`Release`, confirm `DEBUG` is unset in every non-development one, then check the
built binary yourself:

```sh
flutter build ipa
APP=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
BIN="$APP/Frameworks/falconer.framework/falconer"

nm -gU "$BIN" | grep RealFalconerEngine   # no output = inspector absent
otool -L "$BIN" | grep sqlite3            # no output = storage not linked
```

Both commands print nothing on a correctly stripped release build. If either
prints a match, treat the build as capture-capable and do not ship it.

Check the **archive**, not `build/ios/iphoneos/Runner.app` — a debug run on a
device writes to that same path, so it may hold a debug binary that legitimately
contains the inspector. Reading it as a release artifact turns a correct build
into a false alarm. (`Frameworks/App.framework/flutter_assets/kernel_blob.bin`
exists only in a debug build, if you need to tell two artifacts apart.)

The Dart runtime gate (`resolveEnabled` is `false` in release) holds either way,
as defence in depth.

## Example

See [`example/`](example/) — a demo app with two Dio clients sharing one list,
configuration with header redaction, and buttons that exercise JSON / form /
image / error / slow requests.

## License

[MIT](LICENSE).
