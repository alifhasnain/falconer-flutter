## 0.3.0

Makes debug-only capture a **structural guarantee** instead of a default that
could be flipped, and puts a hard ceiling on how long captured payload can sit on
the device.

### Removed — BREAKING

* **`RetentionPeriod.forever` is gone; `oneMonth` is now the maximum window.**
  Captured traffic is unredacted-by-default payload in an on-device SQLite file,
  and retention is the only thing that bounds it — there is no row or size cap.
  An unbounded window let a long-lived debug build accumulate request and
  response bodies indefinitely. Eventual deletion is now a property of the tool
  rather than a setting the host app has to remember to choose.

  *Migration:* replace `retention: RetentionPeriod.forever` with the longest
  window you actually need (`RetentionPeriod.oneMonth` at most). Both native
  sides map the retired `forever` key onto their **one-day** fallback, so an app
  pinned to an older plugin against a newer engine deletes more, never less.

### Changed

* **The list screen and the ongoing notification now read a narrow column
  projection**, not the full row. Those queries re-run on every write, and the
  wide row carries `requestBody`, `responseBody` and the in-row image BLOB — each
  capped at `maxContentLength` (250 KB by default) — so a busy session was
  re-reading up to half a megabyte per transaction to draw a handful of short
  fields. Detail reads still take the full row. No API change.

* **The transaction list shows a loading shimmer** while the first read is in
  flight, instead of flashing the "nothing captured yet" empty state at a
  database that has not answered yet. Honours the platform's reduce-motion
  setting; a load that resolves within 120 ms never draws a placeholder at all.

> The list projection and the shimmer ship inside the platform engines. iOS gets
> them from the pod; Android from `io.github.alifhasnain:falconer-*`, now bumped
> to **`0.2.0`** on Maven Central (`ext.falconer_version`). Dropping `forever`
> needed no engine change on the wire: Dart simply stops sending the key, and an
> engine that still recognises it never hears it.

### Removed — BREAKING (debug-only capture)

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

### Added

* **`RetentionPeriod.oneMonth`** — a rolling **30 days**, not a calendar month.
  The default stays `oneWeek`; this is opt-in via `retention:`. Retention is the
  window in which captured payloads stay readable on the device, and sweeps are
  time-based only (no row or size cap, response images stored in-row), so a month
  on a busy app grows the store considerably. Prefer the shortest window that is
  still useful.

  **Requires the matching engine release on Android.** The Kotlin mirror ships in
  `falconer-impl`; with an older engine, `oneMonth` falls back silently to the
  one-day window. iOS ships in the plugin pod, so it needs nothing extra.

  Golden tests on all three sides now pin the retention wire-key set, so a
  one-sided addition fails the build instead of sweeping at the wrong interval.

### Fixed

* **`Falconer.configure` no longer throws into the host app.** A failing platform
  channel is swallowed and reported via `debugPrint`, matching the fire-and-forget
  policy the log calls already used — a diagnostic tool must not be able to break
  the app it inspects. Previously, calling `configure` before the binding existed
  threw `Binding has not yet been initialized` straight out of `main()`, and the
  native side silently kept its default redaction set, so headers still appeared
  as `**redacted**` even when `redactHeaders: {}` was passed.

  `configure` still needs a live binding to reach the channel: call
  `WidgetsFlutterBinding.ensureInitialized()` before it if it runs at the top of
  `main`. The warning now says exactly that when the call fails.

### Changed

* **Default retention is now `oneWeek`** (was `oneDay`) — a week of history is
  more useful for chasing intermittent failures, and capture is debug-only.
  Retention is the window in which captured payloads stay readable on the
  device, so pass a shorter `retention:` if your traffic is sensitive. Note
  sweeps are time-based only: there is no row or size cap, and response images
  are stored in-row, so a longer window grows the store without bound.

  The native pre-`configure` fallbacks stay at one day; they apply only before
  the first `configure` arrives and are replaced by it.

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
