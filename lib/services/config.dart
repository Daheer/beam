import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // Bytescale configuration
  static String get bytescaleApiKey =>
      dotenv.env['BYTESCALE_API_KEY'] ?? 'demopublickey';

  static String get bytescaleAccountId =>
      dotenv.env['BYTESCALE_ACCOUNT_ID'] ?? '';

  // Agora configuration
  static String get agoraAppId {
    final appId = dotenv.env['AGORA_APP_ID'];
    if (appId == null || appId.isEmpty) {
      throw Exception('AGORA_APP_ID not found in environment variables');
    }
    return appId;
  }

  static String get agoraToken {
    final token = dotenv.env['AGORA_TOKEN'];
    if (token == null || token.isEmpty) {
      throw Exception('AGORA_TOKEN not found in environment variables');
    }
    return token;
  }

  // Firebase configuration (no need to change, already in firebase_options.dart)

  // Other app configuration
  static const int maxUploadSizeInMb = 10;
}
