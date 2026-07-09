import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';

/// Two independent Dio clients, each with its own [FalconerInterceptor].
///
/// The interceptors share one sink, so traffic from BOTH clients lands in a
/// single Falconer list/notification — demonstrating multi-Dio capture.
final Dio dioA = Dio(
  BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'),
)..interceptors.add(FalconerInterceptor());

final Dio dioB = Dio(BaseOptions(baseUrl: 'https://httpbin.org'))
  ..interceptors.add(FalconerInterceptor());

/// Headers that exercise redaction: `Authorization` (default redact set) and a
/// custom `X-Demo-Secret` (added to the redact set in `main`). Both appear as
/// `**redacted**` in the inspector — never persisted raw.
final Options _demoAuth = Options(
  headers: {
    'Authorization': 'Bearer demo-token-123',
    'X-Demo-Secret': 'top-secret-value',
  },
);

/// JSON GET (client A).
Future<void> jsonGet() => dioA.get<dynamic>('/todos/1', options: _demoAuth);

/// Multipart form POST (client B).
Future<void> formPost() => dioB.post<dynamic>(
  '/post',
  data: FormData.fromMap({'user': 'ada', 'role': 'admin'}),
);

/// Image GET — bytes path (client B).
Future<void> imageGet() => dioB.get<List<int>>(
  '/image/png',
  options: Options(responseType: ResponseType.bytes),
);

/// 404 error (client A) — captured as a response with status 404.
Future<void> notFound() => dioA.get<dynamic>('/this-path-does-not-exist-404');

/// Slow request, ~3s (client B).
Future<void> slowRequest() => dioB.get<dynamic>('/delay/3');
