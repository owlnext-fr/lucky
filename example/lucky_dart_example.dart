// ignore_for_file: avoid_print
import 'package:lucky_dart/lucky_dart.dart';

// ─── 1. Define the Connector ─────────────────────────────────────────────────

/// One Connector per API — holds the base URL, default headers, and auth.
///
/// The [posts] accessor groups all post-related calls, enabling
/// `api.posts.list()` instead of `api.send(GetPostsRequest())`.
class JsonPlaceholderConnector extends Connector {
  JsonPlaceholderConnector({Authenticator? auth}) : _auth = auth;
  final Authenticator? _auth;

  @override
  String resolveBaseUrl() => 'https://jsonplaceholder.typicode.com';

  @override
  Map<String, String>? defaultHeaders() => {'Accept': 'application/json'};

  @override
  Authenticator? get authenticator => _auth;

  // Endpoint accessor — enables api.posts.list(), api.posts.get(1), etc.
  late final posts = PostsEndpoint(this);
}

// ─── 2. Requests ─────────────────────────────────────────────────────────────

class GetPostsRequest extends Request {
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/posts';
}

class GetPostRequest extends Request {
  final int id;
  GetPostRequest(this.id);
  @override
  String get method => 'GET';
  @override
  String resolveEndpoint() => '/posts/$id';
}

class CreatePostRequest extends Request with HasJsonBody {
  final String title;
  final String content;
  final int userId;

  CreatePostRequest({
    required this.title,
    required this.content,
    required this.userId,
  });

  @override
  String get method => 'POST';
  @override
  String resolveEndpoint() => '/posts';

  @override
  Map<String, dynamic> jsonBody() => {
        'title': title,
        'body': content,
        'userId': userId,
      };
}

// ─── 3. Endpoint class ───────────────────────────────────────────────────────

/// Groups all post-related requests under one namespace.
class PostsEndpoint {
  final Connector _connector;
  PostsEndpoint(this._connector);

  Future<LuckyResponse> list() => _connector.send(GetPostsRequest());
  Future<LuckyResponse> get(int id) => _connector.send(GetPostRequest(id));
  Future<LuckyResponse> create({
    required String title,
    required String content,
    required int userId,
  }) =>
      _connector.send(CreatePostRequest(
        title: title,
        content: content,
        userId: userId,
      ));
}

// ─── 4. Main ─────────────────────────────────────────────────────────────────

Future<void> main() async {
  final api = JsonPlaceholderConnector();

  // ── GET list ─────────────────────────────────────────────────────────────────
  print('--- Listing posts ---');
  final posts = await api.posts.list();
  final items = posts.jsonList();
  print('Got ${items.length} posts');
  print('First: ${items.first['title']}');

  // ── GET single ───────────────────────────────────────────────────────────────
  print('\n--- Getting post #1 ---');
  final post = await api.posts.get(1);
  print('Title: ${post.json()['title']}');
  print('isSuccessful: ${post.isSuccessful}');
  print('isJson: ${post.isJson}');

  // Custom transformer
  final title = post.as((r) => r.json()['title'] as String);
  print('title via as(): $title');

  // ── POST (JSON body) ──────────────────────────────────────────────────────────
  print('\n--- Creating a post ---');
  final created = await api.posts.create(
    title: 'Lucky Dart is great',
    content: 'Structured API calls without the boilerplate.',
    userId: 1,
  );
  print('Status: ${created.statusCode}');
  print('Created: ${created.json()}');

  // ── Error handling ────────────────────────────────────────────────────────────
  print('\n--- Error handling (throwOnError=true by default) ---');
  try {
    await api.posts.get(99999); // 404 on jsonplaceholder
  } on NotFoundException catch (e) {
    print('Caught NotFoundException: ${e.message}');
  } on LuckyException catch (e) {
    print('Caught HTTP ${e.statusCode}: ${e.message}');
  }
}
