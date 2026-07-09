import 'package:dio/dio.dart';

import '../capture/transaction_dto.dart';
import '../capture/transaction_sink.dart';
import '../falconer_runtime.dart';
import 'transaction_id.dart';

/// Keys stored on `RequestOptions.extra` to correlate the two logging phases.
const String _idKey = '__falconer_id';
const String _startKey = '__falconer_start';

/// A Dio [Interceptor] that captures requests, responses and errors.
///
/// Add one line per Dio instance:
///
/// ```dart
/// final dio = Dio()..interceptors.add(FalconerInterceptor());
/// ```
///
/// Multiple interceptor instances funnel into one shared [FalconerSink], so
/// traffic from several Dio clients appears in a single store. Capture never
/// mutates `response.data` and never throws into the Dio chain.
class FalconerInterceptor extends Interceptor {
  /// Creates an interceptor. [sink] defaults to the shared platform sink;
  /// inject a fake in tests.
  FalconerInterceptor({FalconerSink? sink})
    : _sink = sink ?? const PlatformSink();

  final FalconerSink _sink;

  int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Zero-overhead short-circuit (Phase 7 owns `captureEnabled`).
    if (!captureEnabled) {
      handler.next(options);
      return;
    }
    try {
      final id = TransactionId.next();
      final startedAt = _now();
      options.extra[_idKey] = id;
      options.extra[_startKey] = startedAt;
      _sink.logRequest(
        buildRequestDto(
          id: id,
          startedAt: startedAt,
          options: options,
          config: activeConfig,
        ),
      );
    } catch (_) {
      // Capture must never break the request.
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (!captureEnabled) {
      handler.next(response);
      return;
    }
    try {
      final id = response.requestOptions.extra[_idKey] as String?;
      if (id != null) {
        final completedAt = _now();
        _sink.logResponse(
          buildResponseDto(
            id: id,
            completedAt: completedAt,
            tookMs: _took(response.requestOptions, completedAt),
            response: response,
            config: activeConfig,
          ),
        );
      }
    } catch (_) {
      // Capture must never break the response.
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!captureEnabled) {
      handler.next(err);
      return;
    }
    try {
      final id = err.requestOptions.extra[_idKey] as String?;
      if (id != null) {
        final completedAt = _now();
        final tookMs = _took(err.requestOptions, completedAt);
        final response = err.response;
        if (response != null) {
          // HTTP errors (404, 500, ...) carry a full response — capture it so
          // the transaction shows its real status and body.
          _sink.logResponse(
            buildResponseDto(
              id: id,
              completedAt: completedAt,
              tookMs: tookMs,
              response: response,
              config: activeConfig,
            ),
          );
        } else {
          // Transport errors (timeout, connection, cancel) have no response.
          _sink.logError(
            buildErrorDto(
              id: id,
              completedAt: completedAt,
              tookMs: tookMs,
              error: err,
            ),
          );
        }
      }
    } catch (_) {
      // Capture must never break the error chain.
    }
    handler.next(err);
  }

  int _took(RequestOptions options, int completedAt) {
    final startedAt = options.extra[_startKey] as int?;
    return startedAt == null ? 0 : completedAt - startedAt;
  }
}
