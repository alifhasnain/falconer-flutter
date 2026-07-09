# falconer_example

Demonstrates the Falconer plugin: multi-client capture, configuration with
redaction, and the on-device inspection UI.

## What it shows

- **Two Dio clients, one list.** `dioA` (jsonplaceholder) and `dioB` (httpbin)
  each add their own `FalconerInterceptor`; their traffic appears together in a
  single Falconer list and notification (see `lib/api_clients.dart`).
- **Configuration + redaction.** `main()` calls `Falconer.configure(...)` with a
  custom redact header (`X-Demo-Secret`) on top of the strong defaults. Requests
  send `Authorization` and `X-Demo-Secret`; both show as `**redacted**` in the
  inspector — never persisted raw.
- **Request buttons.** JSON GET · multipart form POST · image GET · 404 · slow
  (~3s). Each produces a captured transaction (errors are captured too).
- **Inspector entry points.** "Open inspector" calls `Falconer.launchUi()`, but
  the **notification is the primary entry point** — tap it to open the UI in its
  own task. On Android 13+ tap "Enable notifications" first.

## Run

```sh
flutter run
```

Capture is **debug-only by default**. To try it in a release build, uncomment
the explicit opt-in block in `main()`:

```dart
await Falconer.configure(const FalconerConfig(
  enabled: true,
  enableInReleaseBuilds: true,
));
```

> ⚠️ Enabling release capture persists HTTP request/response data on-device.
> Ensure auth/PII headers are redacted and do **not** capture cardholder data
> (PCI-DSS). See the root README and `doc/PLAN.md`.
