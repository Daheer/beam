import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'log_service.dart';

class AgoraTokenService {
  static Future<String?> generateToken(String channelName, String uid) async {
    try {
      final appwriteEndpoint = dotenv.env['APPWRITE_ENDPOINT'];
      final functionId = dotenv.env['APPWRITE_FUNCTION_ID'];
      final projectId = dotenv.env['APPWRITE_PROJECT_ID'];
      final apiKey = dotenv.env['APPWRITE_API_KEY'];

      if (appwriteEndpoint == null ||
          functionId == null ||
          projectId == null ||
          apiKey == null) {
        throw Exception('Missing Appwrite configuration');
      }

      final response = await http.post(
        Uri.parse(appwriteEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-Appwrite-Project': projectId,
          'X-Appwrite-Key': apiKey,
        },
        body: jsonEncode({
          'channelName': channelName,
          'uid': uid,
          'expireTime': 3600,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        return token;
      }

      // Fallback to temporary token for testing
      return dotenv.env['AGORA_TOKEN'];
    } catch (e) {
      LogService.e('Error generating token', e, StackTrace.current);
      // Fallback to temporary token for testing
      return dotenv.env['AGORA_TOKEN'];
    }
  }
}
