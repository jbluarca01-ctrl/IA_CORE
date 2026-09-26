import 'dart:convert';

import '../ai_log.dart';

/// Parsea un stream de líneas Server-Sent Events (SSE) compatible con la
/// especificación de OpenAI / OpenRouter / NVIDIA NIM.
///
/// Cada chunk relevante tiene la forma:
/// `data: {"choices":[{"delta":{"content":"..."}}]}`
/// El flujo finaliza ante el centinela `data: [DONE]`.
Stream<String> parseOpenAiCompatibleSse(Stream<String> lines) async* {
  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    if (trimmed.startsWith('data:')) {
      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') {
        break;
      }
      if (data.isEmpty) continue;

      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          final choices = decoded['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final first = choices[0] as Map<String, dynamic>?;
            final delta = first?['delta'] as Map<String, dynamic>?;
            final content = delta?['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              yield content;
            }
          }
        }
      } catch (e) {
        AiLog.warning(
          'parseOpenAiCompatibleSse: chunk no parseable, ignorado',
          details: e.toString(),
        );
      }
    }
  }
}
