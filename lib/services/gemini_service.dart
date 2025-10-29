import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static GenerativeModel? _model;

  // Initialize the model
  static void initialize() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print('❌ GEMINI_API_KEY not found in .env file!');
      return;
    }

    print('✅ Gemini API Key loaded: ${apiKey.substring(0, 10)}...');

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
  }

  static Future<String> getPrediction({
    required String subject,
    required num currentGrade,
    required List<Map<String, dynamic>> pastGrades,
  }) async {
    // Check if model is initialized
    if (_model == null) {
      print('⚠️ Gemini not initialized, trying to initialize now...');
      initialize();

      if (_model == null) {
        print('❌ Failed to initialize Gemini - API key missing');
        return '—';
      }
    }

    final gradesStr = pastGrades.map((g) => "${g['label']}: ${g['percent']}%").join(', ');
    final prompt = '''
Predict the student's likelihood of passing based on:
Subject: $subject
Current Grade: $currentGrade%
Past Grades: $gradesStr

Return ONLY one of these exact labels: High, Moderate, Borderline, or Low.
No explanation, just the label.
''';

    try {
      print('🤖 Calling Gemini API for: $subject (Grade: $currentGrade%)');

      final res = await _model!.generateContent([Content.text(prompt)]);
      final prediction = res.text?.trim() ?? '—';

      print('✅ Gemini response: $prediction');

      // Ensure the response is one of the expected values
      final normalized = prediction.toLowerCase();
      if (normalized.contains('high')) return 'High';
      if (normalized.contains('moderate')) return 'Moderate';
      if (normalized.contains('borderline')) return 'Borderline';
      if (normalized.contains('low')) return 'Low';

      return prediction;
    } catch (e) {
      print('❌ Gemini error: $e');
      print('❌ Error type: ${e.runtimeType}');
      return '—';
    }
  }
}