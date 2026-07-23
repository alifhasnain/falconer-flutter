# Falconer — iOS Implementation Plan

> Full plan to bring Falconer to iOS at parity with Android, **including the
> release-stripping guarantee** (inspector physically absent from release builds).
> Read alongside `DOCUMENTATION.md` (system overview) and
> `falconer-android/DOCUMENTATION.md` (the Android mechanism we are mirroring).

Status: **implemented (v0.2.0)** — Phases 0–7 done and verified on a simulator:
capture → SQLite → live count → SwiftUI inspector → cURL/text export, with
shake-to-open. Release stripping proven by symbol inspection (inspector types and
`libsqlite3` absent from the release binary). `pubspec.yaml` declares `ios`; the
native code lives in `ios/` and ships in the plugin pod. Decisions taken against
the open questions (§8): iOS 15 target, system-`libsqlite3` wrapper, Option A
(`#if DEBUG`) default with Option B documented, shake + `launchUi`, notifications
deferred. See `DOCUMENTATION.md §13`.

---

## 1. Goal & scope

Deliver an iOS implementation that:
1. **Matches the Android feature set** — capture, persist, inspect (list → detail →
   read → search), export.
2. **Keeps the release-stripping guarantee** — the inspector (UI, DB, capture) is
   **absent from a release IPA**, not merely disabled. Same PCI posture as Android.
3. **Preserves the one-line install** — no consumer Podfile surgery for the default
   path.
4. **Honors the design principles** (PRODUCT.md): data is the product; triage speed;
   faithful (truncation/redaction visibly marked); restrained polish; composed, not
   stock.

Out of scope for v1-iOS: iPad-specific layouts beyond adaptive SwiftUI, macOS,
watchOS.

---

## 2. What already exists vs what's needed

| Layer | Android | iOS status |
|-------|---------|------------|
| Dio interceptor + capture (Dart) | done, shared | **reused as-is** (platform-agnostic) |
| Channel contract (`MethodNames`/`PayloadKeys`) | in `contract.dart` + Kotlin | needs **Swift mirror** + golden test |
| Thin plugin (channel wiring) | `FalconerPlugin.kt` | needs **`FalconerPlugin.swift`** |
| Engine seam | `FalconerEngine` (interface) | needs **`FalconerEngine` (protocol)** |
| Real engine (DB + UI + capture) | `falconer-impl` (Compose/SQLDelight) | needs **Swift/SwiftUI/SQLite build** |
| No-op engine | `falconer-noop` | needs **`NoOpFalconerEngine.swift`** |
| Release stripping | Gradle variant deps + ServiceLoader + R8 | needs **`#if DEBUG` compile guard** |

**Key point for the presentation:** the Dart capture pipeline is done and shared.
iOS work = the *native sink, storage, UI, and the stripping mechanism*.

---

## 3. Architecture mapping (Android → iOS)

| Concern | Android | iOS choice |
|---------|---------|------------|
| Plugin language | Kotlin | Swift |
| Channels | `MethodChannel` / `EventChannel` | `FlutterMethodChannel` / `FlutterEventChannel` |
| Engine discovery | `ServiceLoader` (runtime) | **`#if DEBUG` compile-time selection** (simpler) |
| Storage | SQLDelight | **system `libsqlite3`** via a thin Swift wrapper (no 3rd-party dep) |
| UI | Jetpack Compose + `FalconerActivity` (own task) | **SwiftUI**, presented in its own `UIWindow`/modal |
| Concurrency | Kotlin coroutines / `Flow` | Swift `async`/`await` + `AsyncStream` (or Combine) |
| Live count stream | `Flow<Int>` → EventChannel | `AsyncStream<Int>` → EventChannel |
| Export/share | `Intent` share sheet | `UIActivityViewController` |
| Entry point | notification tap → separate task | **shake gesture** + programmatic `launchUi` (iOS has no launcher/notification-to-task model) |
| Notifications | ongoing summary notification | optional `UNUserNotificationCenter` local notif (iOS is restrictive — treat as nice-to-have) |

---

## 4. The hard part — release stripping on iOS

iOS has **no** `debugImplementation`/`releaseImplementation`. So the Android
mechanism (variant-scoped Maven deps + ServiceLoader) does not port directly. Two
viable approaches:

### Option A (RECOMMENDED default) — `#if DEBUG` compile guard, single pod
- The whole inspector (`RealFalconerEngine`, SwiftUI UI, SQLite storage, capture)
  is wrapped in `#if DEBUG … #endif`.
- The plugin selects the engine at **compile time**:
  ```swift
  #if DEBUG
  private let engine: FalconerEngine = RealFalconerEngine()
  #else
  private let engine: FalconerEngine = NoOpFalconerEngine()
  #endif
  ```
- Flutter's `flutter build ipa --release` compiles the pod with the **Release**
  configuration, where `DEBUG` is **not** defined → the inspector source is not
  compiled → absent from the IPA.
- **Storage uses the system `libsqlite3`** (already on every iOS device) via a small
  Swift wrapper, so there is **no third-party dependency** to leak into Release.
  Everything heavy is either `#if DEBUG` code or a system library.
- **Pros:** automatic, one-line install (no Podfile edit), physically stripped,
  simpler than Android (no ServiceLoader). **Cons:** the guarantee rides on the
  `DEBUG` compilation condition being unset in Release (true for standard Flutter
  builds — must be verified for archives/TestFlight, see Phase 5).

### Option B (advanced / belt-and-suspenders) — per-configuration CocoaPods pod
- Ship the inspector as a **separate pod** (`FalconerInspector`); consumers add it
  as `pod 'FalconerInspector', :configurations => ['Debug']` in their Podfile.
- The thin plugin looks up the real engine via the Obj-C runtime
  (`NSClassFromString("FalconerRealEngine")`) — present only when the Debug pod is
  linked, else falls back to the no-op.
- **Pros:** stripping decoupled from the `DEBUG` macro (works with custom build
  configs). **Cons:** consumer must edit the Podfile (loses one-line install) —
  this is Chucker's "Method B" ergonomics.

**Plan:** ship **Option A** as the default. Offer **Option B** as documented opt-in
for teams with custom configurations or a hard audit requirement. Both keep the Dart
runtime gate (`enableInReleaseBuilds`) as defence in depth.

---

## 5. Roadmap

| Phase | Title | Outcome |
|-------|-------|---------|
| 0 | Foundation & channel parity | iOS builds, `ping` works, contract mirrored |
| 1 | Capture ingestion | payloads parsed + redacted/truncated natively |
| 2 | Storage | transactions persisted; live count stream |
| 3 | Inspection UI (SwiftUI) | list → detail → search, on device |
| 4 | Entry points & export | launch UI, share/cURL export |
| 5 | Release stripping | inspector proven absent in release IPA |
| 6 | Testing & CI | XCTest + integration tests + iOS CI job |
| 7 | Docs, versioning, publish | iOS documented; pub.dev ready |

Phases 1–4 can partially overlap; Phase 5 (stripping) must be validated **before**
any release and re-checked whenever native deps change.

---

## 6. Phase-by-phase checklist

### Phase 0 — Foundation & channel parity
- [ ] Add `ios` to `pubspec.yaml` plugin platforms (`pluginClass: FalconerPlugin`).
- [ ] Create `ios/` with `falconer.podspec` (Swift, `s.swift_version`, min iOS
      deployment target — **decide 13 vs 15**, see Open Questions).
- [ ] `ios/Classes/FalconerPlugin.swift` — register `FlutterMethodChannel("falconer")`
      and `FlutterEventChannel("falconer/transactionCount")`.
- [ ] `FalconerEngine` protocol (attach/detach, configure, logRequest/Response/Error,
      clear, launchUi, observeCount).
- [ ] `NoOpFalconerEngine.swift` (inert; `observeCount` yields 0).
- [ ] `RealFalconerEngine.swift` stub under `#if DEBUG` + compile-time engine
      selection in the plugin.
- [ ] Swift `MethodNames` / `PayloadKeys` mirroring `lib/src/platform/contract.dart`.
- [ ] `ping → pong` round-trips on an iOS simulator.
- [ ] Golden test: Swift contract constants == Dart constants (guards drift).

### Phase 1 — Capture ingestion
- [ ] `PayloadMapper.swift` — parse channel `[String: Any]` maps into typed
      request/response/error models (mirror `PayloadMapper.kt`, tolerant of Int/Int64).
- [ ] `FalconerNativeConfig.swift` — parse the `configure` map; implement redaction
      (header masking) + truncation backstop (mirror the Kotlin logic exactly).
- [ ] `logRequest/logResponse/logError` route into the engine (buffer in memory
      until Phase 2 storage lands).
- [ ] Unit tests for mapper + config (redaction case-insensitive, truncation marker).

### Phase 2 — Storage (system SQLite)
- [ ] `SQLiteDatabase.swift` — thin wrapper over `libsqlite3` (open, migrate, query).
- [ ] Schema mirroring `Transactions.sq` (same columns; image BLOB in-row).
- [ ] `HttpTransactionDao.swift` — insert / merge-update on response|error / clear /
      `observeAll` / `observeFiltered(query)` / `observeById` / `observeCount`.
- [ ] `TransactionRepository.swift` — insert-on-request, merge on response/error,
      re-apply redaction/truncation before persist.
- [ ] `RetentionManager.swift` — startup + throttled on-write cleanup (mirror windows).
- [ ] Expose `observeCount()` as `AsyncStream<Int>` → EventChannel.
- [ ] DAO tests on an in-memory SQLite DB (no simulator needed).

### Phase 3 — Inspection UI (SwiftUI)
- [ ] `TransactionListView` — reverse-chron list, method/status/host/path/timing,
      search + filter; empty state.
- [ ] `TransactionDetailView` — Overview / Request / Response tabs.
- [ ] Body rendering: JSON pretty-print, search highlight, image preview,
      **visible markers** for truncated/redacted/unsupported bodies.
- [ ] `FalconerTheme` — quiet, composed identity (not stock UIKit); readable
      contrast ≥ 4.5:1.
- [ ] Host the UI in its own `UIWindow`/modal so it overlays any app screen.
- [ ] Keep pure logic (match-finding, formatting) separate from views for unit tests.

### Phase 4 — Entry points, export, notifications
- [ ] `launchUi` presents the inspector from Dart.
- [ ] **Shake-to-open** in debug (motion event) — the idiomatic iOS debug entry.
- [ ] Export: `TextExporter` + `CurlBuilder` (mirror Android); share via
      `UIActivityViewController`; redacted headers carried through, secrets not.
- [ ] (Optional) local capture-summary notification via `UNUserNotificationCenter`
      + permission request; document iOS limitations vs Android's ongoing notif.
- [ ] `clear` wipes storage and dismisses UI.

### Phase 5 — Release stripping (Method A parity)
- [ ] All Real/UI/DB/capture Swift under `#if DEBUG`; only `NoOpFalconerEngine`
      compiles in Release.
- [ ] No third-party pod dependencies (system `libsqlite3` only) — confirm the
      podspec adds nothing linked in Release.
- [ ] Build a **release** app: `flutter build ios --release` (and an archive).
- [ ] **Verify absence** (the proof, mirroring Android §5):
      - [ ] `nm`/`strings` the release `.app` binary → no `RealFalconerEngine`, no
            SwiftUI-inspector symbols, no inspector types.
      - [ ] Confirm no `FalconerInspector`/UI classes in the linked binary.
      - [ ] Debug build shows all of them present and the inspector working.
- [ ] Re-verify after **archive / TestFlight** config (guard against a build setup
      that defines `DEBUG` in Release).
- [ ] (Optional) implement Option B per-configuration pod + `NSClassFromString`
      lookup for teams needing the macro-independent guarantee.

### Phase 6 — Testing & CI
- [ ] XCTest targets: mapper, config, DAO (in-memory SQLite), export, redaction.
- [ ] Flutter `integration_test` exercised on an iOS simulator (capture → inspect).
- [ ] CI job on a **macOS runner**: `flutter build ios --no-codesign` (debug +
      release) + run XCTests. Release build doubles as a strip smoke-check.
- [ ] Extend `.github/workflows/ci.yml` with the iOS job; keep `pana` (iOS platform
      declared improves the pub score).

### Phase 7 — Docs, versioning, publish
- [ ] Update `DOCUMENTATION.md` (both repos): iOS sections, architecture mapping,
      the `#if DEBUG` stripping mechanism + proof.
- [ ] Update `README.md`: iOS support, install, entry-point (shake), any Podfile
      note for Option B.
- [ ] `CHANGELOG.md` entry.
- [ ] Bump plugin version (iOS native ships **inside** the plugin pod — no separate
      artifact repo, unlike Android/Maven — so no extra publishing step).
- [ ] Tag + (future) `flutter pub publish`.

---

## 7. Cross-cutting concerns

- **Contract parity is law.** `MethodNames`/`PayloadKeys` are defined once in Dart
  and mirrored in Swift *and* Kotlin; change all together; golden tests on every
  side fail on drift.
- **Redaction/truncation** must be byte-identical to Android so behaviour matches
  regardless of platform.
- **Distribution is simpler than Android.** No Maven equivalent needed for the
  default path — the native code lives in the plugin's `ios/` and ships in the
  plugin pod. (Only Option B introduces a separately-published pod.)
- **Design acceptance lens:** run the 5 PRODUCT.md principles over the SwiftUI UI
  the same way they gate the Compose UI.

---

## 8. Risks & open questions (decide before Phase 0)

1. **Minimum iOS deployment target?** SwiftUI needs iOS 13; modern `List`/search
   ergonomics want iOS 15+. Higher target = simpler UI code, fewer devices.
   *Recommendation: iOS 15.*
2. **Storage: system `libsqlite3` wrapper vs a Swift lib (GRDB/SQLite.swift)?** The
   wrapper keeps Release dependency-free (best for stripping); a lib is nicer to
   write but must be `#if DEBUG`-only and its pod dep conditionalized.
   *Recommendation: thin `libsqlite3` wrapper.*
3. **Stripping default: Option A (`#if DEBUG`) vs Option B (per-config pod)?**
   *Recommendation: A default, B documented opt-in.*
4. **Entry-point UX** for launching the inspector on iOS: shake, programmatic, or a
   floating debug button? *Recommendation: shake + programmatic `launchUi`.*
5. **Notifications:** implement the iOS local-notification summary, or document it as
   Android-only for v1? *Recommendation: defer; document the platform difference.*

---

## 9. Definition of done (iOS v1)

- [ ] Capture works on iOS with the same Dart API — no consumer code changes vs
      Android.
- [ ] Inspector UI reaches Android parity (list/detail/search/export) and passes the
      design principles.
- [ ] `flutter build ios --release` produces an IPA with **no inspector symbols and
      no extra dependencies** — verified, not assumed.
- [ ] XCTests + integration tests green in CI on a macOS runner.
- [ ] Docs + README + CHANGELOG updated; `pubspec.yaml` declares iOS; pub score not
      regressed.
- [ ] A real consumer app on a device: debug shows the inspector; release build is
      clean.

---

## 10. Effort sketch (rough)

- Phase 0–2 (foundation, capture, storage): the core plumbing — largest chunk.
- Phase 3 (SwiftUI UI): second largest; parity with the Compose UI drives it.
- Phase 4–5 (entry/export + stripping): moderate; stripping is quick to implement,
  the *verification* is what matters.
- Phase 6–7 (tests, CI, docs): steady.

Sequence strictly 0 → 2 (nothing to inspect without capture+storage); 3 and 4 can
interleave; **5 gates every release**.
