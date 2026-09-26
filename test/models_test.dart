import 'package:test/test.dart';
import 'package:ai_core/ai_core.dart';

void main() {
  group('AiProviderType Tests', () {
    test('Verificar propiedades y valores por defecto de todos los proveedores', () {
      expect(AiProviderType.values.length, 5);

      expect(AiProviderType.nvidiaNim.displayName, 'NVIDIA NIM');
      expect(AiProviderType.nvidiaNim.defaultBaseUrl, contains('api.nvidia.com'));
      expect(AiProviderType.nvidiaNim.defaultModel, isNotEmpty);

      expect(AiProviderType.anthropic.displayName, 'Anthropic Claude');
      expect(AiProviderType.anthropic.defaultBaseUrl, contains('api.anthropic.com'));
      expect(AiProviderType.anthropic.defaultModel, contains('claude'));

      expect(AiProviderType.gemini.displayName, 'Google Gemini');
      expect(AiProviderType.gemini.defaultBaseUrl, contains('generativelanguage.googleapis.com'));
      expect(AiProviderType.gemini.defaultModel, contains('gemini'));

      expect(AiProviderType.openAi.displayName, 'OpenAI');
      expect(AiProviderType.openAi.defaultBaseUrl, contains('api.openai.com'));
      expect(AiProviderType.openAi.defaultModel, contains('gpt'));

      expect(AiProviderType.openRouter.displayName, 'OpenRouter');
      expect(AiProviderType.openRouter.defaultBaseUrl, contains('openrouter.ai'));
      expect(AiProviderType.openRouter.defaultModel, isNotEmpty);
    });

    test('fromString deserializa correctamente y maneja errores', () {
      expect(AiProviderType.fromString('nvidiaNim'), AiProviderType.nvidiaNim);
      expect(AiProviderType.fromString('anthropic'), AiProviderType.anthropic);
      expect(AiProviderType.fromString('gemini'), AiProviderType.gemini);
      expect(AiProviderType.fromString('openAi'), AiProviderType.openAi);
      expect(AiProviderType.fromString('openRouter'), AiProviderType.openRouter);

      expect(() => AiProviderType.fromString('desconocido'), throwsArgumentError);
    });
  });

  group('AiChatMessage Tests', () {
    test('Serialización y deserialización JSON con timestamp y metadata', () {
      final now = DateTime(2026, 8, 16, 12, 0, 0);
      final msg = AiChatMessage(
        role: AiMessageRole.user,
        content: 'Falla sobrecorriente en VFD GS3',
        timestamp: now,
        metadata: {'categoria': 'Variador VFD', 'codigo': 'OC'},
      );

      final json = msg.toJson();
      expect(json['role'], 'user');
      expect(json['content'], 'Falla sobrecorriente en VFD GS3');
      expect(json['timestamp'], now.toIso8601String());
      expect(json['metadata']['codigo'], 'OC');

      final deserialized = AiChatMessage.fromJson(json);
      expect(deserialized.role, AiMessageRole.user);
      expect(deserialized.content, msg.content);
      expect(deserialized.metadata?['categoria'], 'Variador VFD');
    });

    test('AiMessageRole.fromString y copyWith', () {
      expect(AiMessageRole.fromString('system'), AiMessageRole.system);
      expect(AiMessageRole.fromString('user'), AiMessageRole.user);
      expect(AiMessageRole.fromString('assistant'), AiMessageRole.assistant);
      expect(AiMessageRole.fromString('model'), AiMessageRole.assistant);
      expect(() => AiMessageRole.fromString('otro'), throwsArgumentError);

      final msg = AiChatMessage(role: AiMessageRole.user, content: 'Hola');
      final updated = msg.copyWith(content: 'Nuevo texto', role: AiMessageRole.assistant);
      expect(updated.content, 'Nuevo texto');
      expect(updated.role, AiMessageRole.assistant);
    });
  });

  group('AiProviderConfig Tests', () {
    test('Validación de API Key obligatoria y rango de temperatura', () {
      expect(
        () => AiProviderConfig(providerType: AiProviderType.openAi, apiKey: ''),
        throwsArgumentError,
      );
      expect(
        () => AiProviderConfig(providerType: AiProviderType.openAi, apiKey: '   '),
        throwsArgumentError,
      );
      expect(
        () => AiProviderConfig(
          providerType: AiProviderType.openAi,
          apiKey: 'key',
          temperature: -0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => AiProviderConfig(
          providerType: AiProviderType.openAi,
          apiKey: 'key',
          temperature: 2.5,
        ),
        throwsArgumentError,
      );
    });

    test('Resolución de effectiveBaseUrl y effectiveModelId por defecto', () {
      final config = AiProviderConfig(
        providerType: AiProviderType.anthropic,
        apiKey: 'sk-ant-test-123',
      );

      expect(config.effectiveBaseUrl, 'https://api.anthropic.com/v1');
      expect(config.effectiveModelId, 'claude-3-5-sonnet-20241022');
      expect(config.timeout, const Duration(seconds: 30));
      expect(config.temperature, 0.2);
    });

    test('Serialización y deserialización JSON de AiProviderConfig', () {
      final config = AiProviderConfig(
        providerType: AiProviderType.gemini,
        apiKey: 'gemini-key',
        baseUrl: 'https://custom.gemini.endpoint',
        modelId: 'gemini-1.5-flash',
        timeout: const Duration(seconds: 45),
        temperature: 0.5,
        maxTokens: 2048,
        extraHeaders: {'X-Custom': 'Value'},
      );

      final json = config.toJson();
      final fromJson = AiProviderConfig.fromJson(json);

      expect(fromJson.providerType, AiProviderType.gemini);
      expect(fromJson.apiKey, 'gemini-key');
      expect(fromJson.effectiveBaseUrl, 'https://custom.gemini.endpoint');
      expect(fromJson.effectiveModelId, 'gemini-1.5-flash');
      expect(fromJson.timeout, const Duration(seconds: 45));
      expect(fromJson.temperature, 0.5);
      expect(fromJson.maxTokens, 2048);
      expect(fromJson.extraHeaders['X-Custom'], 'Value');
    });
  });

  group('AiChatResponse Tests', () {
    test('Serialización, deserialización y copyWith de AiChatResponse', () {
      final response = AiChatResponse(
        content: 'Diagnóstico: Revisar rampa de aceleración en Pr.01.',
        modelUsed: 'gpt-4o',
        finishReason: 'stop',
        promptTokens: 120,
        completionTokens: 45,
        totalTokens: 165,
        latency: const Duration(milliseconds: 650),
        rawResponse: {'id': 'chatcmpl-123'},
      );

      final json = response.toJson();
      expect(json['content'], contains('Revisar rampa'));
      expect(json['model_used'], 'gpt-4o');
      expect(json['latency_ms'], 650);

      final deserialized = AiChatResponse.fromJson(json);
      expect(deserialized.content, response.content);
      expect(deserialized.modelUsed, response.modelUsed);
      expect(deserialized.totalTokens, 165);
      expect(deserialized.latency, const Duration(milliseconds: 650));
      expect(deserialized.rawResponse?['id'], 'chatcmpl-123');
    });
  });

  group('AiServiceException Hierarchy Tests', () {
    test('Tipificación y formato de excepciones', () {
      const authEx = AiAuthException(
        message: 'Invalid Key',
        provider: AiProviderType.anthropic,
      );
      expect(authEx.statusCode, 401);
      expect(authEx.provider, AiProviderType.anthropic);
      expect(authEx.toString(), contains('Anthropic Claude'));

      const rateEx = AiRateLimitException(
        message: 'Quota exceeded',
        provider: AiProviderType.openAi,
      );
      expect(rateEx.statusCode, 429);

      const invalidEx = AiInvalidRequestException(
        message: 'Invalid model',
        provider: AiProviderType.gemini,
      );
      expect(invalidEx.statusCode, 400);

      const serverEx = AiServerException(
        message: 'Internal error',
        provider: AiProviderType.nvidiaNim,
        statusCode: 503,
      );
      expect(serverEx.statusCode, 503);

      const timeoutEx = AiTimeoutException(
        message: 'Timed out',
        provider: AiProviderType.openRouter,
      );
      expect(timeoutEx.statusCode, isNull);

      const netEx = AiNetworkException(
        message: 'Socket error',
        provider: AiProviderType.nvidiaNim,
      );
      expect(netEx.statusCode, isNull);
    });
  });
}
