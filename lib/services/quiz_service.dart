import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/log_service.dart';

class QuizQuestion {
  final String question;
  final List<String> options;
  final String answer;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.answer,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'],
      options: List<String>.from(json['options']),
      answer: json['answer'],
    );
  }
}

class QuizService {
  static Future<List<QuizQuestion>> fetchQuestions(
    String profession,
    int experience,
  ) async {
    try {
      final appwriteEndpoint = dotenv.env['APPWRITE_QUIZ_ENDPOINT'];
      final functionId = dotenv.env['APPWRITE_QUIZ_FUNCTION_ID'];
      final projectId = dotenv.env['APPWRITE_PROJECT_ID'];
      final apiKey = dotenv.env['APPWRITE_API_KEY'];

      if (appwriteEndpoint == null || projectId == null || apiKey == null) {
        throw Exception('Missing Appwrite configuration');
      }

      final response = await http.post(
        Uri.parse(appwriteEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-Appwrite-Project': projectId,
          'X-Appwrite-Key': apiKey,
        },
        body: jsonEncode({'profession': profession, 'experience': experience}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data != null && data.containsKey("questions")) {
          final List<dynamic> questionsJson = data["questions"];
          return questionsJson
              .map((json) => QuizQuestion.fromJson(json))
              .toList();
        }
      }

      throw Exception(
        'Failed to load questions: ${response.statusCode} ${response.body}',
      );
    } catch (e) {
      LogService.e('Error fetching quiz questions', e, StackTrace.current);
      return [];
    }
  }
}
