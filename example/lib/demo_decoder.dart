import 'dart:convert';

import 'package:falconer/falconer.dart';

/// A toy stand-in for real payload encryption, so the demo needs no crypto
/// dependency and no special backend.
///
/// **This is not encryption.** Base64 is an encoding — anyone can reverse it.
/// A production decoder would call the app's own cryptor here, with keys
/// obtained the way the app already obtains them (obfuscated build-time
/// injection, keystore), never hard-coded next to the decoder.
String demoEncrypt(Object? value) =>
    base64Encode(utf8.encode(jsonEncode(value)));

Object? _demoDecrypt(String cipherText) =>
    jsonDecode(utf8.decode(base64Decode(cipherText)));

/// Decodes the envelope shape this demo sends and receives:
///
/// ```jsonc
/// { "code": 200, "message": "OK", "data": "<ciphertext>" }
/// ```
///
/// Any string member named [key] is replaced by its decoded value, at any depth
/// — the demo posts to an echo endpoint, which nests the request envelope one
/// level down inside its reply.
///
/// Returning `null` declines the transaction: the next decoder runs, and if all
/// decline Falconer keeps the raw captured body. That is what keeps the demo's
/// unencrypted calls (`JSON GET`, `Image GET`, ...) readable as themselves.
class DemoEnvelopeDecoder implements FalconerBodyDecoder {
  const DemoEnvelopeDecoder({this.key = 'data'});

  /// The envelope member holding the ciphertext.
  final String key;

  @override
  String get name => 'demo envelope';

  @override
  String? decodeRequest(FalconerBodyContext context) => _decode(context);

  @override
  String? decodeResponse(FalconerBodyContext context) => _decode(context);

  String? _decode(FalconerBodyContext context) {
    final raw = context.raw;
    if (raw is! Map) return null;

    // Copy, never mutate: the host's own request/response object must come out
    // of capture exactly as it went in.
    final decoded = _walk(raw);
    if (decoded == null) return null;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// Returns a decoded copy of [value], or `null` when it holds no ciphertext.
  Object? _walk(Object? value) {
    if (value is Map) {
      Map<String, dynamic>? out;
      value.forEach((k, v) {
        final Object? replacement;
        if (k == key && v is String && v.isNotEmpty) {
          replacement = _tryDecrypt(v);
        } else {
          replacement = _walk(v);
        }
        if (replacement != null) {
          out ??= Map<String, dynamic>.from(value);
          out!['$k'] = replacement;
        }
      });
      return out;
    }
    if (value is List) {
      List<dynamic>? out;
      for (var i = 0; i < value.length; i++) {
        final replacement = _walk(value[i]);
        if (replacement != null) {
          out ??= List<dynamic>.from(value);
          out[i] = replacement;
        }
      }
      return out;
    }
    return null;
  }

  Object? _tryDecrypt(String cipherText) {
    try {
      return _demoDecrypt(cipherText);
    } catch (_) {
      // Not our ciphertext — leave it alone. Never log the value.
      return null;
    }
  }
}
