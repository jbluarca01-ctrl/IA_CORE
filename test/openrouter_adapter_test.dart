import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_core/ai_core.dart';

void main() {
  group('OpenRouterAdapter Unit Tests', () {
    final config = AiProviderConfig(
      providerType: AiProviderType.openRouter,
      apiKey: 'sk-or-v1-testkey-888',
      modelId: 'anthropic/claude-3.5-sonnet',
      temperature: 0.2,
      maxTokens: 1024,
    );

    test(
      'Petición exitosa 200: valida cabeceras obligatorias HTTP-Referer y X-Title',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://openrouter.ai/api/v1/chat/completions',
          );
          expect(
            request.headers['Authorization'],
            'Bearer sk-or-v1-testkey-888',
          );
          expect(request.headers['HTTP-Referer'], 'https://praxia.industrial');
          expect(request.headers['X-Title'], 'PRAXIA Industrial');
          expect(request.headers['Content-Type'], contains('application/json'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'anthropic/claude-3.5-sonnet');
          expect(body['temperature'], 0.2);
          expect(body['max_tokens'], 1024);

          final responseJson = {
            'id': 'gen-123456',
            'model': 'anthropic/claude-3.5-sonnet',
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'Diagnóstico multi-modelo OpenRouter exitoso.',
                },
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 20,
              'completion_tokens': 10,
              'total_tokens': 30,
            },
          };

          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final adapter = OpenRouterAdapter(client: mockClient);
        final response = await adapter.enviarMensaje(
          mensajes: [
            AiChatMessage(
              role: AiMessageRole.user,
              content: 'Test de conectividad OpenRouter',
            ),
          ],
          config: config,
        );

        expect(
          response.content,
          contains('Diagnóstico multi-modelo OpenRouter exitoso'),
        );
        expect(response.modelUsed, 'anthropic/claude-3.5-sonnet');
        expect(response.finishReason, 'stop');
        expect(response.promptTokens, 20);
        expect(response.completionTokens, 10);
        expect(response.totalTokens, 30);
      },
    );

    test('Mapeo de error 401 a AiAuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Unauthorized: Invalid API Key'},
          }),
          401,
        );
      });

      final adapter = OpenRouterAdapter(client: mockClient);
      expect(
        () => adapter.enviarMensaje(
          mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'Hola')],
          config: config,
        ),
        throwsA(
          isA<AiAuthException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('Mapeo de error 429 a AiRateLimitException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Credits exhausted or rate limit hit'},
          }),
          429,
        );
      });

      final adapter = OpenRouterAdapter(client: mockClient);
      expect(
        () => adapter.enviarMensaje(
          mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'Hola')],
          config: config,
        ),
        throwsA(
          isA<AiRateLimitException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
      );
    });

    test(
      'enviarMensajeStream emite tokens ordenados y finaliza ante [DONE]',
      () async {
        final sseBody =
            [
              'data: {"choices":[{"delta":{"content":"Diagnóstico "}}]}\n\n',
              'data: {"choices":[{"delta":{"content":"OpenRouter "}}]}\n\n',
              'data: {"choices":[{"delta":{"content":"en streaming."}}]}\n\n',
              'data: [DONE]\n\n',
            ].join();

        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://openrouter.ai/api/v1/chat/completions',
          );
          expect(request.headers['Accept'], 'text/event-stream');
          expect(request.headers['HTTP-Referer'], 'https://praxia.industrial');
          expect(request.headers['X-Title'], 'PRAXIA Industrial');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['stream'], isTrue);
          return http.Response(
            sseBody,
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        });

        final adapter = OpenRouterAdapter(client: mockClient);
        final chunks =
            await adapter
                .enviarMensajeStream(
                  mensajes: [
                    AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
                  ],
                  config: config,
                )
                .toList();

        expect(chunks, ['Diagnóstico ', 'OpenRouter ', 'en streaming.']);
      },
    );

    test(
      'enviarMensajeStream lanza AiAuthException si status es 401 antes del primer chunk',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Unauthorized'},
            }),
            401,
          );
        });

        final adapter = OpenRouterAdapter(client: mockClient);
        expect(
          () =>
              adapter
                  .enviarMensajeStream(
                    mensajes: [
                      AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
                    ],
                    config: config,
                  )
                  .toList(),
          throwsA(
            isA<AiAuthException>().having(
              (e) => e.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
      },
    );

    test('cancelarStream no lanza excepción si no hay stream activo', () {
      final adapter = OpenRouterAdapter();
      expect(() => adapter.cancelarStream(), returnsNormally);
    });
  });
}
