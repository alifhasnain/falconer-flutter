import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';
import 'package:falconer/src/capture/transaction_dto.dart';
import 'package:falconer/src/falconer_runtime.dart' as runtime;
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_adapter.dart';

/// A decoder driven entirely by the test: [onRequest] / [onResponse] decide
/// what it returns, and [calls] records every invocation.
class _ScriptedDecoder implements FalconerBodyDecoder {
  _ScriptedDecoder(this.name, {this.onRequest, this.onResponse});

  @override
  final String name;

  final String? Function(FalconerBodyContext)? onRequest;
  final String? Function(FalconerBodyContext)? onResponse;

  final List<FalconerBodyContext> calls = [];

  @override
  String? decodeRequest(FalconerBodyContext context) {
    calls.add(context);
    return onRequest?.call(context);
  }

  @override
  String? decodeResponse(FalconerBodyContext context) {
    calls.add(context);
    return onResponse?.call(context);
  }
}

/// Always declines.
_ScriptedDecoder _declining(String name) => _ScriptedDecoder(name);

/// Always returns [text], on both legs.
_ScriptedDecoder _fixed(String name, String text) =>
    _ScriptedDecoder(name, onRequest: (_) => text, onResponse: (_) => text);

/// The reference-case shape: a JSON envelope whose `data` member is ciphertext,
/// here "encrypted" with base64 so the test needs no crypto dependency.
String? _envelope(FalconerBodyContext context) {
  final raw = context.raw;
  if (raw is! Map) return null;
  final cipher = raw['data'];
  if (cipher is! String || cipher.isEmpty) return null;

  final plain = utf8.decode(base64Decode(cipher));
  final out = Map<String, dynamic>.from(raw);
  out['data'] = jsonDecode(plain);
  return jsonEncode(out);
}

String _cipher(Object value) => base64Encode(utf8.encode(jsonEncode(value)));

RequestOptions _options({
  Object? data,
  Map<String, dynamic>? extra,
  Map<String, dynamic>? headers,
  String method = 'POST',
}) => RequestOptions(
  baseUrl: 'https://api.example.com',
  path: '/pay',
  method: method,
  data: data,
  extra: extra ?? <String, dynamic>{},
  headers: headers ?? <String, dynamic>{},
);

Response<dynamic> _response(Object? data, {int status = 200}) =>
    Response<dynamic>(
      requestOptions: _options(),
      statusCode: status,
      data: data,
      headers: Headers.fromMap({
        'content-type': ['application/json'],
      }),
    );

Dio _dio(MockAdapter adapter, RecordingSink sink) =>
    Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(FalconerInterceptor(sink: sink));

void main() {
  group('decoder chain', () {
    test('no decoders configured leaves the body untouched', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: const FalconerConfig(),
      );

      expect(dto['requestBody'], '{"a":1}');
    });

    test('a declining decoder preserves the raw body', () {
      final decoder = _declining('nope');

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(bodyDecoders: [decoder]),
      );

      expect(dto['requestBody'], '{"a":1}');
      expect(decoder.calls, hasLength(1));
    });

    test('a succeeding decoder replaces the stored body', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(bodyDecoders: [_fixed('fix', 'DECODED')]),
      );

      expect(dto['requestBody'], 'DECODED');
    });

    test('first non-null wins and later decoders are not invoked', () {
      final first = _declining('first');
      final second = _fixed('second', 'FROM SECOND');
      final third = _declining('third');

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(bodyDecoders: [first, second, third]),
      );

      expect(dto['requestBody'], 'FROM SECOND');
      expect(first.calls, hasLength(1));
      expect(second.calls, hasLength(1));
      expect(third.calls, isEmpty, reason: 'chain stops at the first hit');
    });

    test('a throwing decoder is skipped and the chain continues', () {
      final thrower = _ScriptedDecoder(
        'boom',
        onRequest: (_) => throw StateError('bad key'),
      );
      final next = _fixed('next', 'RECOVERED');

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(bodyDecoders: [thrower, next]),
      );

      expect(dto['requestBody'], 'RECOVERED');
    });

    test('a decoder whose name getter throws is skipped', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(
          bodyDecoders: [_ThrowingName(), _fixed('next', 'RECOVERED')],
        ),
      );

      expect(dto['requestBody'], 'RECOVERED');
    });

    test('every decoder throwing falls back to the raw body', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(
          bodyDecoders: [
            _ScriptedDecoder('a', onRequest: (_) => throw StateError('x')),
            _ScriptedDecoder('b', onRequest: (_) => throw StateError('y')),
          ],
        ),
      );

      expect(dto['requestBody'], '{"a":1}');
    });

    test('an empty string is a successful decode, not a decline', () {
      final after = _fixed('after', 'SHOULD NOT RUN');

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(bodyDecoders: [_fixed('empty', ''), after]),
      );

      expect(dto['requestBody'], '');
      expect(after.calls, isEmpty);
    });

    test('request and response legs dispatch to their own method', () {
      final decoder = _ScriptedDecoder(
        'sided',
        onRequest: (_) => 'REQ',
        onResponse: (_) => 'RES',
      );
      final config = FalconerConfig(bodyDecoders: [decoder]);

      final req = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: config,
      );
      final res = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: _response({'b': 2}),
        config: config,
      );

      expect(req['requestBody'], 'REQ');
      expect(res['responseBody'], 'RES');
    });
  });

  group('context', () {
    test('carries the request leg verbatim, with unredacted headers', () {
      final decoder = _declining('probe');
      final data = {'a': 1};

      buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(
          data: data,
          method: 'PUT',
          headers: {
            'Authorization': 'Bearer SUPER_SECRET',
            'content-type': 'application/json',
          },
          extra: {'isEncrypted': true},
        ),
        config: FalconerConfig(bodyDecoders: [decoder]),
      );

      final context = decoder.calls.single;
      expect(context.direction, FalconerDirection.request);
      expect(context.method, 'PUT');
      expect(context.uri.path, '/pay');
      expect(context.uri.host, 'api.example.com');
      expect(context.kind, BodyKind.json);
      expect(context.contentType, 'application/json');
      expect(context.statusCode, isNull);
      expect(context.text, '{"a":1}');
      expect(context.bytes, isNull);
      expect(context.raw, same(data));
      expect(context.extra['isEncrypted'], isTrue);
      expect(
        context.headers['Authorization'],
        'Bearer SUPER_SECRET',
        reason: 'decoders may need a header to pick a key',
      );
    });

    test('redaction still applies to the stored headers', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(
          data: {'a': 1},
          headers: {'Authorization': 'Bearer SUPER_SECRET'},
        ),
        config: FalconerConfig(bodyDecoders: [_declining('probe')]),
      );

      expect((dto['requestHeaders'] as Map)['Authorization'], '**redacted**');
    });

    test('carries the response leg, including the status code', () {
      final decoder = _declining('probe');

      buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 5,
        response: _response({'b': 2}, status: 503),
        config: FalconerConfig(bodyDecoders: [decoder]),
      );

      final context = decoder.calls.single;
      expect(context.direction, FalconerDirection.response);
      expect(context.statusCode, 503);
      expect(context.method, 'POST');
      expect(context.headers['content-type'], 'application/json');
      expect(context.text, '{"b":2}');
    });

    test('headers and extra are unmodifiable views', () {
      final decoder = _declining('probe');

      buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}, extra: {'k': 'v'}),
        config: FalconerConfig(bodyDecoders: [decoder]),
      );

      final context = decoder.calls.single;
      expect(() => context.headers['x'] = 'y', throwsUnsupportedError);
      expect(() => context.extra['x'] = 'y', throwsUnsupportedError);
    });

    test('multipart bodies reach the decoder as FormData via raw', () {
      final decoder = _declining('probe');
      final form = FormData.fromMap({'username': 'ada'});

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: form),
        config: FalconerConfig(bodyDecoders: [decoder]),
      );

      final context = decoder.calls.single;
      expect(context.kind, BodyKind.multipart);
      expect(context.raw, same(form));
      expect(context.text, contains('username: ada'));
      expect(dto['requestBodyKind'], 'multipart');
      expect(dto['requestBody'], contains('username: ada'));
    });
  });

  group('no mutation of the host payload', () {
    test('a decoder that copies leaves the original request map intact', () {
      final data = <String, dynamic>{
        'code': 200,
        'data': _cipher({'accounts': 2}),
      };
      final snapshot = jsonEncode(data);

      buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: data),
        config: FalconerConfig(
          bodyDecoders: [
            _ScriptedDecoder(
              'env',
              onRequest: _envelope,
              onResponse: _envelope,
            ),
          ],
        ),
      );

      expect(jsonEncode(data), snapshot);
    });

    test('a decoder that mutates raw cannot corrupt the response object', () {
      // The contract forbids mutating `raw`; this pins that Falconer itself
      // hands over the live object and does not copy it back over the host's.
      final data = <String, dynamic>{'code': 200};
      final response = _response(data);

      buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: response,
        config: FalconerConfig(
          bodyDecoders: [_ScriptedDecoder('ro', onResponse: (_) => 'OK')],
        ),
      );

      expect(response.data, same(data));
      expect(data, {'code': 200});
    });
  });

  group('partial envelope (the reference case)', () {
    test('decodes the ciphertext member and keeps its siblings', () {
      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: _response({
          'code': 200,
          'message': 'Success',
          'data': _cipher({
            'accounts': [
              {'id': 1},
            ],
          }),
        }),
        config: FalconerConfig(
          bodyDecoders: [_ScriptedDecoder('env', onResponse: _envelope)],
        ),
      );

      final body =
          jsonDecode(dto['responseBody'] as String) as Map<String, dynamic>;
      expect(body['code'], 200);
      expect(body['message'], 'Success');
      expect(body['data'], {
        'accounts': [
          {'id': 1},
        ],
      });
    });

    test('declines the unencrypted endpoints of the same API', () {
      // §2.5: reference-data endpoints ship in the clear; the decoder must be
      // able to decline them per transaction.
      final plain = {'code': 200, 'banks': [], 'data': null};

      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: _response(plain),
        config: FalconerConfig(
          bodyDecoders: [_ScriptedDecoder('env', onResponse: _envelope)],
        ),
      );

      expect(jsonDecode(dto['responseBody'] as String), plain);
    });
  });

  group('pipeline order', () {
    test('decoded text is truncated against its own length', () {
      final long = 'y' * 300;

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(
          maxContentLength: 100,
          bodyDecoders: [_fixed('big', long)],
        ),
      );

      final body = dto['requestBody'] as String;
      expect(body, startsWith('y' * 100));
      expect(body, contains('[Falconer: truncated — original 300 bytes'));
      expect(body, isNot(contains('y' * 101)));
    });

    test('a body that only becomes over-cap after decoding is truncated', () {
      // The captured body is small; the decoded one is not. Truncation must
      // follow the decoder, not precede it.
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'a': 1}),
        config: FalconerConfig(
          maxContentLength: 10,
          bodyDecoders: [_fixed('big', 'z' * 50)],
        ),
      );

      expect(dto['requestBody'], startsWith('z' * 10));
      expect(dto['requestBody'], contains('truncated'));
    });

    test('a body that becomes under-cap after decoding is not truncated', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'ciphertext': 'q' * 300}),
        config: FalconerConfig(
          maxContentLength: 100,
          bodyDecoders: [_fixed('small', 'short plaintext')],
        ),
      );

      expect(dto['requestBody'], 'short plaintext');
    });

    test('the reported content length stays the wire size', () {
      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(data: {'ciphertext': 'q' * 300}),
        config: FalconerConfig(bodyDecoders: [_fixed('small', 'tiny')]),
      );

      expect(dto['requestBody'], 'tiny');
      expect(dto['requestContentLength'], greaterThan(300));
    });
  });

  group('image bodies', () {
    test('an untouched image keeps its bytes', () {
      final png = [137, 80, 78, 71];
      final response = Response<dynamic>(
        requestOptions: _options(method: 'GET'),
        statusCode: 200,
        data: png,
        headers: Headers.fromMap({
          'content-type': ['image/png'],
        }),
      );

      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: response,
        config: FalconerConfig(bodyDecoders: [_declining('probe')]),
      );

      expect(dto['responseBodyKind'], 'image');
      expect(dto['responseImageBytes'], isNotNull);
    });

    test('a decoder that claims an image body replaces it', () {
      final png = [137, 80, 78, 71];
      final response = Response<dynamic>(
        requestOptions: _options(method: 'GET'),
        statusCode: 200,
        data: png,
        headers: Headers.fromMap({
          'content-type': ['image/png'],
        }),
      );

      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: response,
        config: FalconerConfig(bodyDecoders: [_fixed('img', 'PLAINTEXT')]),
      );

      expect(dto['responseBody'], 'PLAINTEXT');
      expect(dto['responseImageBytes'], isNull);
    });
  });

  group('per-transaction opt-out', () {
    test('skipDecode captures normally but runs no decoder', () async {
      final decoder = _fixed('fix', 'DECODED');
      final sink = RecordingSink();
      runtime.applyConfig(
        FalconerConfig(enabled: true, bodyDecoders: [decoder]),
      );
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));

      final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);
      await dio.post(
        '/pay',
        data: {'a': 1},
        options: Options(extra: {FalconerExtras.skipDecode: true}),
      );

      expect(sink.requests, hasLength(1));
      expect(sink.responses, hasLength(1));
      expect(sink.requests.single['requestBody'], '{"a":1}');
      expect(sink.responses.single['responseBody'], contains('"ok":true'));
      expect(decoder.calls, isEmpty);
    });

    test('skipCapture logs nothing at all', () async {
      final decoder = _fixed('fix', 'DECODED');
      final sink = RecordingSink();
      runtime.applyConfig(
        FalconerConfig(enabled: true, bodyDecoders: [decoder]),
      );
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));

      final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);
      await dio.post(
        '/card/enrol',
        data: {'pan': '[PLACEHOLDER]'},
        options: Options(extra: {FalconerExtras.skipCapture: true}),
      );

      expect(sink.requests, isEmpty);
      expect(sink.responses, isEmpty);
      expect(sink.errors, isEmpty);
      expect(decoder.calls, isEmpty);
    });

    test('skipCapture suppresses the error leg too', () async {
      final sink = RecordingSink();
      runtime.applyConfig(const FalconerConfig(enabled: true));
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));

      final dio = _dio(
        MockAdapter(
          (_) => throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 1),
            requestOptions: RequestOptions(path: '/slow'),
          ),
        ),
        sink,
      );

      await expectLater(
        dio.get(
          '/slow',
          options: Options(extra: {FalconerExtras.skipCapture: true}),
        ),
        throwsA(isA<DioException>()),
      );

      expect(sink.requests, isEmpty);
      expect(sink.errors, isEmpty);
    });

    test('a neighbouring transaction is unaffected by the opt-out', () async {
      final decoder = _fixed('fix', 'DECODED');
      final sink = RecordingSink();
      runtime.applyConfig(
        FalconerConfig(enabled: true, bodyDecoders: [decoder]),
      );
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));

      final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);
      await dio.post(
        '/skipped',
        data: {'a': 1},
        options: Options(extra: {FalconerExtras.skipCapture: true}),
      );
      await dio.post('/normal', data: {'a': 1});

      expect(sink.requests, hasLength(1));
      expect(sink.requests.single['path'], '/normal');
      expect(sink.requests.single['requestBody'], 'DECODED');
    });

    test('a flag set to something other than true does not opt out', () {
      final decoder = _fixed('fix', 'DECODED');

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: _options(
          data: {'a': 1},
          extra: {FalconerExtras.skipDecode: 'yes'},
        ),
        config: FalconerConfig(bodyDecoders: [decoder]),
      );

      expect(dto['requestBody'], 'DECODED');
    });
  });

  group('release gate', () {
    test('no decoder is invoked when capture is off', () async {
      final decoder = _fixed('fix', 'DECODED');
      final sink = RecordingSink();

      // What `resolveEnabled(true)` produces in a release build.
      runtime.applyConfig(
        FalconerConfig(enabled: false, bodyDecoders: [decoder]),
      );
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));
      expect(runtime.captureEnabled, isFalse);

      final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);
      await dio.post('/pay', data: {'a': 1});

      expect(sink.requests, isEmpty);
      expect(sink.responses, isEmpty);
      expect(decoder.calls, isEmpty);
    });

    test('resolveEnabled(true) is false however decoders are configured', () {
      final config = FalconerConfig(
        enabled: true,
        bodyDecoders: [_fixed('fix', 'DECODED')],
      );
      expect(config.resolveEnabled(true), isFalse);
    });
  });

  group('end to end through the interceptor', () {
    test('an encrypted round trip is readable on both legs', () async {
      final sink = RecordingSink();
      runtime.applyConfig(
        FalconerConfig(
          enabled: true,
          bodyDecoders: [
            _ScriptedDecoder(
              'env',
              onRequest: _envelope,
              onResponse: _envelope,
            ),
          ],
        ),
      );
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));

      final dio = _dio(
        MockAdapter(
          (_) => jsonResponse({
            'code': 200,
            'message': 'Success',
            'data': _cipher({'balance': '1200.50'}),
          }),
        ),
        sink,
      );

      await dio.post(
        '/account/balance',
        data: {
          'data': _cipher({'accountNo': '[PLACEHOLDER]'}),
        },
      );

      final req =
          jsonDecode(sink.requests.single['requestBody'] as String) as Map;
      expect(req['data'], {'accountNo': '[PLACEHOLDER]'});

      final res =
          jsonDecode(sink.responses.single['responseBody'] as String) as Map;
      expect(res['code'], 200);
      expect(res['data'], {'balance': '1200.50'});
    });

    test('a throwing decoder never surfaces in the Dio chain', () async {
      final sink = RecordingSink();
      runtime.applyConfig(
        FalconerConfig(
          enabled: true,
          bodyDecoders: [
            _ScriptedDecoder(
              'boom',
              onRequest: (_) => throw StateError('bad key'),
              onResponse: (_) => throw StateError('bad key'),
            ),
          ],
        ),
      );
      addTearDown(() => runtime.applyConfig(const FalconerConfig()));

      final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);
      final res = await dio.post('/pay', data: {'a': 1});

      expect(res.statusCode, 200);
      expect(sink.requests.single['requestBody'], '{"a":1}');
      expect(sink.responses.single['responseBody'], contains('"ok":true'));
    });
  });
}

/// A decoder whose `name` throws — the chain must survive that too.
class _ThrowingName implements FalconerBodyDecoder {
  @override
  String get name => throw StateError('no name');

  @override
  String? decodeRequest(FalconerBodyContext context) => 'CLAIMED';

  @override
  String? decodeResponse(FalconerBodyContext context) => 'CLAIMED';
}
