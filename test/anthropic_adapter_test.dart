import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_core/ai_core.dart';

void main() {
  group('AnthropicAdapter Unit Tests', () {
    final config = AiProviderConfig(
      providerType: AiProviderType.anthropic,
      apiKey: 'sk-ant-api03-testkey',
      modelId: 'claude-3-5-sonnet-20241022',
      temperature: 0.2,
      maxTokens: 1024,
    );

    test(
      'Petición exitosa 200: extrae system prompt, valida headers y formatea messages',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.anthropic.com/v1/messages',
          );
          expect(request.headers['x-api-key'], 'sk-ant-api03-testkey');
          expect(request.headers['anthropic-version'], '2023-06-01');
          expect(request.headers['content-type'], contains('application/json'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'claude-3-5-sonnet-20241022');
          expect(
            body['system'],
            'Instrucciones estrictas de diagnóstico industrial.',
          );
          expect(body['max_tokens'], 1024);
          expect(body['temperature'], 0.2);

          // El arreglo messages NO debe contener mensajes con rol 'system'
          final messages = body['messages'] as List;
          expect(messages.length, 1);
          expect(messages[0]['role'], 'user');
          expect(messages[0]['content'], 'Falla en servo driver Delta ASDA-A2');

          final responseJson = {
            'id': 'msg_01XFDUDr9pJJq2',
            'type': 'message',
            'role': 'assistant',
            'model': 'claude-3-5-sonnet-20241022',
            'content': [
              {
                'type': 'text',
                'text':
                    'Diagnóstico Delta: AL001 indica cortocircuito o sobrecorriente.',
              },
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 62, 'output_tokens': 24},
          };

          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final adapter = AnthropicAdapter(client: mockClient);
        final response = await adapter.enviarMensaje(
          mensajes: [
            AiChatMessage(
              role: AiMessageRole.system,
              content: 'Instrucciones estrictas de diagnóstico industrial.',
            ),
            AiChatMessage(
              role: AiMessageRole.user,
              content: 'Falla en servo driver Delta ASDA-A2',
            ),
          ],
          config: config,
        );

        expect(response.content, contains('AL001 indica cortocircuito'));
        expect(response.modelUsed, 'claude-3-5-sonnet-20241022');
        expect(response.finishReason, 'end_turn');
        expect(response.promptTokens, 62);
        expect(response.completionTokens, 24);
        expect(response.totalTokens, 86);
      },
    );

    test('Mapeo de error 401 a AiAuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'type': 'error',
            'error': {
              'type': 'authentication_error',
              'message': 'invalid x-api-key',
            },
          }),
          401,
        );
      });

      final adapter = AnthropicAdapter(client: mockClient);
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
            'type': 'error',
            'error': {
              'type': 'rate_limit_error',
              'message': 'Rate limit exceeded',
            },
          }),
          429,
        );
      });

      final adapter = AnthropicAdapter(client: mockClient);
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
      'Mapeo de error 529 a AiServerException (servidor sobrecargado)',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'type': 'error',
              'error': {
                'type': 'overloaded_error',
                'message': 'Anthropic is temporarily overloaded',
              },
            }),
            529,
          );
        });

        final adapter = AnthropicAdapter(client: mockClient);
        expect(
          () => adapter.enviarMensaje(
            mensajes: [
              AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
            ],
            config: config,
          ),
          throwsA(
            isA<AiServerException>().having(
              (e) => e.statusCode,
              'statusCode',
              529,
            ),
          ),
        );
      },
    );

    test(
      'enviarMensajeStream procesa content_block_delta e ignora otros eventos',
      () async {
        final sseBody =
            [
              'event: message_start\n',
              'data: {"type":"message_start","message":{"id":"msg_1"}}\n\n',
              'event: content_block_start\n',
              'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n',
              'event: ping\n',
              'data: {"type":"ping"}\n\n',
              'event: content_block_delta\n',
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Alarma AL001: "}}\n\n',
              'event: content_block_delta\n',
              'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"sobrecorriente en etapa IGBT."}}\n\n',
              'event: message_stop\n',
              'data: {"type":"message_stop"}\n\n',
            ].join();

        final mockClient = MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.anthropic.com/v1/messages',
          );
          expect(request.headers['accept'], 'text/event-stream');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['stream'], isTrue);
          return http.Response(
            sseBody,
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        });

        final adapter = AnthropicAdapter(client: mockClient);
        final chunks =
            await adapter
                .enviarMensajeStream(
                  mensajes: [
                    AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
                  ],
                  config: config,
                )
                .toList();

        expect(chunks, ['Alarma AL001: ', 'sobrecorriente en etapa IGBT.']);
      },
    );

    test(
      'enviarMensajeStream lanza AiAuthException si status es 401 antes del primer chunk',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'type': 'error',
              'error': {
                'type': 'authentication_error',
                'message': 'invalid x-api-key',
              },
            }),
            401,
          );
        });

        final adapter = AnthropicAdapter(client: mockClient);
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
      final adapter = AnthropicAdapter();
      expect(() => adapter.cancelarStream(), returnsNormally);
    });
  });
}
