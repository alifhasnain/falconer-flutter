import 'dart:collection';
import 'dart:typed_data';

import 'body_codec.dart';

/// Which leg of a transaction a body belongs to.
enum FalconerDirection { request, response }

/// Everything a decoder needs to decide whether, and how, to decode a body.
///
/// Headers are the **raw, unredacted** values — a decoder may legitimately need
/// a header to pick a key or a scheme version. Redaction is applied to the
/// stored payload afterwards and is unaffected by what a decoder reads.
///
/// [headers] and [extra] are unmodifiable views; [raw] is the host's own object
/// and is read-only by contract (see [FalconerBodyDecoder]).
final class FalconerBodyContext {
  FalconerBodyContext({
    required this.direction,
    required this.method,
    required this.uri,
    required Map<String, String> headers,
    required Map<String, dynamic> extra,
    required this.kind,
    this.contentType,
    this.statusCode,
    this.text,
    this.bytes,
    this.raw,
  }) : headers = UnmodifiableMapView<String, String>(headers),
       extra = UnmodifiableMapView<String, dynamic>(extra);

  /// Whether this body was sent or received.
  final FalconerDirection direction;

  /// The HTTP method of the transaction, e.g. `'POST'`. Present on both legs.
  final String method;

  /// The full request URI. Present on both legs.
  final Uri uri;

  /// Raw, unredacted headers of this leg, multi-values joined with `', '`.
  final Map<String, String> headers;

  /// `RequestOptions.extra`, so a decoder can branch on the host's own flags.
  final Map<String, dynamic> extra;

  /// How Falconer classified the body.
  final BodyKind kind;

  /// The content type of this leg, when one was declared.
  final String? contentType;

  /// The HTTP status code. Always `null` on the request leg.
  final int? statusCode;

  /// The body as Falconer encoded it for display: JSON re-encoded to a string,
  /// text verbatim, multipart as its field summary. `null` for image bodies and
  /// for a body that was absent.
  final String? text;

  /// Raw bytes, when the body was binary. Never a drained stream.
  final Uint8List? bytes;

  /// The original Dart object Dio was handed (`Map`, `List`, `String`,
  /// `FormData`, ...). Provided so a decoder can address a single member
  /// without re-parsing.
  ///
  /// **Read-only by contract — never mutate it.** Falconer guarantees that
  /// capture does not touch the host's request or response data, and a decoder
  /// that mutates [raw] breaks that guarantee for the host's own code.
  final Object? raw;
}

/// Converts a captured body into something readable.
///
/// Falconer captures what Dio sends and receives. Apps that encrypt, compress
/// or otherwise obscure their payloads at the application layer can register a
/// decoder to make those bodies readable in the inspector:
///
/// ```dart
/// await Falconer.configure(
///   FalconerConfig(bodyDecoders: [MyEnvelopeDecoder()]),
/// );
/// ```
///
/// Return `null` to decline — the next registered decoder is tried, and if all
/// decline the raw captured body is stored unchanged. Declining is the correct
/// response for any transaction a decoder does not recognise; it must be cheap,
/// because it runs on every captured body.
///
/// Decoders run **in debug builds only** (capture is release-gated), on the
/// calling isolate, synchronously, inside the interceptor. Keep them fast and
/// side-effect free. A decoder that throws is skipped and the chain continues,
/// so a decoder bug can never surface in the host app.
///
/// ## Security
///
/// A decoder writes **plaintext into the on-device store**. That is only
/// defensible because capture is impossible in release builds. For endpoints
/// carrying full card data, PINs or other regulated PII, exclude the
/// transaction entirely with `FalconerExtras.skipCapture` rather than relying
/// on the decoder to be selective. A decoder must obtain its keys the way the
/// app already does (obfuscated build-time injection, keystore) — never by
/// hard-coding them into the decoder class. Never log decoded content.
abstract interface class FalconerBodyDecoder {
  /// A short name for the decoder, e.g. `'AES envelope'`. Keep it under ~24
  /// characters — a later release surfaces it in the inspector next to a
  /// decoded body.
  String get name;

  /// Decode an outgoing body. Return `null` to decline.
  String? decodeRequest(FalconerBodyContext context);

  /// Decode an incoming body. Return `null` to decline.
  String? decodeResponse(FalconerBodyContext context);
}

/// A body a decoder claimed, and the name of the decoder that claimed it.
///
/// Internal: phase 1 stores [text] in the existing `*Body` payload key, so
/// [decodedBy] does not yet cross the channel.
final class DecodedBody {
  const DecodedBody({required this.text, required this.decodedBy});

  /// The decoded body. May be empty — an empty string is a successful decode
  /// of an empty body, not a declined one.
  final String text;

  /// The `name` of the decoder that produced [text].
  final String decodedBy;
}

/// Runs [decoders] in order over [context]; the first non-null result wins.
///
/// Returns `null` when every decoder declines, when [decoders] is empty, or
/// when the transaction opted out via `FalconerExtras.skipDecode` (checked by
/// the caller). A decoder that throws — including from its `name` getter — is
/// skipped and the chain continues, per the failure policy: the worst case is a
/// transaction logged with its raw body.
DecodedBody? runBodyDecoders(
  List<FalconerBodyDecoder> decoders,
  FalconerBodyContext context,
) {
  for (final decoder in decoders) {
    try {
      final decoded = context.direction == FalconerDirection.request
          ? decoder.decodeRequest(context)
          : decoder.decodeResponse(context);
      if (decoded == null) continue;
      return DecodedBody(text: decoded, decodedBy: decoder.name);
    } catch (_) {
      // A broken decoder must not cost the transaction. Never log the body.
      continue;
    }
  }
  return null;
}
