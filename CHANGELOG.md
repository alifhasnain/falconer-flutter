## 0.3.0

Makes debug-only capture a **structural guarantee** instead of a default that
could be flipped. Dart-only change — no native code, no channel-contract change;
the Android engine coordinate stays at `0.1.0`.

### Removed — BREAKING

* **`FalconerConfig.enableInReleaseBuilds` is gone.** `resolveEnabled` now
  returns `false` for every release build, so no configuration can enable
  capture in release — `enabled: true` included. `enabled` remains, honoured in
  debug builds only.

  The removed flag never delivered a working inspector in release anyway: the
  native engine is absent from release builds on both platforms (Method A), so
  setting it `true` only re-enabled the Dart hot path and paid for payloads that
  the no-op engine discarded. Removing it deletes a footgun rather than a
  feature.

  *Migration:* delete `enableInReleaseBuilds:` from your `FalconerConfig(...)`.
  If you need capture in a non-debug build, `DOCUMENTATION.md §7` documents the
  consumer-side build edits for a staging flavour.

* `maybeWarnReleaseCapture` / `releaseCaptureWarned` (internal) removed — the
  condition they warned about is now unreachable.

## 0.2.0

Adds **iOS support** at feature parity with Android. No consumer API changes —
the shared Dart capture pipeline is unchanged, so the same `FalconerInterceptor`
and `Falconer.configure(...)` work on both platforms.

### Added

* **iOS backend** (Swift / SwiftUI): capture ingestion, system-`libsqlite3`
  storage with configurable retention and a live count, and a native inspection
  UI (list → detail tabs → in-body search with highlight, JSON pretty-print,
  image preview). Minimum deployment target **iOS 15**.
* **Export on iOS.** Share a transaction as cURL or text via the iOS share sheet
  (`UIActivityViewController`).
* **Entry points on iOS.** `Falconer.launchUi()` presents the inspector in its
  own window; **shake-to-open** is wired in debug builds (iOS has no
  notification-to-task model like Android).
* **iOS release stripping (Method A).** The entire inspector is compiled behind
  `#if DEBUG`, so a release IPA contains **no** inspector code — verified by
  symbol inspection (`nm`/`strings`): `RealFalconerEngine`, the SQLite wrapper
  and the SwiftUI views are absent from release; only the inert
  `NoOpFalconerEngine` and the thin plugin remain. No third-party pod, and
  `libsqlite3` is linked in Debug only.

### Notes

* iOS ships inside the plugin pod — there is no separate native artifact
  repository (unlike Android/Maven), so the Android engine coordinate
  (`io.github.alifhasnain:*`) stays at `0.1.0`.
* `showNotification` is a no-op on iOS; `requestNotificationPermission()`
  resolves `true` (nothing to grant — the entry point is shake + `launchUi`).

## 0.1.0

First development release. Android-only; the API is pre-1.0 and may change.

### Added

* **Dio interceptor.** Add one `FalconerInterceptor` to any Dio client to
  capture requests, responses and errors. Multiple clients share one list.
* **Capture pipeline.** Two-phase logging (request / response / error) with
  body encoding for JSON, text, multipart and images; unsupported and
  truncated bodies are marked, never silently dropped.
* **Storage.** Room-backed persistence with configurable retention and a live
  transaction count exposed over an `EventChannel`.
* **Native inspection UI** (Jetpack Compose): transaction list, detail tabs
  (overview / request / response) with swipeable navigation, in-body search
  with match highlighting, JSON pretty-printing and image preview.
* **Export.** Share a transaction as cURL or text, or save it to a `.txt` file.
* **Notification entry point.** A foreground notification opens the inspector
  in its own task; runtime permission handling on Android 13+.
* **Configuration.** `Falconer.configure(FalconerConfig(...))` for retention,
  max content length and the redact-header set.

### Security & privacy

* Sensitive headers (`Authorization`, `Cookie`, `Set-Cookie`,
  `Proxy-Authorization`, `X-Api-Key`, `X-Auth-Token`) are redacted in Dart
  **before** crossing the platform channel; secrets never reach native logs
  or the database.
* Capture is **inert in release builds** unless explicitly opted in with both
  `enabled: true` and `enableInReleaseBuilds: true`.
* Do not capture cardholder data (PAN/CVV) or other regulated PII; exclude
  such endpoints and keep release capture disabled in payment/PCI-DSS contexts.

### Notes

* v1 is Android-only. All capture and redaction logic is pure Dart behind a
  platform interface, so iOS support can be added without API changes.
