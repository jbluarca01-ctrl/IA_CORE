import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../ai_log.dart';
import '../chat_completion_service.dart';
import '../exceptions/ai_service_exception.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_chat_response.dart';
import '../models/ai_provider_config.dart';
import '../models/ai_provider_type.dart';
import '../models/modelo_ia.dart';

/// Adaptador para Google Gemini (Google Generative Language REST API - generateContent).
class GeminiAdapter implements ChatCompletionService {
  final http.Client _client;
  final bool _isCustomClient;
  http.Client? _activeStreamClient;

  GeminiAdapter({http.Client? client})
    : _client = client ?? http.Client(),
      _isCustomClient = client != null;

  @override
  AiProviderType get providerType => AiProviderType.gemini;

  @override
  Future<List<ModeloDisponible>> listarModelos({
    required String apiKey,
    String? baseUrl,
  }) async {
    final base =
        (baseUrl != null && baseUrl.trim().isNotEmpty)
            ? baseUrl.trim().replaceAll(RegExp(r'/+$'), '')
            : providerType.defaultBaseUrl;
    final response = await _client
        .get(Uri.parse('$base/models'), headers: {'x-goog-api-key': apiKey})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw AiServerException(
        message:
            'No se pudo obtener el catálogo de modelos de Gemini (${response.statusCode}).',
        provider: providerType,
        statusCode: response.statusCode,
      );
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final models = json['models'] as List? ?? [];
    final ahora = DateTime.now();
    final resultado = <ModeloDisponible>[];
    for (final m in models) {
      final map = m as Map<String, dynamic>;
      final fullName = map['name'].toString(); // "models/gemini-1.5-pro"
      final id =
          fullName.startsWith('models/') ? fullName.substring(7) : fullName;
      final metodos =
          (map['supportedGenerationMethods'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          {};
      final FuncionIa funcion;
      if (metodos.contains('embedContent')) {
        funcion = FuncionIa.embeddings;
      } else if (metodos.contains('generateContent')) {
        funcion = FuncionIa.chat;
      } else {
        continue; // modelo sin capacidad relevante para esta app (ej. solo embeddings legacy o generación de imagen)
      }
      resultado.add(
        ModeloDisponible(
          proveedor: providerType,
          modelId: id,
          nombreVisible: map['displayName']?.toString() ?? id,
          funcion: funcion,
          actualizadoEn: ahora,
        ),
      );
    }
    return resultado;
  }

  @override
  Future<AiChatResponse> enviarMensaje({
    required List<AiChatMessage> mensajes,
    required AiProviderConfig config,
  }) async {
    final stopwatch = Stopwatch()..start();
    // Limpieza de prefijo 'models/' si ya viene en el modelId
    final cleanModelId =
        config.effectiveModelId.startsWith('models/')
            ? config.effectiveModelId.substring(7)
            : config.effectiveModelId;

    final url = Uri.parse(
      '${config.effectiveBaseUrl}/models/$cleanModelId:generateContent',
    );

    final headers = <String, String>{
      'x-goog-api-key': config.apiKey,
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      ...config.extraHeaders,
    };

    // Separar system instruction de contents
    final systemMessages =
        mensajes.where((m) => m.role == AiMessageRole.system).toList();
    final nonSystemMessages =
        mensajes.where((m) => m.role != AiMessageRole.system).toList();

    final systemText = systemMessages.map((m) => m.content).join('\n\n').trim();

    final payload = <String, dynamic>{
      if (systemText.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemText},
          ],
        },
      'contents':
          nonSystemMessages.map((m) {
            return {
              'role': m.role == AiMessageRole.user ? 'user' : 'model',
              'parts': [
                {'text': m.content},
              ],
            };
          }).toList(),
      'generationConfig': {
        'temperature': config.temperature,
        if (config.maxTokens != null) 'maxOutputTokens': config.maxTokens,
      },
    };

    try {
      final response = await _client
          .post(url, headers: headers, body: jsonEncode(payload))
          .timeout(config.timeout);
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final candidates = json['candidates'] as List? ?? [];
        if (candidates.isEmpty) {
          throw AiInvalidRequestException(
            message:
                'La respuesta de Google Gemini no contiene candidatos generados.',
            provider: providerType,
            statusCode: response.statusCode,
          );
        }
        final firstCandidate = candidates[0] as Map<String, dynamic>;
        final contentObj =
            firstCandidate['content'] as Map<String, dynamic>? ?? {};
        final parts = contentObj['parts'] as List? ?? [];
        final textBuffer = StringBuffer();
        for (final part in parts) {
          if (part is Map && part['text'] != null) {
            textBuffer.write(part['text']);
          }
        }
        final content = textBuffer.toString();
        final finishReason = firstCandidate['finishReason']?.toString();
        final usage = json['usageMetadata'] as Map<String, dynamic>?;
        final promptTokens = usage?['promptTokenCount'] as int?;
        final completionTokens = usage?['candidatesTokenCount'] as int?;
        final totalTokens =
            usage?['totalTokenCount'] as int? ??
            ((promptTokens != null && completionTokens != null)
                ? (promptTokens + completionTokens)
                : null);

        return AiChatResponse(
          content: content,
          modelUsed:
              json['modelVersion']?.toString() ?? config.effectiveModelId,
          finishReason: finishReason,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: totalTokens,
          latency: stopwatch.elapsed,
          rawResponse: json,
        );
      }

      _handleErrorResponse(response.statusCode, response.body);
      throw AiServerException(
        message:
            'Error inesperado en Google Gemini con código ${response.statusCode}',
        provider: providerType,
        statusCode: response.statusCode,
      );
    } on AiServiceException {
      rethrow;
    } on TimeoutException catch (e, st) {
      throw AiTimeoutException(
        message:
            'Tiempo de espera agotado (${config.timeout.inSeconds}s) con Google Gemini.',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw AiNetworkException(
        message:
            'Error de conexión HTTP / socket con Google Gemini: ${e.message}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw AiNetworkException(
        message: 'Error de red o comunicación con Google Gemini: $e',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    }
  }

  void _handleErrorResponse(int statusCode, String responseBody) {
    String extractedMessage = responseBody;
    String? statusReason;
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['error'] != null) {
        extractedMessage =
            decoded['error']['message']?.toString() ?? responseBody;
        statusReason = decoded['error']['status']?.toString();
      }
    } catch (e) {
      AiLog.warning(
        'No se pudo parsear el cuerpo de error de Gemini como JSON',
        modulo: 'GeminiAdapter',
        details: e.toString(),
      );
    }

    if (statusCode == 401 ||
        statusCode == 403 ||
        statusReason == 'PERMISSION_DENIED' ||
        statusReason == 'UNAUTHENTICATED' ||
        extractedMessage.contains('API_KEY_INVALID')) {
      throw AiAuthException(
        message: 'Error de autenticación Google Gemini: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 429 || statusReason == 'RESOURCE_EXHAUSTED') {
      throw AiRateLimitException(
        message:
            'Límite de cuota / tasa excedida en Google Gemini: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 400 ||
        statusCode == 422 ||
        statusReason == 'INVALID_ARGUMENT') {
      throw AiInvalidRequestException(
        message: 'Solicitud inválida a Google Gemini: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 410) {
      throw AiModelRetiredException(
        message: 'El modelo fue retirado por Google Gemini: $extractedMessage',
        provider: providerType,
      );
    } else if (statusCode >= 500) {
      throw AiServerException(
        message:
            'Error interno del servidor Google Gemini ($statusCode): $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    }
  }

  @override
  void cancelarStream() {
    if (!_isCustomClient) {
      _activeStreamClient?.close();
    }
    _activeStreamClient = null;
  }

  @override
  Stream<String> enviarMensajeStream({
    required List<AiChatMessage> mensajes,
    required AiProviderConfig config,
  }) async* {
    final cleanModelId =
        config.effectiveModelId.startsWith('models/')
            ? config.effectiveModelId.substring(7)
            : config.effectiveModelId;

    final url = Uri.parse(
      '${config.effectiveBaseUrl}/models/$cleanModelId:streamGenerateContent?alt=sse',
    );

    final headers = <String, String>{
      'x-goog-api-key': config.apiKey,
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...config.extraHeaders,
    };

    final systemMessages =
        mensajes.where((m) => m.role == AiMessageRole.system).toList();
    final nonSystemMessages =
        mensajes.where((m) => m.role != AiMessageRole.system).toList();
    final systemText = systemMessages.map((m) => m.content).join('\n\n').trim();

    final payload = <String, dynamic>{
      if (systemText.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemText},
          ],
        },
      'contents':
          nonSystemMessages.map((m) {
            return {
              'role': m.role == AiMessageRole.user ? 'user' : 'model',
              'parts': [
                {'text': m.content},
              ],
            };
          }).toList(),
      'generationConfig': {
        'temperature': config.temperature,
        if (config.maxTokens != null) 'maxOutputTokens': config.maxTokens,
      },
    };

    final client = _isCustomClient ? _client : http.Client();
    _activeStreamClient = client;

    try {
      final request =
          http.Request('POST', url)
            ..headers.addAll(headers)
            ..body = jsonEncode(payload);

      final streamedResponse = await client
          .send(request)
          .timeout(
            config.timeout,
            onTimeout:
                () =>
                    throw TimeoutException(
                      'Timeout de conexión inicial (${config.timeout.inSeconds}s) con Google Gemini',
                    ),
          );

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        final errorBody = await streamedResponse.stream.bytesToString();
        _handleErrorResponse(streamedResponse.statusCode, errorBody);
        throw AiServerException(
          message:
              'Error inesperado en Google Gemini con código ${streamedResponse.statusCode}',
          provider: providerType,
          statusCode: streamedResponse.statusCode,
        );
      }

      final streamLines = streamedResponse.stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .timeout(
            const Duration(seconds: 45),
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'Timeout de inactividad (45s sin chunks) en stream Google Gemini',
                ),
              );
              sink.close();
            },
          );

      final streamStopwatch = Stopwatch()..start();
      await for (final line in streamLines) {
        if (streamStopwatch.elapsed > const Duration(seconds: 120)) {
          AiLog.warning(
            'Timeout global de stream Google Gemini (120s totales transcurridos)',
          );
          throw TimeoutException(
            'Timeout global: el stream excedió 120s de duración total '
            '(${streamStopwatch.elapsed.inSeconds}s transcurridos)',
          );
        }

        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('data:')) {
          final data = trimmed.substring(5).trim();
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data);
            if (json is Map<String, dynamic>) {
              final candidates = json['candidates'] as List?;
              if (candidates != null && candidates.isNotEmpty) {
                final firstCandidate = candidates[0] as Map<String, dynamic>?;
                final contentObj =
                    firstCandidate?['content'] as Map<String, dynamic>?;
                final parts = contentObj?['parts'] as List?;
                if (parts != null) {
                  for (final part in parts) {
                    if (part is Map && part['text'] != null) {
                      final text = part['text'].toString();
                      if (text.isNotEmpty) {
                        yield text;
                      }
                    }
                  }
                }
              }
            }
          } catch (e) {
            AiLog.warning(
              'GeminiAdapter: chunk de stream no parseable, ignorado',
              details: e.toString(),
            );
          }
        }
      }
    } on AiServiceException {
      rethrow;
    } on TimeoutException catch (e, st) {
      throw AiTimeoutException(
        message:
            'Tiempo de espera agotado con Google Gemini: ${e.message ?? e.toString()}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw AiNetworkException(
        message:
            'Error de conexión HTTP / socket con Google Gemini: ${e.message}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw AiNetworkException(
        message: 'Error de red o comunicación con Google Gemini: $e',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } finally {
      // Solo cerramos el cliente si lo creamos nosotros mismos aquí. Si es
      // el cliente inyectado (compartido por AiProviderFactory en producción,
      // o un MockClient/cliente de prueba inyectado por el llamador),
      // cerrarlo lo dejaría inutilizado para cualquier llamada posterior —
      // ver AiProviderFactory y AGENTS.md.
      if (!_isCustomClient) {
        client.close();
      }
      _activeStreamClient = null;
    }
  }

  @override
  Future<bool> validarConexion({required AiProviderConfig config}) async {
    final response = await enviarMensaje(
      mensajes: [AiChatMessage(role: AiMessageRole.user, content: 'ping')],
      config: config.copyWith(maxTokens: 5),
    );
    return response.content.isNotEmpty;
  }
}
