# Falconer

A Chucker-style HTTP inspector for the [Dio](https://pub.dev/packages/dio)
client. Add one interceptor and inspect every request/response in a native
on-device UI — method, URL, headers, bodies, timing, status — with search,
JSON pretty-printing, image preview and cURL/text export.

> **v1 is Android-only**, with an iOS-ready architecture (all capture and
> redaction logic is pure Dart behind a platform interface).

## Status

**v0.1.0 — first development release.** Feature-complete on Android: capture,
storage, the native inspection UI, search and export all work. The API is
pre-1.0 and may change. iOS is not yet implemented.

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
- Android `minSdk 21`, `compileSdk 36`, Kotlin 2.1.x, Jetpack Compose

## Install

Not yet on pub.dev — add it as a git dependency:

```yaml
dependencies:
  dio: ^5.7.0
  falconer:
    git:
      url: https://github.com/alifhasnain/falconer.git
      ref: v0.1.0   # or `main` to track the latest
```

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

Open the inspector by tapping the Falconer notification, or call
`Falconer.launchUi()`.

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

## Example

See [`example/`](example/) — a demo app with two Dio clients sharing one list,
configuration with header redaction, and buttons that exercise JSON / form /
image / error / slow requests.

## License

[MIT](LICENSE).
