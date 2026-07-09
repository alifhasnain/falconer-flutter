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
