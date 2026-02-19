import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:lucky_dart/lucky_dart.dart';

void main() {
  group('ConfigMerger.mergeHeaders', () {
    test('connector only', () =>
      expect(ConfigMerger.mergeHeaders({'A': '1'}, null), equals({'A': '1'})));
    test('request only', () =>
      expect(ConfigMerger.mergeHeaders(null, {'B': '2'}), equals({'B': '2'})));
    test('request overrides connector', () =>
      expect(ConfigMerger.mergeHeaders({'A': 'old'}, {'A': 'new'}), equals({'A': 'new'})));
    test('merges without conflict', () {
      final r = ConfigMerger.mergeHeaders({'Auth': 'tok'}, {'CT': 'json'});
      expect(r, containsPair('Auth', 'tok'));
      expect(r, containsPair('CT', 'json'));
    });
    test('both null returns empty', () =>
      expect(ConfigMerger.mergeHeaders(null, null), isEmpty));
  });

  group('ConfigMerger.mergeQuery', () {
    test('both null returns null', () =>
      expect(ConfigMerger.mergeQuery(null, null), isNull));
    test('request overrides connector', () =>
      expect(ConfigMerger.mergeQuery({'page': '1'}, {'page': '2'}), equals({'page': '2'})));
    test('merges without conflict', () {
      final r = ConfigMerger.mergeQuery({'api_key': 'abc'}, {'q': 'search'});
      expect(r, equals({'api_key': 'abc', 'q': 'search'}));
    });
  });

  group('ConfigMerger.mergeOptions', () {
    test('uses provided method', () {
      final r = ConfigMerger.mergeOptions(null, null, 'DELETE', null);
      expect(r.method, equals('DELETE'));
    });
    test('request contentType overrides connector', () {
      final r = ConfigMerger.mergeOptions(
        Options(contentType: 'text/plain'),
        Options(contentType: 'application/json'),
        'POST', null,
      );
      expect(r.contentType, equals('application/json'));
    });
    test('falls back to connector contentType', () {
      final r = ConfigMerger.mergeOptions(
        Options(contentType: 'text/plain'), Options(), 'GET', null,
      );
      expect(r.contentType, equals('text/plain'));
    });
    test('mergedHeaders take priority', () {
      final r = ConfigMerger.mergeOptions(
        Options(headers: {'X-A': '1'}),
        Options(headers: {'X-B': '2'}),
        'GET',
        {'X-C': '3'},
      );
      expect(r.headers, containsPair('X-A', '1'));
      expect(r.headers, containsPair('X-B', '2'));
      expect(r.headers, containsPair('X-C', '3'));
    });
  });
}
