import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_core/ai_core.dart';

void main() {
  group('NvidiaNimAdapter Unit Tests', () {
    final config = AiProviderConfig(
      providerType: AiProviderType.nvidiaNim,
      apiKey: 'TEST-KEY-nim-12345',
      modelId: 'meta/llama-3.1-70b-instruct',
      temperature: 0.2,
      maxTokens: 512,
    );

    test(
      'Petición exitosa 200 con payload, headers y respuesta normalizada',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://integrate.api.nvidia.com/v1/chat/completions',
          );
          expect(request.headers['Authorization'], 'Bearer TEST-KEY-nim-12345');
          expect(request.headers['Content-Type'], contains('application/json'));
          expect(request.headers['Accept'], 'application/json');

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'meta/llama-3.1-70b-instruct');
          expect(body['temperature'], 0.2);
          expect(body['max_tokens'], 512);

          final messages = body['messages'] as List;
          expect(messages.length, 2);
          expect(messages[0]['role'], 'system');
          expect(messages[1]['role'], 'user');
          expect(messages[1]['content'], 'Falla OC en variador');

          final responseJson = {
            'id': 'chatcmpl-nv-123',
            'model': 'meta/llama-3.1-70b-instruct',
            'choices': [
              {
                'index': 0,
                'message': {
                  'role': 'assistant',
                  'content':
                      'Diagnóstico: Sobrecorriente en etapa de potencia IGBT.',
                },
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 45,
              'completion_tokens': 18,
              'total_tokens': 63,
            },
          };

          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final adapter = NvidiaNimAdapter(client: mockClient);
        final response = await adapter.enviarMensaje(
          mensajes: [
            AiChatMessage(
              role: AiMessageRole.system,
              content: 'Eres un experto en automatización.',
            ),
            AiChatMessage(
              role: AiMessageRole.user,
              content: 'Falla OC en variador',
            ),
          ],
          config: config,
        );

        expect(
          response.content,
          contains('Sobrecorriente en etapa de potencia IGBT'),
        );
        expect(response.modelUsed, 'meta/llama-3.1-70b-instruct');
        expect(response.finishReason, 'stop');
        expect(response.promptTokens, 45);
        expect(response.completionTokens, 18);
        expect(response.totalTokens, 63);
        expect(response.latency.inMilliseconds, greaterThanOrEqualTo(0));
      },
    );

    test('Mapeo de error 401 a AiAuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Invalid API Key',
              'type': 'invalid_request_error',
            },
          }),
          401,
        );
      });

      final adapter = NvidiaNimAdapter(client: mockClient);
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
            'error': {'message': 'Rate limit exceeded'},
          }),
          429,
        );
      });

      final adapter = NvidiaNimAdapter(client: mockClient);
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

    test('Mapeo de error 500 a AiServerException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final adapter = NvidiaNimAdapter(client: mockClient);
      expect(
        () => adapter.enviarMensaje(
          mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'Hola')],
          config: config,
        ),
        throwsA(
          isA<AiServerException>().having(
            (e) => e.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
    });

    test(
      'validarConexion retorna true si el endpoint responde correctamente',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'pong'},
                },
              ],
            }),
            200,
          );
        });

        final adapter = NvidiaNimAdapter(client: mockClient);
        final ok = await adapter.validarConexion(config: config);
        expect(ok, isTrue);
      },
    );

    test(
      'enviarMensajeStream emite tokens ordenados y finaliza ante [DONE]',
      () async {
        final sseBody =
            [
              'data: {"choices":[{"delta":{"content":"Falla OC: "}}]}\n\n',
              'data: {"choices":[{"delta":{"content":"revisar bobinado del motor "}}]}\n\n',
              'data: {"choices":[{"delta":{"content":"y cable apantallado."}}]}\n\n',
              'data: [DONE]\n\n',
            ].join();

        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://integrate.api.nvidia.com/v1/chat/completions',
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

        final adapter = NvidiaNimAdapter(client: mockClient);
        final chunks =
            await adapter
                .enviarMensajeStream(
                  mensajes: [
                    AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
                  ],
                  config: config,
                )
                .toList();

        expect(chunks, [
          'Falla OC: ',
          'revisar bobinado del motor ',
          'y cable apantallado.',
        ]);
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

        final adapter = NvidiaNimAdapter(client: mockClient);
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
      final adapter = NvidiaNimAdapter();
      expect(() => adapter.cancelarStream(), returnsNormally);
    });
  });
}
