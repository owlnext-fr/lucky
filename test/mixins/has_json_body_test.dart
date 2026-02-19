import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _JsonReq extends Request with HasJsonBody {
  @override
  String get method => 'POST';
  @override
  String resolveEndpoint() => '/test';
  @override
  Map<String, dynamic> jsonBody() => {'key': 'value'};
}

void main() {
  group('HasJsonBody', () {
    test('body() returns jsonBody() result',
        () => expect(_JsonReq().body(), equals({'key': 'value'})));
    test(
        'buildOptions sets application/json contentType',
        () => expect(_JsonReq().buildOptions()!.contentType,
            equals('application/json')));
    test(
        'buildOptions sets Content-Type header',
        () => expect(_JsonReq().buildOptions()!.headers!['Content-Type'],
            equals('application/json')));
    test(
        'buildOptions sets Accept header',
        () => expect(_JsonReq().buildOptions()!.headers!['Accept'],
            equals('application/json')));
  });
}
