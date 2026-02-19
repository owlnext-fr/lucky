import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

class _MultipartReq extends Request with HasMultipartBody {
  @override String get method => 'POST';
  @override String resolveEndpoint() => '/upload';
  @override Future<FormData> multipartBody() async => FormData.fromMap({'f': 'v'});
}

void main() {
  group('HasMultipartBody', () {
    test('body() returns Future<FormData>', () =>
      expect(_MultipartReq().body(), isA<Future<FormData>>()));
    test('buildOptions sets multipart/form-data contentType', () =>
      expect(_MultipartReq().buildOptions()!.contentType, equals('multipart/form-data')));
  });
}
