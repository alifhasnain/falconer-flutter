import 'package:dio/dio.dart';

import '../config/falconer_config.dart';
import '../platform/contract.dart';
import 'body_codec.dart';

/// Builds the `logRequest` / `logResponse` / `logError` payload maps.
///
/// Field keys come from [PayloadKeys]. Redaction (matched headers → mask) and
/// truncation (bodies/images over `maxContentLength`) are applied here, in Dart,
/// before the map is built — so secrets and oversized payloads never cross the
/// channel (D2). Reported content lengths remain the original sizes.
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

  return <String, dynamic>{
    PayloadKeys.id: id,
    PayloadKeys.startedAt: startedAt,
    PayloadKeys.method: options.method,
    PayloadKeys.url: uri.toString(),
    PayloadKeys.host: uri.host,
    PayloadKeys.path: uri.path,
    PayloadKeys.scheme: uri.scheme,
    PayloadKeys.requestHeaders: _redact(
      _flattenRequestHeaders(options.headers),
      config,
    ),
    PayloadKeys.requestContentType: contentType,
    PayloadKeys.requestContentLength:
        _headerInt(options.headers, 'content-length') ?? body.size,
    PayloadKeys.requestBody: _truncate(body.text, body.size, config),
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

  return <String, dynamic>{
    PayloadKeys.id: id,
    PayloadKeys.completedAt: completedAt,
    PayloadKeys.tookMs: tookMs,
    PayloadKeys.statusCode: response.statusCode,
    PayloadKeys.statusMessage: response.statusMessage,
    // Dio does not surface the negotiated HTTP protocol; left null for v1.
    PayloadKeys.protocol: null,
    PayloadKeys.responseHeaders: _redact(
      _flattenResponseHeaders(response.headers),
      config,
    ),
    PayloadKeys.responseContentType: contentType,
    PayloadKeys.responseContentLength: headerLength ?? body.size,
    PayloadKeys.responseBody: imageOverCap
        ? '[Falconer: image truncated — ${body.size} bytes > ${config.maxContentLength}]'
        : _truncate(body.text, body.size, config),
    PayloadKeys.responseBodyKind: bodyKindName(body.kind),
    PayloadKeys.responseImageBytes: (isImage && !imageOverCap)
        ? body.bytes
        : null,
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
