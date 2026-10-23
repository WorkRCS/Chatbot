import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String _configuredBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

class ChatApiException implements Exception {
  ChatApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ChatApiEvent {
  const ChatApiEvent({
    required this.type,
    this.token,
    this.conversationId,
    this.messageId,
    this.model,
    this.sources = const [],
    this.error,
  });

  final String type;
  final String? token;
  final String? conversationId;
  final String? messageId;
  final String? model;
  final List<Map<String, dynamic>> sources;
  final String? error;

  factory ChatApiEvent.fromJson(Map<String, dynamic> json) {
    return ChatApiEvent(
      type: json['type'] is String ? json['type'] as String : 'unknown',
      token: json['token'] is String ? json['token'] as String : null,
      conversationId: json['conversationId'] is String
          ? json['conversationId'] as String
          : null,
      messageId: json['messageId'] is String ? json['messageId'] as String : null,
      model: json['model'] is String ? json['model'] as String : null,
      sources: json['sources'] is List
          ? (json['sources'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : const [],
      error: json['error'] is String ? json['error'] as String : null,
    );
  }
}

class GeneratedImage {
  const GeneratedImage({
    required this.assetId,
    required this.prompt,
    required this.mimeType,
    this.dataUrl,
    this.imageUrl,
    this.conversationId,
    this.messageId,
    this.storedInR2 = false,
  });

  final String assetId;
  final String prompt;
  final String mimeType;
  final String? dataUrl;
  final String? imageUrl;
  final String? conversationId;
  final String? messageId;
  final bool storedInR2;

  Uint8List? get bytes {
    final value = dataUrl;
    if (value == null || !value.contains(',')) return null;
    try {
      return base64Decode(value.substring(value.indexOf(',') + 1));
    } catch (_) {
      return null;
    }
  }

  factory GeneratedImage.fromJson(Map<String, dynamic> json) {
    return GeneratedImage(
      assetId: json['assetId'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'image/jpeg',
      dataUrl: json['dataUrl'] as String?,
      imageUrl: json['imageUrl'] as String?,
      conversationId: json['conversationId'] as String?,
      messageId: json['messageId'] as String?,
      storedInR2: json['storedInR2'] as bool? ?? false,
    );
  }
}

class ApiConversation {
  const ApiConversation({
    required this.id,
    required this.title,
    this.preview = '',
  });

  final String id;
  final String title;
  final String preview;

  factory ApiConversation.fromJson(Map<String, dynamic> json) {
    return ApiConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Conversation',
      preview: json['preview'] as String? ?? '',
    );
  }
}

class ApiStoredMessage {
  const ApiStoredMessage({
    required this.id,
    required this.role,
    required this.content,
    this.model,
    this.feedback,
    this.sources = const [],
    this.generatedImage,
    this.attachment,
  });

  final String id;
  final String role;
  final String content;
  final String? model;
  final String? feedback;
  final List<Map<String, dynamic>> sources;
  final GeneratedImage? generatedImage;
  final Map<String, dynamic>? attachment;

  factory ApiStoredMessage.fromJson(Map<String, dynamic> json) {
    return ApiStoredMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      model: json['model'] as String?,
      feedback: json['feedback'] as String?,
      sources: json['sources'] is List
          ? (json['sources'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : const [],
      generatedImage: json['generatedImage'] is Map
          ? GeneratedImage.fromJson(Map<String, dynamic>.from(json['generatedImage'] as Map))
          : null,
      attachment: json['attachment'] is Map
          ? Map<String, dynamic>.from(json['attachment'] as Map)
          : null,
    );
  }
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Uuid _uuid = Uuid();

  static bool get isConfigured => _configuredBaseUrl.trim().isNotEmpty;

  Uri _uri(String path) {
    final base = _configuredBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(base + path);
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String> _getSessionToken() async {
    if (!isConfigured) {
      throw ChatApiException(
        'Backend URL is not configured. Build with --dart-define=API_BASE_URL=https://your-project.vercel.app',
      );
    }

    final prefs = await _prefs;
    final existingToken = prefs.getString('ai_chat_session_token');
    final expiresAt = prefs.getInt('ai_chat_session_expires_at') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (existingToken != null && expiresAt > now + 60) return existingToken;

    final refreshToken = prefs.getString('ai_chat_refresh_token');
    final response = await _client
        .post(
          _uri('/api/session'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            if (refreshToken != null && refreshToken.isNotEmpty)
              'refreshToken': refreshToken,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = _decodeJsonResponse(response);
    final token = data['token'];
    final exp = data['expiresAt'];
    final newRefreshToken = data['refreshToken'];
    final guestId = data['guestId'];
    if (token is! String || exp is! num ||
        newRefreshToken is! String || guestId is! String) {
      throw ChatApiException('Could not start a guest session.');
    }
    await prefs.setString('ai_chat_session_token', token);
    await prefs.setInt('ai_chat_session_expires_at', exp.toInt());
    await prefs.setString('ai_chat_refresh_token', newRefreshToken);
    await prefs.setString('ai_chat_guest_id', guestId);
    return token;
  }

  Future<Map<String, dynamic>> _requestJson(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final token = await _getSessionToken();
    final uri = _uri(path);
    final headers = <String, String>{
      'Authorization': 'Bearer ' + token,
      'Content-Type': 'application/json',
    };

    final response = switch (method) {
      'POST' => await _client
          .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
          .timeout(const Duration(seconds: 60)),
      _ => await _client.get(uri, headers: headers).timeout(const Duration(seconds: 25)),
    };
    return _decodeJsonResponse(response);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      data = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException(
        data['error'] as String? ??
            'Request failed (HTTP ' + response.statusCode.toString() + '). Check the backend setup.',
      );
    }
    return data;
  }

  Stream<ChatApiEvent> streamChat({
    required String prompt,
    String? conversationId,
    Uint8List? imageBytes,
    String? imageMimeType,
    required String model,
    required bool search,
    required bool thinking,
  }) async* {
    final token = await _getSessionToken();
    String? imageDataUrl;
    if (imageBytes != null) {
      if (imageBytes.length > 2 * 1024 * 1024) {
        throw ChatApiException('Please choose an image smaller than 2 MB.');
      }
      final mime = (imageMimeType == 'image/png' ||
              imageMimeType == 'image/webp' ||
              imageMimeType == 'image/jpeg')
          ? imageMimeType!
          : 'image/jpeg';
      imageDataUrl = 'data:' + mime + ';base64,' + base64Encode(imageBytes);
    }

    final request = http.Request('POST', _uri('/api/chat'))
      ..headers['Authorization'] = 'Bearer ' + token
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'prompt': prompt,
        'conversationId': conversationId,
        'imageDataUrl': imageDataUrl,
        'model': model,
        'search': search,
        'thinking': thinking,
      });

    final response = await _client.send(request).timeout(
          const Duration(seconds: 60),
        );

    if (response.statusCode != 200) {
      final errorText = await response.stream.bytesToString();
      Map<String, dynamic> body = {};
      try {
        final decoded = jsonDecode(errorText);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
      throw ChatApiException(
        body['error'] as String? ??
            'Chat request failed (HTTP ' + response.statusCode.toString() + ').',
      );
    }

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final raw = line.substring(5).trim();
      if (raw.isEmpty || raw == '[DONE]') continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          yield ChatApiEvent.fromJson(decoded);
        }
      } catch (_) {
        // Ignore an isolated malformed SSE frame and continue reading.
      }
    }
  }

  Future<GeneratedImage> generateImage(String prompt, {String? conversationId}) async {
    final data = await _requestJson(
      '/api/image',
      method: 'POST',
      body: {'prompt': prompt, 'conversationId': conversationId},
    );
    return GeneratedImage.fromJson(data);
  }

  Future<List<ApiConversation>> listConversations() async {
    final data = await _requestJson('/api/conversations');
    final raw = data['conversations'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => ApiConversation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<ApiStoredMessage>> getMessages(String conversationId) async {
    final data = await _requestJson(
      '/api/conversations?id=' + Uri.encodeQueryComponent(conversationId),
    );
    final raw = data['messages'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => ApiStoredMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> sendFeedback({
    required String messageId,
    required String? reaction,
  }) async {
    await _requestJson(
      '/api/feedback',
      method: 'POST',
      body: {'messageId': messageId, 'reaction': reaction},
    );
  }

  Future<Uint8List> downloadAsset(String assetId) async {
    final data = await _requestJson(
      '/api/assets?id=' + Uri.encodeQueryComponent(assetId),
    );
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw ChatApiException('The stored image URL is not available.');
    }
    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException('Could not download the stored image.');
    }
    return response.bodyBytes;
  }

  Future<Uint8List> downloadGeneratedImage(GeneratedImage image) async {
    final data = image.bytes;
    if (data != null) return data;

    String? url = image.imageUrl;
    if (image.storedInR2 && image.assetId.isNotEmpty && isConfigured) {
      final refreshed = await _requestJson(
        '/api/assets?id=' + Uri.encodeQueryComponent(image.assetId),
      );
      url = refreshed['url'] as String?;
    }

    if (url == null || url.isEmpty) {
      throw ChatApiException(
        'The image is not available. Configure Cloudflare R2 to keep generated images across sessions.',
      );
    }

    final response = await _client
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChatApiException('Could not download the generated image.');
    }
    return response.bodyBytes;
  }

  void dispose() => _client.close();
}
