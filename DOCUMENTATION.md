# Falconer — Full Documentation

> The complete picture of the Falconer Flutter plugin: what it is, how the Dart
> and native halves fit together, the release-stripping design that makes it safe
> for production/payment apps, and how it is built, versioned, and released.
>
> Sister repo: **falconer-android** (the native engine artifacts on Maven Central)
> — its `DOCUMENTATION.md` covers the native internals and the Maven playbook in
> depth. This document links to it where relevant.

---

## 1. What Falconer is

Falconer is a **Chucker-style HTTP inspector for the Dio client** in Flutter. It
captures every HTTP request/response/error your app makes through Dio and lets you
inspect them — method, URL, headers, bodies, status, timing — in a **native
inspection UI** (Jetpack Compose on Android, SwiftUI on iOS), with search and
export.

- **Android and iOS** are both supported (Dart interceptor + native inspection
  UI — Jetpack Compose on Android, SwiftUI on iOS). The platform boundary is a
  single Dart interface, so the capture pipeline is shared unchanged. iOS
  specifics are in **§13**.
- Personality/design intent: *precise, honest, composed* — the captured HTTP data
  is the product; the UI recedes. Truncation/redaction are always visibly marked.

The headline feature is not just "an inspector" — it is that the inspector can be
made **physically absent from release builds** (see §4), which is what makes it
safe to depend on in a payment app.

---

## 2. The two repositories

Falconer is **two repos** working together:

| Repo | What it is | Distributed via |
|------|------------|-----------------|
| **falconer-flutter** (this repo) | The Flutter plugin: Dart capture pipeline + a thin native plugin. | Git dependency now; pub.dev later. |
| **falconer-android** | The native engine: three Android artifacts (`core` / `impl` / `noop`). | **Maven Central** (`io.github.alifhasnain:*`). |

Why split? Because the release-stripping trick (Method A) has to happen at the
Gradle/Maven layer — pub has no concept of debug/release-scoped dependencies. The
Flutter plugin stays a normal one-line pub install; the heavy native code and the
debug/release swap live in the Maven artifacts. See the falconer-android docs for
the full rationale.

```
   Your Flutter app
        │  depends on (pub / git)
        ▼
   falconer-flutter  ──── Dart interceptor + thin Android plugin
        │  the Android plugin depends on (Maven Central, per build variant)
        ▼
   falconer-android  ──── falconer-core + (debug) falconer-impl / (release) falconer-noop
```

---

## 3. End-to-end architecture

```
 ┌───────────────────────────── DART (this repo, lib/) ─────────────────────────────┐
 │  Dio ──▶ FalconerInterceptor ──▶ capture (DTO/codec/sink) ──▶ MethodChannel        │
 │            │                                                     "falconer"        │
 │            └── runtime gate: kReleaseMode ⇒ always disabled (short-circuit)        │
 └───────────────────────────────────────────────┬──────────────────────────────────┘
                                                  │ platform channel
 ┌────────────────────── NATIVE (this repo, android/) ──────────────────────────────┐
 │  FalconerPlugin  ── resolves a FalconerEngine via ServiceLoader ──▶ engine.log*()  │
 │       (thin: channel wiring + notification-permission only)                        │
 └───────────────────────────────────────────────┬──────────────────────────────────┘
                                                  │ ServiceLoader picks per build variant
 ┌───────────────────── ENGINE (falconer-android, Maven Central) ────────────────────┐
 │  debug   → RealFalconerEngine  → SQLDelight DB + Compose UI (FalconerActivity)     │
 │  release → NoOpFalconerEngine  → nothing (inspector absent from the APK)           │
 └───────────────────────────────────────────────────────────────────────────────────┘
```

On **iOS** the same channel drives a Swift/SwiftUI backend that lives inside the
plugin's own `ios/` (no separate artifact repo). Engine selection is
**compile-time** rather than ServiceLoader:

```
 ┌────────────────────── NATIVE (this repo, ios/Classes/) ───────────────────────────┐
 │  FalconerPlugin.swift  ── #if DEBUG picks the engine at COMPILE time ──▶ engine.*() │
 └───────────────────────────────────────────────┬──────────────────────────────────┘
   #if DEBUG   → RealFalconerEngine → system-libsqlite3 DB + SwiftUI UI (own UIWindow)
   #else       → NoOpFalconerEngine → nothing (inspector absent from the IPA)
```

---

## 4. The Dart layer (`lib/`)

The public API is exported from `lib/falconer.dart`. Internals live in `lib/src/`:

| Area | Files | Responsibility |
|------|-------|----------------|
| **Facade / runtime** | `src/falconer.dart`, `src/falconer_runtime.dart` | Entry point; resolves config against `kReleaseMode` — **release always resolves to disabled**. |
| **Config** | `src/config/falconer_config.dart`, `retention_period.dart` | Redaction rules, max body length, retention window, notification toggle. |
| **Interceptor** | `src/interceptor/falconer_interceptor.dart`, `transaction_id.dart` | The Dio `Interceptor` — hooks onRequest/onResponse/onError, assigns a stable id. |
| **Capture** | `src/capture/transaction_dto.dart`, `body_codec.dart`, `transaction_sink.dart` | Turns Dio events into serializable payloads; encodes bodies; redacts/truncates. |
| **Platform** | `src/platform/contract.dart`, `falconer_platform.dart`, `method_channel_falconer.dart` | The channel boundary. `contract.dart` holds `MethodNames`/`PayloadKeys` (mirrored in Kotlin). |

Key behaviours:

- **The runtime gate.** `FalconerConfig.resolveEnabled` returns `false` for every
  release build — there is no configuration that can override it (`0.3.0` removed
  the old `enableInReleaseBuilds` opt-in). The resolved flag short-circuits the
  interceptor's hot path, so in a release build **no payload is even marshalled**
  toward the channel. This is defence-in-depth *on top of* the native stripping,
  and it is now a structural guarantee rather than a default someone can flip.
- **Redaction & truncation happen in Dart first** (before crossing the channel),
  and are enforced again natively as a backstop.
- **Contract mirroring.** The channel method names and payload keys are defined once
  in `contract.dart` and mirrored in the Kotlin `channel/*` constants (now shipped
  in `falconer-core`). Golden tests guard against drift.

---

## 5. The native layer (`android/`)

After the Method A refactor, the plugin's own Android module is **thin** — just
three files:

- `FalconerPlugin.kt` — wires the `falconer` MethodChannel and the
  `falconer/transactionCount` EventChannel, and **delegates all real work to a
  `FalconerEngine`** it loads via `ServiceLoader`. It also keeps the light
  notification-permission flow. It imports **only** the interface, never a concrete
  implementation.
- `notification/NotificationPermission.kt` — the Android 13+ `POST_NOTIFICATIONS`
  runtime-permission flow (needs a foreground Activity; kept in the plugin).
- `FalconerPluginTest.kt` — unit tests for the channel stubs (`ping`, permission).

Everything else — the Compose UI, database, notifications, export — moved into
`falconer-android`'s `falconer-impl`. The plugin's `AndroidManifest.xml` is now
**empty** of inspector components; they are merged in from the `impl` AAR, which is
only linked in debug.

The plugin's `android/build.gradle` declares the engine per variant:
```gradle
api                   "io.github.alifhasnain:falconer-core:0.1.0"
debugImplementation   "io.github.alifhasnain:falconer-impl:0.1.0"
releaseImplementation "io.github.alifhasnain:falconer-noop:0.1.0"
```

Package: `dev.alifhasnain.falconer`.

---

## 6. The killer feature — release stripping (Method A)

In a **release** build, the plugin links only `falconer-noop`, so `ServiceLoader`
resolves an empty engine, nothing references the inspector, and **R8 strips
Compose, SQLDelight, `FalconerActivity`, and all capture/UI code from the APK**.
The merged release manifest declares none of the inspector's components. In
**debug**, the full `falconer-impl` is linked and everything works.

**Why it matters (PCI / payments):** captured HTTP payloads can contain cardholder
data, tokens, and credentials. A plain plugin would ship the inspector's UI and
on-device database inside production. Falconer makes it *absent* — the storage
surface does not exist in a release build. Treat "absent in release" as the default
posture; "present" is the explicit, debug-only opt-in.

> Full mechanism (ServiceLoader, the `META-INF/services` registration files, the
> R8 behaviour, and the byte-level proof) is documented in
> **`falconer-android/DOCUMENTATION.md` §3 and §5.**

---

## 7. Build & test

The plugin has no standalone build — the `example/` app hosts Gradle.

```bash
# Full compile gate (Dart + native, both variants):
cd example && flutter build apk --debug
cd example && flutter build apk --release       # release must strip the inspector

# Kotlin unit tests (thin plugin):
cd example/android && ./gradlew :falconer:testDebugUnitTest

# iOS (macOS host only):
cd example && flutter build ios --debug --simulator     # compile gate
cd example && flutter build ios --release --no-codesign  # release must strip the inspector
# Swift unit tests (contract drift-guard + mapper/config/redaction/DAO/export/shake):
cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:RunnerTests

# iOS strip proof (after the release build above):
nm build/ios/iphoneos/Runner.app/Frameworks/falconer.framework/falconer | grep RealFalconerEngine
otool -L build/ios/iphoneos/Runner.app/Frameworks/falconer.framework/falconer | grep -i sqlite
# both must print nothing

# Dart:
dart format .          # CI runs --set-exit-if-changed
flutter analyze
flutter test
```

**CI** (`.github/workflows/ci.yml`) runs four jobs on every push to `main` and
every PR:
1. `dart` — format check, `flutter analyze`, `flutter test` (ubuntu).
2. `android-unit` — `:falconer:testDebugUnitTest` (resolves the engine from Maven
   Central; writes `local.properties` first because `settings.gradle.kts` needs
   `flutter.sdk` and that file is gitignored).
3. `ios` (macos-14) — debug simulator build, `xcodebuild test -only-testing:RunnerTests`,
   release build, then an **automated strip check**: `nm`/`strings` must not find
   `RealFalconerEngine`, `SQLiteDatabase`, `TransactionStore`, `InspectorRootView`
   or `TransactionDetailView` in the release framework binary, and `otool -L` must
   not show `libsqlite3`. The job fails if any is present — the stripping guarantee
   is enforced, not just asserted in prose (§13.3).
4. `pana` — pub.dev score gate (fails if the package loses > 20 points).

---

## 8. Consuming the plugin (today)

Not yet on pub.dev — install as a git dependency:

```yaml
dependencies:
  dio: ^5.7.0
  falconer:
    git:
      url: https://github.com/alifhasnain/falconer-flutter.git
      ref: 0.1.0
```

The plugin resolves its native engine from `mavenCentral()` automatically, so no
extra repository configuration is needed in the consuming app. (During debug the
consumer may also need the Kotlin `stdlib` force block — see §9.)

---

## 9. Versioning & release

Three version strings move **together** on every release:

1. `pubspec.yaml` → `version:` (the plugin/pub version).
2. `android/build.gradle` → `ext.falconer_version` (the Maven engine coordinate).
3. `falconer-android` → `VERSION_NAME` (the published artifact version).

`ios/falconer.podspec` → `s.version` tracks the **pub** version (1), not the
Maven engine version — the iOS native code ships inside the pod. See §13.9.

Release steps:
1. Publish the native artifacts first — see `falconer-android/DOCUMENTATION.md §7`.
2. Bump the three versions to match.
3. Commit, then tag the plugin repo with the plain version (e.g. `0.1.0`, no `v`
   prefix — the README's git-dependency `ref:` must match the tag exactly).
4. (Future) `flutter pub publish` to reach the wider Flutter community.

**Consumer note — Kotlin stdlib.** In debug the plugin links `falconer-impl`, which
pulls SQLDelight → a newer `kotlin-stdlib` than the pinned Kotlin 2.1.0 compiler.
On AGP 8.9.1 that jams R8/D8. A consuming app must force the stdlib back to 2.1.0
(the same `resolutionStrategy.force` block the example app uses).

---

## 10. Maven Central — short version

The native engine is published to Maven Central as
`io.github.alifhasnain:{falconer-core,falconer-impl,falconer-noop}`. Getting there
required: a **verified namespace** (`io.github.alifhasnain`), **GPG-signed
artifacts**, a **complete POM**, and **sources + javadoc jars** — all automated
with the vanniktech `maven-publish` Gradle plugin. The single biggest effort was
GPG signing on Windows (two conflicting gpg installs; a PowerShell redirect that
UTF-16-corrupted the exported key). We started on JitPack and moved to Maven
Central so consumers need no custom repository and enterprise proxies don't block
it.

> The **full Maven playbook** (namespace verification, vanniktech config, the GPG
> troubleshooting, the release flow, immutability) is in
> **`falconer-android/DOCUMENTATION.md §7`.**

---

## 11. Status & roadmap

- **Shipped:** Falconer `0.2.0` — Dart capture + native inspector on **Android
  and iOS**, release stripping verified end-to-end on both (debug shows the
  inspector; release contains none of it). Android engine live on Maven Central;
  iOS ships inside the plugin pod (see §13).
- **Reach (next):**
  1. **pub.dev publish** — git-dep is niche; pub.dev is how Flutter devs find it.
     `CHANGELOG.md` is in place; next is `flutter pub publish`.
  2. **Body-content redaction patterns** — mask secrets inside bodies, not just
     headers.
- **Housekeeping:** GitHub Release notes.

---

## 12. Glossary / quick facts

- **Plugin package:** `dev.alifhasnain.falconer`
- **Channel name:** `falconer`; count stream: `falconer/transactionCount`
- **Engine coordinates:** `io.github.alifhasnain:falconer-core|impl|noop:0.1.0`
- **Repos:** `alifhasnain/falconer-flutter` (plugin) · `alifhasnain/falconer-android` (engine)
- **Toolchain:** Kotlin 2.1.0 · AGP 8.9.1 · Gradle 8.12 · SQLDelight 2.2.1 ·
  compileSdk/targetSdk 36 · minSdk 21 · jvmTarget 17 · Flutter 3.35.4
- **iOS toolchain:** Swift 5 · SwiftUI · system `libsqlite3` (no third-party pod) ·
  min iOS 15 · CI on macos-14 / iPhone 15 simulator
- **iOS DB path:** `Application Support/falconer.db` (WAL, single connection)
- **iOS debug entry point:** device shake (`.falconerShake`) or `Falconer.launchUi()`
- **License:** MIT

---

## 13. iOS

The iOS backend lives in this repo's `ios/` and ships **inside the plugin pod** —
there is no Maven-equivalent artifact repo, because iOS has a mechanism Maven's
debug/release-scoped deps were emulating: the C preprocessor.

### 13.1 Architecture mapping (Android → iOS)

| Concern | Android | iOS |
|---------|---------|-----|
| Plugin language | Kotlin | Swift (`ios/Classes/FalconerPlugin.swift`) |
| Channels | `MethodChannel` / `EventChannel` | `FlutterMethodChannel` / `FlutterEventChannel` |
| Engine discovery | `ServiceLoader` (runtime) | **`#if DEBUG` (compile time)** |
| Inert release engine | `falconer-noop` AAR | `NoOpFalconerEngine.swift` (same file, other branch) |
| Storage | SQLDelight | system **`libsqlite3`** via a thin Swift wrapper |
| DB location | app database dir | `Application Support/falconer.db` (WAL) |
| UI | Compose + `FalconerActivity` (own task) | **SwiftUI** in its own `UIWindow` (`windowLevel = .normal + 1`) |
| Navigation | Activity + Compose nav | `NavigationView(.stack)` (deployment target is iOS 15, so **not** `NavigationStack`) |
| Live count | `Flow<Int>` → EventChannel | `AsyncStream<Int>` → EventChannel |
| Search highlight | `AnnotatedString` + `SpanStyle` | `AttributedString` + `backgroundColor` |
| Export/share | `Intent` share sheet | `UIActivityViewController` (via `ShareSheet`) |
| Entry point | notification tap | **shake** (debug) + `launchUi` |
| Notifications | ongoing summary notification | **not implemented** — see §13.7 |

The Dart layer (interceptor, DTO builders, redaction/truncation, contract) is
**reused verbatim**; iOS work was purely the native sink, storage, UI, and the
stripping mechanism. Redaction and truncation are re-applied natively as a
backstop with byte-identical markers (`**redacted**`, the truncation line).

### 13.2 File layout (`ios/Classes/`)

**Compiled in all configurations** (4 files, ~260 lines) — the thin plugin, the
seam, and the contract mirror. Nothing inspector-specific:

- `FalconerPlugin.swift` — channel wiring + method dispatch; picks the engine at
  the single `#if DEBUG` selection point in `init()`.
- `FalconerEngine.swift` — the protocol (the iOS mirror of Kotlin's
  `FalconerEngine` interface). Raw `[String: Any]` in, so the plugin never
  touches capture concerns.
- `NoOpFalconerEngine.swift` — inert; `observeCount()` yields a single `0` and
  finishes.
- `contract/Contract.swift` — the frozen channel contract mirror.

**Debug-only** (18 files, ~1 730 lines) — every one begins with `#if DEBUG`:

| Dir | Files |
|-----|-------|
| `engine/` | `RealFalconerEngine.swift` |
| `capture/` | `PayloadMapper.swift`, `FalconerNativeConfig.swift`, `Redactor.swift`, `Models.swift` |
| `storage/` | `SQLiteDatabase.swift`, `HttpTransactionDao.swift`, `TransactionStore.swift`, `RetentionManager.swift` |
| `ui/` | `InspectorRootView.swift`, `TransactionDetailView.swift`, `InspectorPresenter.swift`, `FalconerTheme.swift`, `BodyFormatting.swift`, `ShakeDetector.swift`, `ShareSheet.swift` |
| `export/` | `CurlBuilder.swift`, `TextExporter.swift` |

### 13.3 Release stripping (Method A on iOS)

`flutter build ipa --release` compiles the pod with the **Release**
configuration, where `DEBUG` is not defined, so every `#if DEBUG` file compiles
to nothing. The plugin's engine field then resolves to `NoOpFalconerEngine`, and
there is no compile edge to the inspector — it is physically absent. The podspec
makes this explicit rather than riding on CocoaPods defaults, and covers
**Profile** as well as Release (the example `Podfile` maps `'Profile' => :release`,
so a profile build strips the inspector too):

```ruby
'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]'   => '$(inherited) DEBUG',
'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Profile]' => '$(inherited)',
'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Release]' => '$(inherited)',
'OTHER_LDFLAGS[config=Debug]' => '$(inherited) -lsqlite3',  # link SQLite in Debug only
```

Because every call site into SQLite is debug-only, `-lsqlite3` is a **Debug-only
link flag**: a release binary links nothing beyond what Flutter/Swift already
pull in. There is no third-party pod dependency at all — `s.dependency 'Flutter'`
is the only one.

**Proof (verified, not assumed).** In a `--release` build the plugin framework
contains **0** occurrences of `RealFalconerEngine`, `TransactionStore`,
`SQLiteDatabase`, or the SwiftUI view types (via `nm` + `strings`); only
`NoOpFalconerEngine` and `FalconerPlugin` remain, and `otool -L` shows **no**
`libsqlite3` and no third-party pod. The same framework in Debug is ~20× larger
and contains all of them. **This proof is automated** — the `ios` CI job runs it
on every push and PR and fails the build if any inspector symbol or `libsqlite3`
survives (§7). Still re-check by hand whenever native deps change, and audit any
archive/TestFlight configuration that might define `DEBUG` in a release
configuration.

### 13.4 Runtime model (debug engine internals)

`RealFalconerEngine` owns a `TransactionStore` and an `InspectorPresenter`;
everything else hangs off the store.

**Threading / storage.** One `SQLiteDatabase` connection opened with
`SQLITE_OPEN_FULLMUTEX`, and **all** access serialized on a single serial
`DispatchQueue` (`dev.alifhasnain.falconer.db`) — the single-connection model the
DAO documents. Journal mode is WAL. The DB lives at
`Application Support/falconer.db`.

**Two-phase capture.** `logRequest` inserts a row; `logResponse` / `logError`
**merge onto it by id** using read-modify-write (`byId` → mutate → `INSERT OR
REPLACE`), so the DAO stays a plain upsert plus queries. Data volumes are tiny,
so RMW is cheaper than a wide partial-update statement. If a response arrives
with no matching request row (id unknown), a `placeholder(id:)` row is
synthesized rather than dropping the event.

**Backstop enforcement order.** Redaction and truncation are re-applied in
`TransactionStore` *before* the row is persisted, using the resolved
`FalconerNativeConfig`. `config.enabled` (already-resolved `effectiveEnabled`
from Dart) is checked inside each ingest, so a stray payload arriving while
capture is off is dropped natively. Over-cap images are handled specially: the
bytes are **discarded** and the body becomes a visible marker
(`[Falconer: image truncated — N bytes > M]`) — the image is never persisted
above the cap.

**Live count.** `observeCount()` hands out an `AsyncStream<Int>` per subscriber;
continuations are held in a dictionary behind an `NSLock`, so multiple
subscribers are supported and each gets the current count immediately on
subscribe, then a value after every write and clear. `FalconerPlugin` bridges the
stream to the EventChannel in a `Task`, hopping to `MainActor` to call the sink,
and cancels that task on `onCancel` / `detachFromEngine`.

**SwiftUI feed.** The same store publishes `transactions` (`@Published`,
main-actor) for the UI, so a response merging in after a row is opened updates
the open detail live (the detail view looks the transaction up by id every
render).

**Retention.** `RetentionManager` sweeps unconditionally after `configure`, and
throttled on the write path — at most one sweep per 60 s. `forever` never
deletes. Windows mirror Android exactly (`oneHour` / `oneDay` / `oneWeek` /
`forever`).

**Graceful degradation.** If the Application Support directory or the DB cannot
be opened, `dao` is `nil` and every ingest becomes a silent no-op — the host app
never sees a throw from the inspector. All DAO calls use `try?` for the same
reason.

### 13.5 Shake-to-open (and the swizzle that bit us)

iOS has no notification-to-task model, so the debug entry point is a device
shake plus the programmatic `launchUi`. `ShakeDetector.install()` adds a
**`UIWindow`-scoped override** of `motionEnded(_:with:)` via
`class_replaceMethod` with an `imp_implementationWithBlock`, posts
`.falconerShake`, then forwards to the captured original `IMP`.

Why not the usual two-selector swizzle: `UIResponder`'s default
`motionEnded(_:with:)` forwards to the next responder **using `_cmd`** — the
selector it was invoked with. A classic swizzle invokes the original under a
*renamed* selector, so that renamed selector gets propagated up the chain to the
window's next responder (`UIWindowScene`), which does not implement it →
`-[UIWindowScene falconer_motionEnded:with:]: unrecognized selector` crash.
Calling the original IMP directly with the real selector keeps the responder
chain intact and never leaks a private selector. `ShakeDetectorTests` pins both
halves of this regression (a shake on a non-window responder must not crash; a
shake on a `UIWindow` attached to the host's scene must post *and* forward
cleanly).

### 13.6 Option B (advanced, macro-independent)

For teams with custom build configurations or a hard audit requirement, ship the
inspector as a **separate Debug-only pod** and resolve the real engine at runtime
via `NSClassFromString`; the thin plugin falls back to the no-op when the Debug
pod is not linked. This decouples stripping from the `DEBUG` macro at the cost of
a one-line Podfile edit (`pod 'FalconerInspector', :configurations => ['Debug']`)
— Chucker's "Method B" ergonomics. Option A is the default; both keep the Dart
runtime gate (release always resolves to disabled) as defence in depth.

### 13.7 Behaviour deltas vs Android (stated, not hidden)

Feature parity is the goal, but three things differ. The channel contract is
identical on both sides — the deltas are in what the native side *does* with it:

1. **Notifications are not implemented.** `showNotification` is parsed into
   `FalconerNativeConfig` and then **never read** — it is accepted and ignored so
   the shared Dart config stays platform-neutral. `requestNotificationPermission`
   resolves **`true`** without asking for anything, because there is nothing to
   grant: the iOS entry points are shake and `launchUi`. A consuming app that
   branches on that result therefore sees the same shape on both platforms.
2. **List filtering is in-memory.** `HttpTransactionDao.filtered(_:)` exists and
   is unit-tested (SQL `LIKE … COLLATE NOCASE` over url / method / host /
   `CAST(statusCode AS TEXT)`), but `InspectorRootView` filters the published
   `transactions` array in Swift instead — same four fields, same
   case-insensitivity, no round trip per keystroke. The DAO query is the
   pushdown path kept for when volumes make it worth it.
3. **No cross-launch task/back-stack semantics.** Android's inspector is a
   separate Activity in its own task; iOS presents a `UIWindow` one level above
   the app's, dismissed by its Close button, `clear()`, or `detach()`. Nothing
   persists the inspector across app launches on either platform.

### 13.8 iOS test coverage (`example/ios/RunnerTests/RunnerTests.swift`)

Six XCTest classes, all headless on the simulator — no device storage, no
network:

- `ContractTests` — the **drift guard**. Mirrors `test/contract/contract_test.dart`
  and fails if any channel name, method name, payload key, config key, or body
  kind diverges from the frozen Dart contract. Note `PayloadKeys.protocolName`
  maps to the wire key `"protocol"` (`protocol` is a Swift keyword) — the test
  pins that mapping explicitly.
- `PayloadMapperTests` — `NSNull` → `nil`, `Int`/`NSNumber`/`Int64` tolerance
  (Flutter's `StandardMessageCodec` picks the width by magnitude), and
  missing-`id` rejection.
- `ConfigAndRedactionTests` — config parsing, lowercased header matching,
  and the byte-identical truncation marker.
- `DaoTests` — real SQLite via `SQLiteDatabase(path: ":memory:")`: insert,
  query, filter, upsert-merge-by-id, clear.
- `FormattingAndExportTests` — match-finding, JSON pretty-print, byte
  formatting, and that a **redacted header's mask travels into the cURL export**
  (the mark travels; the secret never existed here).
- `ShakeDetectorTests` — the swizzle regression from §13.5.

`BodyFormatting` deliberately holds the pure logic (pretty-print, match ranges,
formatting) with **no SwiftUI import**, so it is unit-testable — the same split
Android needs because Compose `ui.text` is not JVM-safe.

### 13.9 Versioning nuance

iOS native code ships in the plugin pod, so an iOS-only change bumps the **pub
package** version (`pubspec.yaml`, `ios/falconer.podspec`) but **not** the
Android Maven engine coordinate, which stays independent
(`io.github.alifhasnain:*`). The three-versions-in-lockstep rule in §9 applies to
Android engine releases.
