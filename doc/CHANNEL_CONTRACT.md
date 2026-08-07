# Falconer channel contract

The frozen wire format between the Dart interceptor and the native backends.
Primitives only — no platform types cross the channel — so the Android and iOS
backends implement the same contract unchanged.

**Sources of truth**
- Dart (canonical): `lib/src/platform/contract.dart` (`FalconerChannels`, `FalconerMethods`, `PayloadKeys`, `ConfigKeys`, `BodyKinds`)
- Kotlin mirror: `falconer-core` → `channel/MethodNames.kt`, `channel/PayloadKeys.kt`
- Swift mirror: `ios/Classes/contract/Contract.swift`
- Builders: `lib/src/capture/transaction_dto.dart`
- Parsers: `falconer-impl` → `channel/PayloadMapper.kt` · `ios/Classes/capture/PayloadMapper.swift`

**Drift guard.** Golden tests pin every field on all three sides —
`test/contract/contract_test.dart` (Dart), `PayloadMapperTest.kt` (Kotlin) and
`ContractTests` in `example/ios/RunnerTests/RunnerTests.swift` (Swift). Renaming,
removing, or adding a field fails the matching golden test, so a contract change
means editing all three mirrors and this document together.

## Channels

| Name | Type | Purpose |
|------|------|---------|
| `falconer` | MethodChannel | all method calls below |
| `falconer/transactionCount` | EventChannel | live `int` count of stored transactions |

## Methods

| Method | Args | Result | Direction |
|--------|------|--------|-----------|
| `ping` | — | `String "pong"` | Dart → native (diagnostic) |
| `configure` | config `Map` (schema below) | `null` | Dart → native |
| `logRequest` | request payload (below) | `null` (fire-and-forget) | Dart → native |
| `logResponse` | response payload (below) | `null` (fire-and-forget) | Dart → native |
| `logError` | error payload (below) | `null` (fire-and-forget) | Dart → native |
| `clearTransactions` | — | `null` | Dart → native |
| `launchUi` | — | `null` | Dart → native |
| `requestNotificationPermission` | — | `bool` (grant result) | Dart → native |

Log calls are **fire-and-forget** (`unawaited`) so HTTP latency is untouched;
channel errors are swallowed (logged in debug) and never thrown into the Dio
chain.

## `configure`

Keys come from `ConfigKeys` (Dart), parsed by `FalconerNativeConfig` on both
native sides. `enabled` is the **resolved** `effectiveEnabled` (after release
gating, so always `false` in a release build), so the native side can see the
live capture state.

> Both platforms enforce `enabled` on every ingest as of `falconer-impl 0.2.0`
> (iOS `guard config.enabled`; Android `if (!nativeConfig.enabled) return` in
> `RealFalconerEngine.logRequest/logResponse/logError`). Against `falconer-impl
> 0.1.0` Android parsed the flag but ignored it, leaving the Dart gate as the
> only thing stopping capture there — a release build was unaffected either way,
> since that gate is unconditional in release and the impl artifact is
> debug-only.

| Key | Type | Notes |
|-----|------|-------|
| `enabled` | bool | resolved `effectiveEnabled` |
| `maxContentLength` | int | truncation cap, bytes |
| `redactHeaders` | List<String> | header names to mask |
| `retention` | String | `oneHour` / `oneDay` / `oneWeek` / `oneMonth`; Dart defaults to `oneWeek`. Rolling durations, not calendar units — `oneMonth` is a fixed 30 days and is the **maximum**; there is no unbounded window. Both native sides map an **unknown** key silently onto their one-day window (including the retired `forever`, which therefore deletes *more*, not less), so adding a value means updating every mirror together; the three golden tests pin the set |
| `showNotification` | bool | Android only; accepted and ignored on iOS |

Redaction (matched headers → `**redacted**`) and truncation happen **in Dart
before the payload is built**; both native sides re-apply them as a
defense-in-depth backstop, with byte-identical markers. The reported
`*ContentLength` is always the original size.

## Payloads

Types use Dart wire encoding (`StandardMessageCodec`). Integers arrive with a
width chosen by magnitude and are coerced tolerantly on both sides — via `Number`
on Kotlin, via `NSNumber`/`Int64` on Swift. `Uint8List` maps to `ByteArray`
(Kotlin) / `FlutterStandardTypedData` (Swift). Dart `null` arrives as `NSNull` on
Swift. `?` marks nullable / may-be-absent fields.

### `logRequest`

| Key | Type | Null? | Notes |
|-----|------|-------|-------|
| `id` | String | no | `<sessionEpochMs>-<counter>` |
| `startedAt` | int (ms) | no | epoch millis at send |
| `method` | String | no | HTTP method |
| `url` | String | no | full resolved URL |
| `host` | String | no | |
| `path` | String | no | |
| `scheme` | String | no | `http` / `https` |
| `requestHeaders` | Map<String,String> | no | flattened; redaction already applied |
| `requestContentType` | String | yes | |
| `requestContentLength` | int | yes | `content-length` header else encoded size |
| `requestBody` | String | yes | text/json/multipart summary; null for image/none |
| `requestBodyKind` | String | no | one of the body kinds |

### `logResponse`

| Key | Type | Null? | Notes |
|-----|------|-------|-------|
| `id` | String | no | matches the request |
| `completedAt` | int (ms) | no | |
| `tookMs` | int | no | wall-clock duration |
| `statusCode` | int | yes | nullable (rare Dio cases) |
| `statusMessage` | String | yes | |
| `protocol` | String | yes | always null (Dio does not expose it) |
| `responseHeaders` | Map<String,String> | no | flattened; redaction already applied |
| `responseContentType` | String | yes | |
| `responseContentLength` | int | yes | header else encoded size |
| `responseBody` | String | yes | null on the image path |
| `responseBodyKind` | String | yes | one of the body kinds |
| `responseImageBytes` | Uint8List | yes | image path only, `<= maxContentLength` |

> HTTP errors (4xx/5xx) carry a full response, so the interceptor emits
> `logResponse` for them (real status + body). `logError` is reserved for
> response-less transport failures.

### `logError`

| Key | Type | Null? | Notes |
|-----|------|-------|-------|
| `id` | String | no | |
| `completedAt` | int (ms) | no | |
| `tookMs` | int | no | |
| `error` | String | no | `DioException.toString()` |

## Body kinds

`none` · `text` · `json` · `multipart` · `image` · `unsupported`

- `multipart`: text fields + file metadata (filename, content-type, length).
  File bytes are **not** inlined.
- `image`: bytes carried in `responseImageBytes`; `*Body` is null.
- `unsupported`: streams and unknown binary — never drained, marked only.

## EventChannel `falconer/transactionCount`

Emits the current stored-transaction count as an `int` on listen and after each
insert/clear. Optional for Dart consumers. Backed by a `Flow<Int>` on Android and
an `AsyncStream<Int>` on iOS; in a release build the inert engine emits a single
`0`.
