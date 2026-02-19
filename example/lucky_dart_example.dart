// ignore_for_file: avoid_print
import 'package:lucky_dart/lucky_dart.dart';

// ─── 1. Define the Connector ─────────────────────────────────────────────────

/// One Connector per API — holds base URL, default headers, and auth.
class JsonPlaceholderConnector extends Connector {
  @override
  String resolveBaseUrl() => 'https://jsonplaceholder.typicode.com';

  @override
  Map<String, String>? defaultHeaders() => {'Accept': 'application/json'};
}

// ─── 2. Define Requests ──────────────────────────────────────────────────────

/// GET /posts — returns a list of posts.
class GetPostsRequest extends Request {
  @override
  String get method => 'GET';

  @override
  String resolveEndpoint() => '/posts';
}

/// GET /posts/:id — returns a single post.
class GetPostRequest extends Request {
  final int id;
  GetPostRequest(this.id);

  @override
  String get method => 'GET';

  @override
  String resolveEndpoint() => '/posts/$id';
}

/// POST /posts — creates a post with a JSON body.
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

// ─── 3. Endpoint class (optional but recommended for large APIs) ──────────────

/// Groups all post-related requests under one namespace.
///
/// Enables the `connector.posts.list()` calling pattern.
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

/// Connector with endpoint accessors — enables `api.posts.list()`.
class ApiConnector extends Connector {
  ApiConnector({Authenticator? auth}) : _auth = auth;
  final Authenticator? _auth;

  @override
  String resolveBaseUrl() => 'https://jsonplaceholder.typicode.com';

  @override
  Map<String, String>? defaultHeaders() => {'Accept': 'application/json'};

  @override
  Authenticator? get authenticator => _auth;

  // Endpoint accessors
  late final posts = PostsEndpoint(this);
}

// ─── 4. Main ─────────────────────────────────────────────────────────────────

Future<void> main() async {
  final api = ApiConnector();

  // ── GET list ────────────────────────────────────────────────────────────────
  print('--- Listing posts ---');
  final listResponse = await api.posts.list();
  final posts = listResponse.jsonList();
  print('Got ${posts.length} posts');
  print('First: ${posts.first['title']}');

  // ── GET single ──────────────────────────────────────────────────────────────
  print('\n--- Getting post #1 ---');
  final postResponse = await api.posts.get(1);
  final post = postResponse.json();
  print('Title: ${post['title']}');
  print('Body: ${post['body']}');

  // ── POST (JSON body) ────────────────────────────────────────────────────────
  print('\n--- Creating a post ---');
  final created = await api.posts.create(
    title: 'Lucky Dart is awesome',
    content: 'Structured API calls without the boilerplate.',
    userId: 1,
  );
  print('Created: ${created.json()}');
  print('Status: ${created.statusCode}');

  // ── Error handling ───────────────────────────────────────────────────────────
  print('\n--- Error handling ---');
  final silentConnector = JsonPlaceholderConnector();
  // throwOnError defaults to true, so 404 throws NotFoundException:
  try {
    await silentConnector.send(GetPostRequest(99999));
  } on NotFoundException catch (e) {
    print('Not found: ${e.message}');
  } on LuckyException catch (e) {
    print('HTTP ${e.statusCode}: ${e.message}');
  }

  // ── Response helpers ─────────────────────────────────────────────────────────
  print('\n--- Response helpers ---');
  final r = await silentConnector.send(GetPostRequest(1));
  print('isSuccessful: ${r.isSuccessful}');
  print('isJson: ${r.isJson}');
  print('statusCode: ${r.statusCode}');

  // Custom transformer
  final title = r.as((res) => res.json()['title'] as String);
  print('title via as(): $title');
}
