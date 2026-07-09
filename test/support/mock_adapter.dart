import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:falconer/src/capture/transaction_sink.dart';

/// A Dio adapter that returns a canned [ResponseBody] per request, so tests
/// exercise the full interceptor flow without real I/O.
class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.responder, {this.delay});

  final FutureOr<ResponseBody> Function(RequestOptions options) responder;
  final Duration? delay;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (delay != null) await Future<void>.delayed(delay!);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a JSON [ResponseBody] with content-type + content-length headers.
ResponseBody jsonResponse(Object data, {int status = 200}) {
  final bytes = utf8.encode(jsonEncode(data));
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      'content-length': ['${bytes.length}'],
    },
  );
}

/// Builds a binary [ResponseBody] (used for the image path).
ResponseBody bytesResponse(
  List<int> bytes, {
  int status = 200,
  String contentType = 'image/png',
}) {
  return ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: [contentType],
      'content-length': ['${bytes.length}'],
    },
  );
}

/// A [FalconerSink] that records every payload for assertions.
class RecordingSink implements FalconerSink {
  final List<Map<String, dynamic>> requests = [];
  final List<Map<String, dynamic>> responses = [];
  final List<Map<String, dynamic>> errors = [];

  @override
  void logRequest(Map<String, dynamic> data) => requests.add(data);

  @override
  void logResponse(Map<String, dynamic> data) => responses.add(data);

  @override
  void logError(Map<String, dynamic> data) => errors.add(data);
}
