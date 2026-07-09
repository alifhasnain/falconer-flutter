import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';
import 'package:falconer/src/falconer_runtime.dart' as runtime;
import 'package:flutter_test/flutter_test.dart';

import '../support/mock_adapter.dart';

Dio _dio(MockAdapter adapter, RecordingSink sink) =>
    Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(FalconerInterceptor(sink: sink));

void main() {
  late RecordingSink sink;

  setUp(() {
    sink = RecordingSink();
    runtime.captureEnabled = true;
  });

  test('JSON GET captures method, url parts, status and bodies', () async {
    final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);

    final res = await dio.get('/users', queryParameters: {'page': '1'});

    expect(res.statusCode, 200);
    expect(sink.requests, hasLength(1));
    expect(sink.responses, hasLength(1));

    final req = sink.requests.single;
    expect(req['method'], 'GET');
    expect(req['host'], 'api.example.com');
    expect(req['path'], '/users');
    expect(req['scheme'], 'https');
    expect(req['url'], contains('page=1'));
    expect(req['requestBodyKind'], 'none');

    final resp = sink.responses.single;
    expect(resp['id'], req['id']);
    expect(resp['statusCode'], 200);
    expect(resp['responseBodyKind'], 'json');
    expect(resp['responseBody'], contains('"ok":true'));
    expect(resp['responseImageBytes'], isNull);
  });

  test('form POST captures multipart fields', () async {
    final dio = _dio(MockAdapter((_) => jsonResponse({'id': 7})), sink);

    final form = FormData.fromMap({'username': 'ada', 'role': 'admin'});
    await dio.post('/signup', data: form);

    final req = sink.requests.single;
    expect(req['method'], 'POST');
    expect(req['requestBodyKind'], 'multipart');
    expect(req['requestBody'], contains('username: ada'));
    expect(req['requestBody'], contains('role: admin'));
  });

  test('image GET captures bytes on the image path', () async {
    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10]);
    final dio = _dio(MockAdapter((_) => bytesResponse(png)), sink);

    await dio.get<List<int>>(
      '/logo.png',
      options: Options(responseType: ResponseType.bytes),
    );

    final resp = sink.responses.single;
    expect(resp['responseBodyKind'], 'image');
    expect(resp['responseImageBytes'], isA<Uint8List>());
    expect(resp['responseImageBytes'], png);
  });

  test('404 is captured as a response with its status and body', () async {
    final dio = _dio(
      MockAdapter((_) => jsonResponse({'error': 'not found'}, status: 404)),
      sink,
    );

    await expectLater(dio.get('/missing'), throwsA(isA<DioException>()));

    expect(sink.errors, isEmpty);
    expect(sink.responses, hasLength(1));
    final resp = sink.responses.single;
    expect(resp['statusCode'], 404);
    expect(resp['responseBody'], contains('not found'));
    expect(resp['id'], sink.requests.single['id']);
  });

  test('transport error (no response) is captured via logError', () async {
    final dio = _dio(
      MockAdapter(
        (options) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      ),
      sink,
    );

    await expectLater(dio.get('/slow'), throwsA(isA<DioException>()));

    expect(sink.responses, isEmpty);
    expect(sink.errors, hasLength(1));
    expect(sink.errors.single['id'], sink.requests.single['id']);
    expect(sink.errors.single['error'], isNotEmpty);
  });

  test('multiple Dio instances funnel into one shared sink', () async {
    final dioA = _dio(MockAdapter((_) => jsonResponse({'a': 1})), sink);
    final dioB = _dio(MockAdapter((_) => jsonResponse({'b': 2})), sink);

    await dioA.get('/a');
    await dioB.get('/b');

    expect(sink.requests, hasLength(2));
    expect(sink.responses, hasLength(2));
    final ids = sink.requests.map((r) => r['id']).toSet();
    expect(ids, hasLength(2), reason: 'each client gets a distinct id');
  });

  test("caller's response.data is unchanged by the interceptor", () async {
    const payload = {
      'hello': 'world',
      'n': 42,
      'nested': {
        'k': [1, 2, 3],
      },
    };

    final plain = Dio()
      ..httpClientAdapter = MockAdapter((_) => jsonResponse(payload));
    final captured = _dio(MockAdapter((_) => jsonResponse(payload)), sink);

    final r1 = await plain.get('https://api.example.com/x');
    final r2 = await captured.get('/x');

    expect(r2.data, equals(r1.data));
    expect(r2.data, equals(payload));
  });

  test('tookMs reflects wall-clock latency within tolerance', () async {
    final dio = _dio(
      MockAdapter(
        (_) => jsonResponse({'ok': true}),
        delay: const Duration(milliseconds: 60),
      ),
      sink,
    );

    await dio.get('/timed');

    final took = sink.responses.single['tookMs'] as int;
    expect(took, greaterThanOrEqualTo(40));
    expect(took, lessThan(5000));
  });

  test('disabled interceptor reads no body and sends nothing', () async {
    runtime.captureEnabled = false;
    final dio = _dio(MockAdapter((_) => jsonResponse({'ok': true})), sink);

    final res = await dio.get('/x');

    expect(res.statusCode, 200);
    expect(sink.requests, isEmpty);
    expect(sink.responses, isEmpty);
    expect(sink.errors, isEmpty);
  });
}
