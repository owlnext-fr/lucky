import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _TextReq extends Request with HasTextBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/notes';
  @override String textBody() => 'Hello!';
}

void main() {
  group('HasTextBody', () {
    test('body() returns textBody() result', () =>
      expect(_TextReq().body(), equals('Hello!')));
    test('buildOptions sets text/plain contentType', () =>
      expect(_TextReq().buildOptions()!.contentType, equals('text/plain')));
  });
}
