import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:falconer/src/capture/body_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('encodeBody', () {
    test('null -> none', () {
      final r = encodeBody(null);
      expect(r.kind, BodyKind.none);
      expect(r.text, isNull);
      expect(r.bytes, isNull);
    });

    test('String -> text with utf8 size', () {
      final r = encodeBody('hello');
      expect(r.kind, BodyKind.text);
      expect(r.text, 'hello');
      expect(r.size, 5);
    });

    test('Map -> json', () {
      final r = encodeBody({'a': 1, 'b': 'two'});
      expect(r.kind, BodyKind.json);
      expect(jsonDecode(r.text!), {'a': 1, 'b': 'two'});
      expect(r.size, utf8.encode(r.text!).length);
    });

    test('List -> json', () {
      final r = encodeBody([1, 2, 3]);
      expect(r.kind, BodyKind.json);
      expect(jsonDecode(r.text!), [1, 2, 3]);
    });

    test('FormData -> multipart with fields and file metadata', () {
      final form = FormData.fromMap({
        'name': 'ada',
        'avatar': MultipartFile.fromBytes(
          [1, 2, 3, 4],
          filename: 'a.png',
          contentType: DioMediaType('image', 'png'),
        ),
      });
      final r = encodeBody(form);
      expect(r.kind, BodyKind.multipart);
      expect(r.text, contains('name: ada'));
      expect(r.text, contains('a.png'));
      expect(r.text, contains('image/png'));
      // File bytes are NOT inlined — metadata only.
      expect(r.text, isNot(contains('1, 2, 3, 4')));
      expect(r.size, greaterThan(0));
    });

    test('image bytes -> image path', () {
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      final r = encodeBody(bytes, contentType: 'image/png');
      expect(r.kind, BodyKind.image);
      expect(r.bytes, bytes);
      expect(r.size, 4);
    });

    test('non-image binary (Uint8List) -> unsupported, not inlined', () {
      final r = encodeBody(
        Uint8List.fromList([0, 1, 2, 3]),
        contentType: 'application/octet-stream',
      );
      expect(r.kind, BodyKind.unsupported);
      expect(r.bytes, isNull);
      expect(r.size, 4);
    });

    test('plain List<int> with no image type -> json', () {
      final r = encodeBody([0, 1, 2]);
      expect(r.kind, BodyKind.json);
      expect(r.text, '[0,1,2]');
    });
  });

  test('bodyKindName covers every kind', () {
    for (final kind in BodyKind.values) {
      expect(bodyKindName(kind), isNotEmpty);
    }
  });
}
