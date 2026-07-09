import 'package:dio/dio.dart';
import 'package:falconer/src/capture/transaction_dto.dart';
import 'package:falconer/src/platform/contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contract constants are frozen (drift guard)', () {
    test('channels', () {
      expect(FalconerChannels.method, 'falconer');
      expect(
        FalconerChannels.transactionCountEvent,
        'falconer/transactionCount',
      );
    });

    test('method names', () {
      expect(
        {
          FalconerMethods.ping,
          FalconerMethods.configure,
          FalconerMethods.logRequest,
          FalconerMethods.logResponse,
          FalconerMethods.logError,
          FalconerMethods.clearTransactions,
          FalconerMethods.launchUi,
          FalconerMethods.requestNotificationPermission,
        },
        {
          'ping',
          'configure',
          'logRequest',
          'logResponse',
          'logError',
          'clearTransactions',
          'launchUi',
          'requestNotificationPermission',
        },
      );
    });

    test('payload keys', () {
      expect(PayloadKeys.id, 'id');
      expect(PayloadKeys.startedAt, 'startedAt');
      expect(PayloadKeys.method, 'method');
      expect(PayloadKeys.url, 'url');
      expect(PayloadKeys.host, 'host');
      expect(PayloadKeys.path, 'path');
      expect(PayloadKeys.scheme, 'scheme');
      expect(PayloadKeys.requestHeaders, 'requestHeaders');
      expect(PayloadKeys.requestContentType, 'requestContentType');
      expect(PayloadKeys.requestContentLength, 'requestContentLength');
      expect(PayloadKeys.requestBody, 'requestBody');
      expect(PayloadKeys.requestBodyKind, 'requestBodyKind');
      expect(PayloadKeys.completedAt, 'completedAt');
      expect(PayloadKeys.tookMs, 'tookMs');
      expect(PayloadKeys.statusCode, 'statusCode');
      expect(PayloadKeys.statusMessage, 'statusMessage');
      expect(PayloadKeys.protocol, 'protocol');
      expect(PayloadKeys.responseHeaders, 'responseHeaders');
      expect(PayloadKeys.responseContentType, 'responseContentType');
      expect(PayloadKeys.responseContentLength, 'responseContentLength');
      expect(PayloadKeys.responseBody, 'responseBody');
      expect(PayloadKeys.responseBodyKind, 'responseBodyKind');
      expect(PayloadKeys.responseImageBytes, 'responseImageBytes');
      expect(PayloadKeys.error, 'error');
    });

    test('body kinds', () {
      expect(
        {
          BodyKinds.none,
          BodyKinds.text,
          BodyKinds.json,
          BodyKinds.multipart,
          BodyKinds.image,
          BodyKinds.unsupported,
        },
        {'none', 'text', 'json', 'multipart', 'image', 'unsupported'},
      );
    });
  });

  group('golden payload maps', () {
    test('logRequest', () {
      final options = RequestOptions(
        baseUrl: 'https://api.example.com',
        path: '/users',
        method: 'GET',
        queryParameters: {'page': '1'},
        headers: {'accept': 'application/json'},
      );

      final dto = buildRequestDto(
        id: '1700000000000-0',
        startedAt: 1700000000000,
        options: options,
      );

      expect(dto, {
        'id': '1700000000000-0',
        'startedAt': 1700000000000,
        'method': 'GET',
        'url': 'https://api.example.com/users?page=1',
        'host': 'api.example.com',
        'path': '/users',
        'scheme': 'https',
        'requestHeaders': {'accept': 'application/json'},
        'requestContentType': null,
        'requestContentLength': null,
        'requestBody': null,
        'requestBodyKind': 'none',
      });
    });

    test('logResponse', () {
      final options = RequestOptions(
        baseUrl: 'https://api.example.com',
        path: '/users',
        method: 'GET',
      );
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        statusMessage: 'OK',
        data: {'ok': true},
        headers: Headers.fromMap({
          'content-type': ['application/json'],
          'content-length': ['11'],
        }),
      );

      final dto = buildResponseDto(
        id: '1700000000000-0',
        completedAt: 1700000000120,
        tookMs: 120,
        response: response,
      );

      expect(dto, {
        'id': '1700000000000-0',
        'completedAt': 1700000000120,
        'tookMs': 120,
        'statusCode': 200,
        'statusMessage': 'OK',
        'protocol': null,
        'responseHeaders': {
          'content-type': 'application/json',
          'content-length': '11',
        },
        'responseContentType': 'application/json',
        'responseContentLength': 11,
        'responseBody': '{"ok":true}',
        'responseBodyKind': 'json',
        'responseImageBytes': null,
      });
    });

    test('logError has exactly the contract keys', () {
      final options = RequestOptions(path: '/slow');
      final error = DioException.connectionTimeout(
        timeout: const Duration(seconds: 1),
        requestOptions: options,
      );

      final dto = buildErrorDto(
        id: '1700000000000-2',
        completedAt: 1700000001000,
        tookMs: 1000,
        error: error,
      );

      expect(dto.keys.toSet(), {'id', 'completedAt', 'tookMs', 'error'});
      expect(dto['id'], '1700000000000-2');
      expect(dto['completedAt'], 1700000001000);
      expect(dto['tookMs'], 1000);
      expect(dto['error'], isA<String>());
      expect(dto['error'], isNotEmpty);
    });
  });
}
