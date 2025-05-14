import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // Bytescale configuration
  static String get bytescaleApiKey =>
      dotenv.env['BYTESCALE_API_KEY'] ?? 'demopublickey';

  static String get bytescaleAccountId =>
      dotenv.env['BYTESCALE_ACCOUNT_ID'] ?? '';

  // Firebase configuration (no need to change, already in firebase_options.dart)

  // Other app configuration
  static const int maxUploadSizeInMb = 10;
}
