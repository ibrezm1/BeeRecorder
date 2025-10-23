// utils/gemini_service.dart
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class GeminiService {
  Future<String> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('geminiApiKey');
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Gemini API key in Settings');
    }
    return apiKey;
  }

  Future<String> _getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('geminiModel') ?? 'gemini-2.5-flash-lite';
  }

  Future<String> transcribeAudio(String audioPath) async {
    try {
      final apiKey = await _getApiKey();
      final modelName = await _getModel();
      final model = GenerativeModel(model: modelName, apiKey: apiKey);

      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();

      final prompt = TextPart(
        'Please transcribe the audio content accurately. Return only the transcription text without any additional commentary.',
      );

      final audioPart = DataPart('audio/m4a', audioBytes);

      final response = await model.generateContent([
        Content.multi([prompt, audioPart])
      ]);

      return response.text ?? 'No transcription available';
    } catch (e) {
      throw Exception('Transcription error: $e');
    }
  }

  Future<String> generateTitle(String transcription) async {
    try {
      final apiKey = await _getApiKey();
      final modelName = await _getModel();
      final model = GenerativeModel(model: modelName, apiKey: apiKey);

      final prompt = '''
Based on this transcription, generate a short, descriptive title (maximum 6 words):

$transcription

Return only the title, nothing else.
''';

      final response = await model.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? 'Untitled Recording';
    } catch (e) {
      throw Exception('Title generation error: $e');
    }
  }

  Future<String> chatWithTranscription(
      String transcription,
      String userMessage,
      List<String> previousResponses,
      ) async {
    try {
      final apiKey = await _getApiKey();
      final modelName = await _getModel();
      final model = GenerativeModel(model: modelName, apiKey: apiKey);

      String context = 'Here is a transcription of an audio recording:\n\n$transcription\n\n';

      if (previousResponses.isNotEmpty) {
        context += 'Previous conversation:\n';
        for (var response in previousResponses) {
          context += '- $response\n';
        }
        context += '\n';
      }

      context += 'User question: $userMessage\n\n';
      context += 'Please provide a helpful and accurate response based on the transcription.';

      final response = await model.generateContent([Content.text(context)]);
      return response.text ?? 'Sorry, I could not generate a response.';
    } catch (e) {
      throw Exception('Chat error: $e');
    }
  }
}
