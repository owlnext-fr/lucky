import 'package:test/test.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _XmlReq extends Request with HasXmlBody {
  @override
  String get method => 'POST';
  @override
  String resolveEndpoint() => '/orders';
  @override
  String xmlBody() => '<order/>';
}

void main() {
  group('HasXmlBody', () {
    test('body() returns xmlBody() result',
        () => expect(_XmlReq().body(), equals('<order/>')));
    test(
        'buildOptions sets application/xml contentType',
        () => expect(
            _XmlReq().buildOptions()!.contentType, equals('application/xml')));
    test(
        'buildOptions sets Accept header',
        () => expect(_XmlReq().buildOptions()!.headers!['Accept'],
            equals('application/xml')));
  });
}
