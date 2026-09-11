import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/falconer_config.dart';
import '../platform/contract.dart';
import 'body_codec.dart';
import 'body_decoder.dart';
import 'falconer_extras.dart';

/// Builds the `logRequest` / `logResponse` / `logError` payload maps.
///
/// Field keys come from [PayloadKeys]. Decoding (`bodyDecoders`), redaction
/// (matched headers → mask) and truncation (bodies/images over
/// `maxContentLength`) are applied here, in Dart, before the map is built — so
/// secrets and oversized payloads never cross the channel (D2). Reported
/// content lengths remain the original *wire* sizes, decoded or not.
///
/// Pipeline order, which the tests pin:
///
/// ```text
/// encodeBody → decoder chain → truncation → payload map → channel
/// ```
///
/// All values are primitives / `Map` / `Uint8List` — no platform types — so the
/// maps are reused verbatim by iOS.

Map<String, dynamic> buildRequestDto({
  required String id,
  required int startedAt,
  required RequestOptions options,
  FalconerConfig config = const FalconerConfig(),
}) {
  final uri = options.uri;
  final contentType =
      options.contentType ?? _headerValue(options.headers, 'content-type');
  final body = encodeBody(options.data, contentType: contentType);
  final headers = _flattenRequestHeaders(options.headers);

  final decoded = _decode(
    config: config,
    extra: options.extra,
    context: () => FalconerBodyContext(
      direction: FalconerDirection.request,
      method: options.method,
      uri: uri,
      headers: headers,
      extra: options.extra,
      kind: body.kind,
      contentType: contentType,
      text: body.text,
      bytes: _bytesOf(body, options.data),
      raw: options.data,
    ),
  );

  return <String, dynamic>{
    PayloadKeys.id: id,
    PayloadKeys.startedAt: startedAt,
    PayloadKeys.method: options.method,
    PayloadKeys.url: uri.toString(),
    PayloadKeys.host: uri.host,
    PayloadKeys.path: uri.path,
    PayloadKeys.scheme: uri.scheme,
    PayloadKeys.requestHeaders: _redact(headers, config),
    PayloadKeys.requestContentType: contentType,
    PayloadKeys.requestContentLength:
        _headerInt(options.headers, 'content-length') ?? body.size,
    PayloadKeys.requestBody: decoded != null
        ? _truncateDecoded(decoded, config)
        : _truncate(body.text, body.size, config),
    // A decoded body keeps the kind of what was captured — decoded-ness is not
    // a body kind.
    PayloadKeys.requestBodyKind: bodyKindName(body.kind),
  };
}

Map<String, dynamic> buildResponseDto({
  required String id,
  required int completedAt,
  required int tookMs,
  required Response<dynamic> response,
  FalconerConfig config = const FalconerConfig(),
}) {
  final contentType = response.headers.value('content-type');
  final isStream = response.requestOptions.responseType == ResponseType.stream;
  final body = isStream
      ? const EncodedBody(
          kind: BodyKind.unsupported,
          text: '[stream not captured]',
        )
      : encodeBody(response.data, contentType: contentType);

  final headerLength = int.tryParse(
    response.headers.value('content-length') ?? '',
  );

  final isImage = body.kind == BodyKind.image;
  final imageOverCap = isImage && (body.size ?? 0) > config.maxContentLength;

  final options = response.requestOptions;
  final headers = _flattenResponseHeaders(response.headers);

  final decoded = _decode(
    config: config,
    extra: options.extra,
    context: () => FalconerBodyContext(
      direction: FalconerDirection.response,
      method: options.method,
      uri: options.uri,
      headers: headers,
      extra: options.extra,
      kind: body.kind,
      contentType: contentType,
      statusCode: response.statusCode,
      text: body.text,
      bytes: _bytesOf(body, response.data),
      raw: response.data,
    ),
  );

  return <String, dynamic>{
    PayloadKeys.id: id,
    PayloadKeys.completedAt: completedAt,
    PayloadKeys.tookMs: tookMs,
    PayloadKeys.statusCode: response.statusCode,
    PayloadKeys.statusMessage: response.statusMessage,
    // Dio does not surface the negotiated HTTP protocol; left null for v1.
    PayloadKeys.protocol: null,
    PayloadKeys.responseHeaders: _redact(headers, config),
    PayloadKeys.responseContentType: contentType,
    PayloadKeys.responseContentLength: headerLength ?? body.size,
    PayloadKeys.responseBody: switch (decoded) {
      // A decoder that claims an image body replaces it: what it produced is
      // more useful than the bytes it was derived from.
      final DecodedBody d => _truncateDecoded(d, config),
      _ when imageOverCap =>
        '[Falconer: image truncated — ${body.size} bytes > ${config.maxContentLength}]',
      _ => _truncate(body.text, body.size, config),
    },
    PayloadKeys.responseBodyKind: bodyKindName(body.kind),
    PayloadKeys.responseImageBytes:
        (isImage && !imageOverCap && decoded == null) ? body.bytes : null,
  };
}

Map<String, dynamic> buildErrorDto({
  required String id,
  required int completedAt,
  required int tookMs,
  required DioException error,
}) {
  return <String, dynamic>{
    PayloadKeys.id: id,
    PayloadKeys.completedAt: completedAt,
    PayloadKeys.tookMs: tookMs,
    PayloadKeys.error: error.toString(),
  };
}

/// Runs the configured decoder chain, unless there is nothing to run or the
/// transaction opted out with `FalconerExtras.skipDecode`.
///
/// [context] is a thunk so the context object — and the header flattening
/// behind it — is only built when a decoder can actually consume it. With no
/// decoders registered (the default) this costs one `isEmpty` check.
DecodedBody? _decode({
  required FalconerConfig config,
  required Map<String, dynamic> extra,
  required FalconerBodyContext Function() context,
}) {
  if (config.bodyDecoders.isEmpty) return null;
  if (FalconerExtras.isSet(extra, FalconerExtras.skipDecode)) return null;
  return runBodyDecoders(config.bodyDecoders, context());
}

/// Truncates decoded text against its own byte length — the captured body's
/// size describes the wire bytes, which the decoded text no longer matches.
String _truncateDecoded(DecodedBody decoded, FalconerConfig config) {
  final size = utf8.encode(decoded.text).length;
  return _truncate(decoded.text, size, config) ?? decoded.text;
}

/// The raw bytes to hand a decoder: what the codec kept, or the original object
/// when it was already a byte buffer the codec chose not to carry.
Uint8List? _bytesOf(EncodedBody body, Object? raw) =>
    body.bytes ?? (raw is Uint8List ? raw : null);

/// Masks header values whose names match [FalconerConfig.redactHeaders]
/// (case-insensitive).
Map<String, String> _redact(
  Map<String, String> headers,
  FalconerConfig config,
) {
  if (config.redactHeaders.isEmpty) return headers;
  final lower = config.redactHeaders.map((e) => e.toLowerCase()).toSet();
  return headers.map(
    (key, value) => MapEntry(
      key,
      lower.contains(key.toLowerCase()) ? FalconerConfig.redactedMarker : value,
    ),
  );
}

/// Truncates an over-cap body, appending a visible marker. The original [size]
/// is still reported by the caller's content-length field.
String? _truncate(String? body, int? size, FalconerConfig config) {
  if (body == null || size == null || size <= config.maxContentLength) {
    return body;
  }
  final max = config.maxContentLength;
  final head = body.length > max ? body.substring(0, max) : body;
  return '$head\n\n[Falconer: truncated — original $size bytes, showing first $max]';
}

Map<String, String> _flattenRequestHeaders(Map<String, dynamic> headers) {
  final out = <String, String>{};
  headers.forEach((key, value) {
    out[key] = value is Iterable ? value.join(', ') : '$value';
  });
  return out;
}

Map<String, String> _flattenResponseHeaders(Headers headers) {
  final out = <String, String>{};
  headers.forEach((name, values) => out[name] = values.join(', '));
  return out;
}

String? _headerValue(Map<String, dynamic> headers, String key) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == key) {
      final v = entry.value;
      return v is Iterable ? v.join(', ') : '$v';
    }
  }
  return null;
}

int? _headerInt(Map<String, dynamic> headers, String key) =>
    int.tryParse(_headerValue(headers, key) ?? '');
