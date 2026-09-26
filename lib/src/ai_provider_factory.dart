import 'package:http/http.dart' as http;

import 'adapters/anthropic_adapter.dart';
import 'adapters/gemini_adapter.dart';
import 'adapters/nvidia_nim_adapter.dart';
import 'adapters/openai_adapter.dart';
import 'adapters/openrouter_adapter.dart';
import 'chat_completion_service.dart';
import 'models/ai_provider_type.dart';

/// Fábrica y despachador de servicios de IA según el proveedor seleccionado.
class AiProviderFactory {
  final http.Client _client;

  AiProviderFactory({http.Client? client}) : _client = client ?? http.Client();

  /// Obtiene la instancia correspondiente del adaptador para el proveedor solicitado.
  ChatCompletionService getService(AiProviderType type) {
    switch (type) {
      case AiProviderType.nvidiaNim:
        return NvidiaNimAdapter(client: _client);
      case AiProviderType.anthropic:
        return AnthropicAdapter(client: _client);
      case AiProviderType.gemini:
        return GeminiAdapter(client: _client);
      case AiProviderType.openAi:
        return OpenAiAdapter(client: _client);
      case AiProviderType.openRouter:
        return OpenRouterAdapter(client: _client);
    }
  }
}
