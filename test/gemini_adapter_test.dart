import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_core/ai_core.dart';

void main() {
  group('GeminiAdapter Unit Tests', () {
    final config = AiProviderConfig(
      providerType: AiProviderType.gemini,
      apiKey: 'TEST-KEY-gemini-999',
      modelId: 'gemini-1.5-pro',
      temperature: 0.2,
      maxTokens: 2048,
    );

    test(
      'Petición exitosa 200: formatea systemInstruction, contents, role model y generationConfig',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.path,
            contains('/models/gemini-1.5-pro:generateContent'),
          );
          expect(request.url.queryParameters['key'], 'TEST-KEY-gemini-999');
          expect(request.headers['x-goog-api-key'], 'TEST-KEY-gemini-999');

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(
            body['systemInstruction']['parts'][0]['text'],
            'Eres un asistente experto en PLC Siemens S7-1200.',
          );

          final contents = body['contents'] as List;
          expect(contents.length, 2);
          expect(contents[0]['role'], 'user');
          expect(
            contents[0]['parts'][0]['text'],
            'Cómo configurar bloque PID_Compact?',
          );
          expect(contents[1]['role'], 'model');
          expect(
            contents[1]['parts'][0]['text'],
            'Usa la instrucción PID_Compact en TIA Portal.',
          );

          expect(body['generationConfig']['temperature'], 0.2);
          expect(body['generationConfig']['maxOutputTokens'], 2048);

          final responseJson = {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text':
                          'Para configurar PID_Compact, define el Input_PER como IW64 y Output_PER como QW64.',
                    },
                  ],
                  'role': 'model',
                },
                'finishReason': 'STOP',
                'index': 0,
              },
            ],
            'usageMetadata': {
              'promptTokenCount': 110,
              'candidatesTokenCount': 42,
              'totalTokenCount': 152,
            },
            'modelVersion': 'gemini-1.5-pro-001',
          };

          return http.Response(
            jsonEncode(responseJson),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final adapter = GeminiAdapter(client: mockClient);
        final response = await adapter.enviarMensaje(
          mensajes: [
            AiChatMessage(
              role: AiMessageRole.system,
              content: 'Eres un asistente experto en PLC Siemens S7-1200.',
            ),
            AiChatMessage(
              role: AiMessageRole.user,
              content: 'Cómo configurar bloque PID_Compact?',
            ),
            AiChatMessage(
              role: AiMessageRole.assistant,
              content: 'Usa la instrucción PID_Compact en TIA Portal.',
            ),
          ],
          config: config,
        );

        expect(response.content, contains('Para configurar PID_Compact'));
        expect(response.modelUsed, 'gemini-1.5-pro-001');
        expect(response.finishReason, 'STOP');
        expect(response.promptTokens, 110);
        expect(response.completionTokens, 42);
        expect(response.totalTokens, 152);
      },
    );

    test(
      'Mapeo de error 400 INVALID_ARGUMENT a AiInvalidRequestException',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 400,
                'message': 'Invalid model name specified',
                'status': 'INVALID_ARGUMENT',
              },
            }),
            400,
          );
        });

        final adapter = GeminiAdapter(client: mockClient);
        expect(
          () => adapter.enviarMensaje(
            mensajes: [
              AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
            ],
            config: config,
          ),
          throwsA(
            isA<AiInvalidRequestException>().having(
              (e) => e.statusCode,
              'statusCode',
              400,
            ),
          ),
        );
      },
    );

    test(
      'Mapeo de error 403 PERMISSION_DENIED / API_KEY_INVALID a AiAuthException',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message': 'API key not valid. Please pass a valid API key.',
                'status': 'PERMISSION_DENIED',
              },
            }),
            403,
          );
        });

        final adapter = GeminiAdapter(client: mockClient);
        expect(
          () => adapter.enviarMensaje(
            mensajes: [
              AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
            ],
            config: config,
          ),
          throwsA(
            isA<AiAuthException>().having(
              (e) => e.statusCode,
              'statusCode',
              403,
            ),
          ),
        );
      },
    );

    test(
      'Mapeo de error 429 RESOURCE_EXHAUSTED a AiRateLimitException',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 429,
                'message': 'Resource has been exhausted (e.g. check quota).',
                'status': 'RESOURCE_EXHAUSTED',
              },
            }),
            429,
          );
        });

        final adapter = GeminiAdapter(client: mockClient);
        expect(
          () => adapter.enviarMensaje(
            mensajes: [
              AiChatMessage(role: AiMessageRole.user, content: 'Hola'),
            ],
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
      },
    );

    test(
      'enviarMensajeStream emite tokens en tiempo real vía SSE alt=sse',
      () async {
        final sseBody =
            [
              'data: {"candidates":[{"content":{"parts":[{"text":"Diagnóstico PLC: "}]}}]}\n\n',
              'data: {"candidates":[{"content":{"parts":[{"text":"Verificar módulo de entradas."}]}}]}\n\n',
            ].join();

        final mockClient = MockClient((request) async {
          expect(
            request.url.path,
            contains('/models/gemini-1.5-pro:streamGenerateContent'),
          );
          expect(request.url.queryParameters['alt'], 'sse');
          expect(request.headers['Accept'], 'text/event-stream');
          return http.Response(
            sseBody,
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        });

        final adapter = GeminiAdapter(client: mockClient);
        final stream = adapter.enviarMensajeStream(
          mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'Hola')],
          config: config,
        );

        final chunks = await stream.toList();
        expect(chunks, ['Diagnóstico PLC: ', 'Verificar módulo de entradas.']);
      },
    );

    test(
      'enviarMensajeStream propaga AiAuthException si falla con 403 antes del primer chunk',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message': 'API key not valid',
                'status': 'PERMISSION_DENIED',
              },
            }),
            403,
          );
        });

        final adapter = GeminiAdapter(client: mockClient);
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
              403,
            ),
          ),
        );
      },
    );

    test('cancelarStream cierra sin error', () {
      final adapter = GeminiAdapter();
      expect(() => adapter.cancelarStream(), returnsNormally);
    });
  });
}
