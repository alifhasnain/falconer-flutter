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
Android inspection UI**, with search and export.

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
 │            └── runtime gate: kReleaseMode / enableInReleaseBuilds (short-circuit)  │
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
| **Facade / runtime** | `src/falconer.dart`, `src/falconer_runtime.dart` | Entry point; resolves config against `kReleaseMode` and the **`enableInReleaseBuilds`** gate. |
| **Config** | `src/config/falconer_config.dart`, `retention_period.dart` | Redaction rules, max body length, retention window, notification toggle. |
| **Interceptor** | `src/interceptor/falconer_interceptor.dart`, `transaction_id.dart` | The Dio `Interceptor` — hooks onRequest/onResponse/onError, assigns a stable id. |
| **Capture** | `src/capture/transaction_dto.dart`, `body_codec.dart`, `transaction_sink.dart` | Turns Dio events into serializable payloads; encodes bodies; redacts/truncates. |
| **Platform** | `src/platform/contract.dart`, `falconer_platform.dart`, `method_channel_falconer.dart` | The channel boundary. `contract.dart` holds `MethodNames`/`PayloadKeys` (mirrored in Kotlin). |

Key behaviours:

- **The runtime gate.** `enableInReleaseBuilds` (resolved against `kReleaseMode`)
  short-circuits the interceptor's hot path — in a disabled build, **no payload is
  even marshalled** toward the channel. This is defence-in-depth *on top of* the
  native stripping.
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
# Swift unit tests (contract drift-guard + mapper/config/redaction/DAO/export):
cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RunnerTests

# Dart:
dart format .          # CI runs --set-exit-if-changed
flutter analyze
flutter test
```

**CI** (`.github/workflows/ci.yml`) runs three jobs on every push to `main` and
every PR:
1. `dart` — format check, `flutter analyze`, `flutter test`.
2. `android-unit` — `:falconer:testDebugUnitTest` (resolves the engine from Maven
   Central).
3. `pana` — pub.dev score gate (fails if the package loses > 20 points).

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
- **iOS toolchain:** Swift 5 · SwiftUI · system `libsqlite3` · min iOS 15
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
| Storage | SQLDelight | system **`libsqlite3`** via a thin Swift wrapper |
| UI | Compose + `FalconerActivity` (own task) | **SwiftUI** in its own `UIWindow` |
| Live count | `Flow<Int>` → EventChannel | `AsyncStream<Int>` → EventChannel |
| Export/share | `Intent` share sheet | `UIActivityViewController` |
| Entry point | notification tap | **shake** (debug) + `launchUi` |
| Notifications | ongoing summary notification | not implemented (`showNotification` is a no-op) |

The Dart layer (interceptor, DTO builders, redaction/truncation, contract) is
**reused verbatim**; iOS work was purely the native sink, storage, UI, and the
stripping mechanism. Redaction and truncation are re-applied natively as a
backstop with byte-identical markers (`**redacted**`, the truncation line).

### 13.2 File layout (`ios/Classes/`)

- `FalconerPlugin.swift`, `FalconerEngine.swift`, `NoOpFalconerEngine.swift`,
  `contract/Contract.swift` — **compiled in all configurations** (the thin
  plugin + the seam + the contract mirror). Nothing inspector-specific.
- Everything else is wrapped in `#if DEBUG`: `engine/RealFalconerEngine.swift`,
  `capture/*` (PayloadMapper, FalconerNativeConfig, Redactor, Models),
  `storage/*` (SQLiteDatabase, HttpTransactionDao, TransactionRepository via
  `TransactionStore`, RetentionManager), `ui/*` (SwiftUI views, theme, presenter,
  shake), `export/*` (CurlBuilder, TextExporter).

### 13.3 Release stripping (Method A on iOS)

`flutter build ipa --release` compiles the pod with the **Release**
configuration, where `DEBUG` is not defined, so every `#if DEBUG` file compiles
to nothing. The plugin's engine field then resolves to `NoOpFalconerEngine`, and
there is no compile edge to the inspector — it is physically absent. The podspec
makes this explicit rather than riding on CocoaPods defaults:

```ruby
'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]'   => '$(inherited) DEBUG',
'SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Release]' => '$(inherited)',
'OTHER_LDFLAGS[config=Debug]' => '$(inherited) -lsqlite3',  # link SQLite in Debug only
```

**Proof (verified, not assumed).** In a `--release` build the plugin framework
contains **0** occurrences of `RealFalconerEngine`, `TransactionStore`,
`SQLiteDatabase`, or the SwiftUI view types (via `nm` + `strings`); only
`NoOpFalconerEngine` and `FalconerPlugin` remain, and `otool -L` shows **no**
`libsqlite3` and no third-party pod. The same framework in Debug is ~20× larger
and contains all of them. Re-run this proof whenever native deps change or before
any release (and re-check for archive/TestFlight configs that might define
`DEBUG` in Release).

### 13.4 Option B (advanced, macro-independent)

For teams with custom build configurations or a hard audit requirement, ship the
inspector as a **separate Debug-only pod** and resolve the real engine at runtime
via `NSClassFromString`; the thin plugin falls back to the no-op when the Debug
pod is not linked. This decouples stripping from the `DEBUG` macro at the cost of
a one-line Podfile edit (`pod 'FalconerInspector', :configurations => ['Debug']`)
— Chucker's "Method B" ergonomics. Option A is the default; both keep the Dart
runtime gate (`enableInReleaseBuilds`) as defence in depth.

### 13.5 Versioning nuance

iOS native code ships in the plugin pod, so an iOS-only change bumps the **pub
package** version (`pubspec.yaml`, `ios/falconer.podspec`) but **not** the
Android Maven engine coordinate, which stays independent
(`io.github.alifhasnain:*`). The three-versions-in-lockstep rule in §9 applies to
Android engine releases.
