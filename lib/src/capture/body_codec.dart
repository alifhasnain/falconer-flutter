import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// How a body was captured. Mirrors the `*BodyKind` wire values (Phase 3).
enum BodyKind { none, text, json, multipart, image, unsupported }

/// Returns the wire string for a [BodyKind].
String bodyKindName(BodyKind kind) => switch (kind) {
  BodyKind.none => 'none',
  BodyKind.text => 'text',
  BodyKind.json => 'json',
  BodyKind.multipart => 'multipart',
  BodyKind.image => 'image',
  BodyKind.unsupported => 'unsupported',
};

/// The result of extracting a request/response body.
///
/// Exactly one of [text] / [bytes] is populated (or neither, for [BodyKind.none]).
/// [size] is the original body size in bytes when known.
class EncodedBody {
  const EncodedBody({required this.kind, this.text, this.bytes, this.size});

  final BodyKind kind;
  final String? text;
  final Uint8List? bytes;
  final int? size;

  static const EncodedBody none = EncodedBody(kind: BodyKind.none);
}

bool _isImage(String? contentType) =>
    contentType != null && contentType.toLowerCase().startsWith('image/');

/// Extracts [body] into a capturable representation without mutating it.
///
/// JSON-ish values are re-encoded into a *copy* — the caller's data is never
/// touched. Streams and unknown binary are marked, never drained.
EncodedBody encodeBody(Object? body, {String? contentType}) {
  if (body == null) return EncodedBody.none;

  if (body is String) {
    return EncodedBody(
      kind: BodyKind.text,
      text: body,
      size: utf8.encode(body).length,
    );
  }

  if (body is FormData) return _encodeFormData(body);

  // Binary buffers are checked before the Map/List (JSON) branch, since a
  // Uint8List / List<int> is also a List. A raw Uint8List is treated as binary;
  // a plain List<int> only takes the image path when the content type says so,
  // otherwise it is assumed to be a decoded JSON array.
  if (body is Uint8List) return _encodeBytes(body, contentType);
  if (body is List<int> && _isImage(contentType)) {
    return _encodeBytes(Uint8List.fromList(body), contentType);
  }

  if (body is Map || body is List) {
    try {
      final text = jsonEncode(body);
      return EncodedBody(
        kind: BodyKind.json,
        text: text,
        size: utf8.encode(text).length,
      );
    } catch (_) {
      final text = body.toString();
      return EncodedBody(
        kind: BodyKind.text,
        text: text,
        size: utf8.encode(text).length,
      );
    }
  }

  // Stream or unknown binary — do not consume it.
  return EncodedBody(
    kind: BodyKind.unsupported,
    text: '[${body.runtimeType} body not captured]',
  );
}

EncodedBody _encodeBytes(Uint8List bytes, String? contentType) {
  if (_isImage(contentType)) {
    return EncodedBody(kind: BodyKind.image, bytes: bytes, size: bytes.length);
  }
  return EncodedBody(
    kind: BodyKind.unsupported,
    text: '[binary ${bytes.length} bytes not captured]',
    size: bytes.length,
  );
}

EncodedBody _encodeFormData(FormData form) {
  final buffer = StringBuffer();
  for (final field in form.fields) {
    buffer.writeln('${field.key}: ${field.value}');
  }
  for (final entry in form.files) {
    final file = entry.value;
    final type = file.contentType?.mimeType ?? 'application/octet-stream';
    final name = file.filename ?? 'unnamed';
    // File bytes are intentionally not inlined in v1 — metadata only.
    buffer.writeln('${entry.key}: [file $name ($type, ${file.length} bytes)]');
  }
  return EncodedBody(
    kind: BodyKind.multipart,
    text: buffer.toString().trimRight(),
    size: form.length,
  );
}
