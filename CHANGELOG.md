## 0.4.0

Body decoders — the first phase of `doc/BODY_DECODER_PROPOSAL.md`. Dart-only:
no channel keys change, so this release pairs with the existing native
artifacts untouched.

* **`FalconerBodyDecoder` seam.** Apps that encrypt, compress or otherwise
  obscure their payloads at the application layer — the norm in banking,
  payment-gateway and telco apps — captured ciphertext and got no value from
  the body panes. Register decoders via `FalconerConfig.bodyDecoders`; each
  receives a `FalconerBodyContext` and returns the text to display, or `null`
  to decline.

  Declining is first-class, not an error path: most such apps send some
  endpoints in the clear, and a decoder that returns `null` hands the body to
  the next decoder, or leaves it raw if all decline. An empty string is a
  successful decode of an empty body, not a decline.

* **`FalconerBodyContext`** carries `direction`, `method`, `uri`, `statusCode`,
  `kind`, `contentType`, the encoded body text, raw bytes where the body was
  binary, the host's `RequestOptions.extra`, and the original Dart object as
  `raw` — so a partial envelope (`{code, message, data: "<ciphertext>"}`) can
  be rewritten one member at a time without re-parsing. Headers are the raw,
  unredacted values, since a decoder may need one to pick a key or a scheme
  version; redaction still applies to what is stored.

  `headers` and `extra` are unmodifiable views. `raw` is the host's live object
  and is read-only by contract — Falconer's no-mutation guarantee depends on
  decoders copying before they rewrite.

* **Failure policy.** A decoder that throws — including from its `name` getter
  — is skipped and the chain continues, so the worst case is a transaction
  logged with its raw body. Nothing propagates into the Dio chain.

* **Per-transaction opt-outs** on `RequestOptions.extra`, as `FalconerExtras`
  constants: `skipDecode` captures normally but runs no decoders;
  `skipCapture` suppresses the transaction entirely — no request, response or
  error row. `skipCapture` is the control to reach for on endpoints carrying
  card data or PINs: not storing a payload is stronger than masking one.

* **Pipeline order is pinned by tests:** encode → decode → truncate → payload
  map → channel. Decoded text is truncated against its own byte length, so a
  body that only becomes over-cap after decoding is still capped; the reported
  content length stays the original wire size either way.

* Decoders are Dart-side only and are absent from `toMap()` — nothing about
  them crosses the platform channel.

### Security

A decoder writes **plaintext into the on-device store**, which inverts the risk
profile of an encrypted app: transactions that were previously ciphertext, and
worthless to an attacker with the device, become readable payment traffic. This
is only defensible because capture is impossible in release builds — the
storage engine is physically absent from release binaries.

Body-content redaction is still not implemented (it is phase 2 of the
proposal), so a decoded PAN or PIN is stored verbatim in a debug build. Until
then, exclude those endpoints with `FalconerExtras.skipCapture`. Falconer never
logs decoded content, on any path, including failures.

## 0.3.2

Documentation only — no code, API or behaviour changes.

* Dropped the `Status` section from the README. It pinned a version number
  (`v0.3.0`) into prose that no release step updated, so it went stale the
  moment `0.3.1` shipped. Platform support is already stated in the intro, and
  pub.dev shows the current version itself.

## 0.3.1

Documentation only — no code, API or behaviour changes.

* **Install instructions now point at pub.dev.** `0.3.0` was published with a
  README written before the package existed on pub.dev: it said "Not yet on
  pub.dev" and told readers to add a git dependency pinned to a tag. The install
  path is now `flutter pub add falconer`.

  The command deliberately does **not** include `dio`. Every Falconer user
  already depends on Dio, and `pub add` on an existing dependency silently
  rewrites its constraint to the latest release rather than leaving it alone —
  so `pub add dio falconer` would quietly bump a pinned `dio` constraint.
  `dio` still belongs in `dependencies`, since your own code imports it.

  pub.dev renders the README from the published archive, per version, so
  correcting it required a release rather than a repo push.

* Clarified that `falconer` belongs in `dependencies`, not `dev_dependencies` —
  app code references `FalconerInterceptor` in every build, while capture itself
  stays debug-only.

## 0.3.0

Makes debug-only capture a **structural guarantee** instead of a default that
could be flipped, and puts a hard ceiling on how long captured payload can sit on
the device.

**First release published to pub.dev.** `0.1.0` and `0.2.0` were development
releases consumed as git dependencies; neither was published to pub.dev, and
`0.2.0` was never tagged. Install with `flutter pub add falconer` from this
version on.

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

* **Default retention is now `oneWeek`** (was `oneDay`) — a week of history is
  more useful for chasing intermittent failures, and capture is debug-only.
  Retention is the window in which captured payloads stay readable on the
  device, so pass a shorter `retention:` if your traffic is sensitive. Note
  sweeps are time-based only: there is no row or size cap, and response images
  are stored in-row, so a longer window grows the store without bound.

  The native pre-`configure` fallbacks stay at one day; they apply only before
  the first `configure` arrives and are replaced by it.

* **The declared SDK constraints are now `sdk: ^3.9.0` / `flutter: '>=3.35.0'`**
  (were `^3.9.2` / `>=3.3.0`). The old Flutter bound was never reachable — the
  Dart bound already excluded every Flutter predating Dart 3.9, so `>=3.3.0`
  advertised support that could not resolve. The Dart bound is relaxed from
  `^3.9.2` to `^3.9.0` because Flutter 3.35.0–3.35.2 bundle Dart 3.9.0 and
  3.35.3+ bundle 3.9.2; leaving it at `^3.9.2` would have kept 3.35.0–3.35.2
  excluded regardless of the Flutter line. Widening only — no version that
  previously resolved is affected.

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
