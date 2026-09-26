import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_core/ai_core.dart';

void main() {
  group('AiProviderFactory Unit Tests', () {
    test('Resolución correcta de cada adaptador según el enum AiProviderType', () {
      final customClient = http.Client();
      final factory = AiProviderFactory(client: customClient);

      final nvidiaService = factory.getService(AiProviderType.nvidiaNim);
      expect(nvidiaService, isA<NvidiaNimAdapter>());
      expect(nvidiaService.providerType, AiProviderType.nvidiaNim);

      final anthropicService = factory.getService(AiProviderType.anthropic);
      expect(anthropicService, isA<AnthropicAdapter>());
      expect(anthropicService.providerType, AiProviderType.anthropic);

      final geminiService = factory.getService(AiProviderType.gemini);
      expect(geminiService, isA<GeminiAdapter>());
      expect(geminiService.providerType, AiProviderType.gemini);

      final openAiService = factory.getService(AiProviderType.openAi);
      expect(openAiService, isA<OpenAiAdapter>());
      expect(openAiService.providerType, AiProviderType.openAi);

      final openRouterService = factory.getService(AiProviderType.openRouter);
      expect(openRouterService, isA<OpenRouterAdapter>());
      expect(openRouterService.providerType, AiProviderType.openRouter);
    });
  });
}
