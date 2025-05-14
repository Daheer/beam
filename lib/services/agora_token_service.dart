import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AgoraTokenService {
  static Future<String?> generateToken(String channelName) async {
    try {
      // Replace this URL with your token server URL
      final tokenServerUrl = dotenv.env['AGORA_TOKEN_SERVER_URL'];
      if (tokenServerUrl == null) {
        // For testing, use a temporary token that you generate from Agora Console
        return dotenv.env['AGORA_TEMP_TOKEN'];
      }

      final response = await http.post(
        Uri.parse(tokenServerUrl),
        body: {
          'channelName': channelName,
          'uid': '0', // Use 0 for the first user
          'role': 'publisher',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['token'];
      }

      return null;
    } catch (e) {
      print('Error generating token: $e');
      // Fallback to temporary token for testing
      return dotenv.env['AGORA_TEMP_TOKEN'];
    }
  }
}
