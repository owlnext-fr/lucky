import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _StreamReq extends Request with HasStreamBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/upload';
  @override int get contentLength => 5;
  @override Stream<List<int>> streamBody() => Stream.fromIterable([[1, 2, 3, 4, 5]]);
}

void main() {
  group('HasStreamBody', () {
    test('body() returns Stream<List<int>>', () =>
      expect(_StreamReq().body(), isA<Stream<List<int>>>()));
    test('buildOptions sets application/octet-stream contentType', () =>
      expect(_StreamReq().buildOptions()!.contentType, equals('application/octet-stream')));
    test('buildOptions sets Content-Length header', () =>
      expect(_StreamReq().buildOptions()!.headers!['Content-Length'], equals('5')));
  });
}
