import 'package:dio/dio.dart';
import 'package:falconer/falconer.dart';

import 'demo_decoder.dart';

/// Two independent Dio clients, each with its own [FalconerInterceptor].
///
/// The interceptors share one sink, so traffic from BOTH clients lands in a
/// single Falconer list/notification — demonstrating multi-Dio capture.
final Dio dioA = Dio(
  BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'),
)..interceptors.add(FalconerInterceptor());

final Dio dioB = Dio(BaseOptions(baseUrl: 'https://postman-echo.com'))
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
///
/// Absolute URL, so it ignores client B's `baseUrl` — postman-echo serves no
/// images. Returns `image/jpeg`, which is what puts this on the image path and
/// gives the inspector something to preview.
Future<void> imageGet() => dioB.get<List<int>>(
  'https://picsum.photos/300/200',
  options: Options(responseType: ResponseType.bytes),
);

/// 404 error (client A) — captured as a response with status 404.
Future<void> notFound() => dioA.get<dynamic>('/this-path-does-not-exist-404');

/// Slow request, ~3s (client B).
Future<void> slowRequest() => dioB.get<dynamic>('/delay/3');

/// Encrypted POST (client B) — what an app with payload encryption sends.
///
/// The body is a single-key envelope whose `data` member is ciphertext. Without
/// a decoder the inspector shows that ciphertext; `DemoEnvelopeDecoder`, wired
/// up in `main`, makes both legs readable. The echo endpoint replies with the
/// envelope nested inside its own JSON, so the response decodes too.
Future<void> encryptedPost() => dioB.post<dynamic>(
  '/post',
  data: {
    'code': 200,
    'message': 'demo',
    'data': demoEncrypt({
      'accountNo': '[PLACEHOLDER]',
      'amount': '1200.50',
      'currency': 'BDT',
    }),
  },
  options: _demoAuth,
);

/// Excluded from capture entirely (client B).
///
/// `FalconerExtras.skipCapture` is the right control for an endpoint carrying
/// card data or a PIN: no row is created at all, so there is nothing on the
/// device to mask, export or leak. Run it and watch the captured count stay
/// where it was.
Future<void> skippedPost() => dioB.post<dynamic>(
  '/post',
  data: {'pan': '[PLACEHOLDER]', 'pin': '[PLACEHOLDER]'},
  options: Options(extra: {FalconerExtras.skipCapture: true}),
);
