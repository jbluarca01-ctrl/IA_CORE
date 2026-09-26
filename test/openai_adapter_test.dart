import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_core/ai_core.dart';

void main() {
  group('OpenAiAdapter Unit Tests', () {
    final config = AiProviderConfig(
      providerType: AiProviderType.openAi,
      apiKey: 'sk-proj-openai-test-key-555',
      modelId: 'gpt-4o',
      temperature: 0.2,
      maxTokens: 500,
    );

    test(
      'Petición exitosa 200: payload estándar, headers y respuesta normalizada',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.openai.com/v1/chat/completions',
          );
          expect(
            request.headers['Authorization'],
            'Bearer sk-proj-openai-test-key-555',
          );
          expect(request.headers['Content-Type'], contains('application/json'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'gpt-4o');
          expect(body['temperature'], 0.2);
          expect(body['max_tokens'], 500);

          final messages = body['messages'] as List;
          expect(messages.length, 2);
          expect(messages[0]['role'], 'system');
          expect(messages[1]['role'], 'user');
          expect(messages[1]['content'], 'Consulta sobre protocolo Modbus TCP');

          final responseJson = {
            'id': 'chatcmpl-987abc',
            'object': 'chat.completion',
            'model': 'gpt-4o-2024-08-06',
            'choices': [
              {
                'index': 0,
                'message': {
                  'role': 'assistant',
                  'content':
                      'Modbus TCP utiliza el puerto 502 por defecto y encapsula la PDU en una trama MBAP.',
                },
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 30,
              'completion_tokens': 20,
              'total_tokens': 50,
            },
          };

          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final adapter = OpenAiAdapter(client: mockClient);
        final response = await adapter.enviarMensaje(
          mensajes: [
            AiChatMessage(
              role: AiMessageRole.system,
              content: 'Experto en redes industriales.',
            ),
            AiChatMessage(
              role: AiMessageRole.user,
              content: 'Consulta sobre protocolo Modbus TCP',
            ),
          ],
          config: config,
        );

        expect(response.content, contains('Modbus TCP utiliza el puerto 502'));
        expect(response.modelUsed, 'gpt-4o-2024-08-06');
        expect(response.finishReason, 'stop');
        expect(response.promptTokens, 30);
        expect(response.completionTokens, 20);
        expect(response.totalTokens, 50);
      },
    );

    test('Mapeo de error 401 a AiAuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Incorrect API key provided',
              'type': 'invalid_request_error',
            },
          }),
          401,
        );
      });

      final adapter = OpenAiAdapter(client: mockClient);
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
            'error': {
              'message':
                  'You exceeded your current quota, please check your plan and billing details.',
            },
          }),
          429,
        );
      });

      final adapter = OpenAiAdapter(client: mockClient);
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
              'data: {"choices":[{"delta":{"content":"Modbus "}}]}\n\n',
              'data: {"choices":[{"delta":{"content":"TCP "}}]}\n\n',
              'data: {"choices":[{"delta":{"content":"en puerto 502"}}]}\n\n',
              'data: [DONE]\n\n',
            ].join();

        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.openai.com/v1/chat/completions',
          );
          expect(request.headers['Accept'], 'text/event-stream');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['stream'], isTrue);
          return http.Response(
            sseBody,
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        });

        final adapter = OpenAiAdapter(client: mockClient);
        final chunks =
            await adapter
                .enviarMensajeStream(
                  mensajes: [
                    AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
                  ],
                  config: config,
                )
                .toList();

        expect(chunks, ['Modbus ', 'TCP ', 'en puerto 502']);
      },
    );

    test(
      'enviarMensajeStream lanza AiAuthException si status es 401 antes del primer chunk',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Invalid API Key'},
            }),
            401,
          );
        });

        final adapter = OpenAiAdapter(client: mockClient);
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
      final adapter = OpenAiAdapter();
      expect(() => adapter.cancelarStream(), returnsNormally);
    });
  });

  group('parseOpenAiCompatibleSse Tests', () {
    test(
      'Parsea chunks válidos, ignora líneas vacías y se detiene en [DONE]',
      () async {
        final lines = Stream.fromIterable([
          '',
          'data: {"choices":[{"delta":{"content":"Chunk 1"}}]}',
          '   ',
          'data: {"choices":[{"delta":{"content":" Chunk 2"}}]}',
          'data: [DONE]',
          'data: {"choices":[{"delta":{"content":"Chunk 3 nunca emitido"}}]}',
        ]);

        final result = await parseOpenAiCompatibleSse(lines).toList();
        expect(result, ['Chunk 1', ' Chunk 2']);
      },
    );

    test(
      'Ignora chunks corruptos o con JSON inválido sin interrumpir el stream',
      () async {
        final lines = Stream.fromIterable([
          'data: {"choices":[{"delta":{"content":"Token A"}}]}',
          'data: {JSON INCOMPLETO O INVALIDO',
          'data: {"sin_choices": true}',
          'data: {"choices":[]}',
          'data: {"choices":[{"delta":{}}]}',
          'data: {"choices":[{"delta":{"content":"Token B"}}]}',
          'data: [DONE]',
        ]);

        final result = await parseOpenAiCompatibleSse(lines).toList();
        expect(result, ['Token A', 'Token B']);
      },
    );
  });
}
