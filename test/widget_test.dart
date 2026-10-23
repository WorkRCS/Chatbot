import 'package:ai_chat_frontend/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API integration stays opt-in until a backend URL is supplied', () {
    expect(ApiService.isConfigured, isFalse);
  });
}
