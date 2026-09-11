/// Per-transaction opt-out flags read from `RequestOptions.extra`.
///
/// Both are part of the public API and namespaced so they cannot collide with
/// a host's own `extra` entries:
///
/// ```dart
/// await dio.post(
///   '/card/enrol',
///   data: payload,
///   options: Options(extra: {FalconerExtras.skipCapture: true}),
/// );
/// ```
///
/// A flag counts as set only when its value is exactly `true`.
abstract final class FalconerExtras {
  /// Capture the transaction normally, but do not run `FalconerBodyDecoder`s
  /// over its bodies. The raw captured body is stored.
  static const String skipDecode = 'falconer.skipDecode';

  /// Do not capture the transaction at all — no request, response or error row
  /// is created.
  ///
  /// Prefer this over redaction for endpoints that carry full card data, PINs
  /// or other regulated PII: not storing a payload is a stronger control than
  /// masking parts of it.
  static const String skipCapture = 'falconer.skipCapture';

  /// Whether [key] is set to `true` in [extra].
  static bool isSet(Map<String, dynamic> extra, String key) =>
      extra[key] == true;
}
