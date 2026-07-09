import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';
import 'package:falconer/src/capture/transaction_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redaction', () {
    test('default config masks matched request headers, leaves others', () {
      final options = RequestOptions(
        baseUrl: 'https://api.example.com',
        path: '/pay',
        method: 'POST',
        headers: {
          'Authorization': 'Bearer SUPER_SECRET',
          'X-Api-Key': 'key-123',
          'Accept': 'application/json',
        },
      );

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: options,
        config: const FalconerConfig(),
      );

      final headers = dto['requestHeaders'] as Map;
      expect(headers['Authorization'], '**redacted**');
      expect(headers['X-Api-Key'], '**redacted**');
      expect(headers['Accept'], 'application/json');
    });

    test('empty redact set leaves headers untouched', () {
      final options = RequestOptions(
        path: '/x',
        headers: {'Authorization': 'Bearer X'},
      );

      final dto = buildRequestDto(
        id: 'x',
        startedAt: 0,
        options: options,
        config: const FalconerConfig(redactHeaders: {}),
      );

      expect((dto['requestHeaders'] as Map)['Authorization'], 'Bearer X');
    });
  });

  group('truncation', () {
    test('over-cap body is truncated, original size preserved', () {
      final big = 'x' * 100;
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: '/big'),
        statusCode: 200,
        data: big,
        headers: Headers.fromMap({
          'content-type': ['text/plain'],
          'content-length': ['100'],
        }),
      );

      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: response,
        config: const FalconerConfig(maxContentLength: 10),
      );

      final body = dto['responseBody'] as String;
      expect(body, startsWith('xxxxxxxxxx'));
      expect(body, contains('truncated'));
      expect(body, contains('original 100 bytes'));
      expect(dto['responseContentLength'], 100); // unchanged
    });

    test('over-cap image drops bytes and marks truncated', () {
      final bytes = Uint8List.fromList(List<int>.filled(50, 1));
      final response = Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/img',
          responseType: ResponseType.bytes,
        ),
        statusCode: 200,
        data: bytes,
        headers: Headers.fromMap({
          'content-type': ['image/png'],
          'content-length': ['50'],
        }),
      );

      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: response,
        config: const FalconerConfig(maxContentLength: 10),
      );

      expect(dto['responseImageBytes'], isNull);
      expect(dto['responseBodyKind'], 'image');
      expect(dto['responseBody'], contains('image truncated'));
    });

    test('under-cap body and image are untouched', () {
      final bytes = Uint8List.fromList(List<int>.filled(4, 9));
      final response = Response<dynamic>(
        requestOptions: RequestOptions(
          path: '/img',
          responseType: ResponseType.bytes,
        ),
        statusCode: 200,
        data: bytes,
        headers: Headers.fromMap({
          'content-type': ['image/png'],
          'content-length': ['4'],
        }),
      );

      final dto = buildResponseDto(
        id: 'x',
        completedAt: 1,
        tookMs: 1,
        response: response,
        config: const FalconerConfig(maxContentLength: 1000),
      );

      expect(dto['responseImageBytes'], bytes);
      expect(dto['responseBody'], isNull);
    });
  });
}
