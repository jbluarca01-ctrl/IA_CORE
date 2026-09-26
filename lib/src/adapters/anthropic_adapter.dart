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

/// Adaptador para Anthropic Claude utilizando la Messages API (`/v1/messages`).
class AnthropicAdapter implements ChatCompletionService {
  final http.Client _client;
  final bool _isCustomClient;
  http.Client? _activeStreamClient;

  AnthropicAdapter({http.Client? client})
    : _client = client ?? http.Client(),
      _isCustomClient = client != null;

  @override
  AiProviderType get providerType => AiProviderType.anthropic;

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
        .get(
          Uri.parse('$base/models'),
          headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw AiServerException(
        message:
            'No se pudo obtener el catálogo de modelos de Anthropic (${response.statusCode}).',
        provider: providerType,
        statusCode: response.statusCode,
      );
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final data = json['data'] as List? ?? [];
    final ahora = DateTime.now();
    // Anthropic no ofrece embeddings propios: todo lo que devuelve /models es chat.
    return data.map((m) {
      final map = m as Map<String, dynamic>;
      final id = map['id'].toString();
      return ModeloDisponible(
        proveedor: providerType,
        modelId: id,
        nombreVisible: map['display_name']?.toString() ?? id,
        funcion: FuncionIa.chat,
        actualizadoEn: ahora,
      );
    }).toList();
  }

  @override
  Future<AiChatResponse> enviarMensaje({
    required List<AiChatMessage> mensajes,
    required AiProviderConfig config,
  }) async {
    final stopwatch = Stopwatch()..start();
    final url = Uri.parse('${config.effectiveBaseUrl}/messages');

    final headers = <String, String>{
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json; charset=utf-8',
      'accept': 'application/json',
      ...config.extraHeaders,
    };

    // Separar instrucciones de sistema (van en campo raíz 'system') de los mensajes de usuario/asistente
    final systemMessages =
        mensajes.where((m) => m.role == AiMessageRole.system).toList();
    final nonSystemMessages =
        mensajes.where((m) => m.role != AiMessageRole.system).toList();

    final systemInstruction =
        systemMessages.map((m) => m.content).join('\n\n').trim();

    final payload = <String, dynamic>{
      'model': config.effectiveModelId,
      if (systemInstruction.isNotEmpty) 'system': systemInstruction,
      'messages':
          nonSystemMessages.map((m) {
            return {
              'role': m.role == AiMessageRole.user ? 'user' : 'assistant',
              'content': m.content,
            };
          }).toList(),
      // Anthropic requiere obligatoriamente max_tokens
      'max_tokens': config.maxTokens ?? 1024,
      'temperature': config.temperature,
    };

    try {
      final response = await _client
          .post(url, headers: headers, body: jsonEncode(payload))
          .timeout(config.timeout);
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final contentList = json['content'] as List? ?? [];
        final textBuffer = StringBuffer();
        for (final item in contentList) {
          if (item is Map && item['text'] != null) {
            textBuffer.write(item['text']);
          }
        }
        final content = textBuffer.toString();
        final finishReason = json['stop_reason']?.toString();
        final usage = json['usage'] as Map<String, dynamic>?;
        final inputTokens = usage?['input_tokens'] as int?;
        final outputTokens = usage?['output_tokens'] as int?;
        final totalTokens =
            (inputTokens != null && outputTokens != null)
                ? (inputTokens + outputTokens)
                : null;

        return AiChatResponse(
          content: content,
          modelUsed: json['model']?.toString() ?? config.effectiveModelId,
          finishReason: finishReason,
          promptTokens: inputTokens,
          completionTokens: outputTokens,
          totalTokens: totalTokens,
          latency: stopwatch.elapsed,
          rawResponse: json,
        );
      }

      _handleErrorResponse(response.statusCode, response.body);
      throw AiServerException(
        message:
            'Error inesperado en Anthropic Claude con código ${response.statusCode}',
        provider: providerType,
        statusCode: response.statusCode,
      );
    } on AiServiceException {
      rethrow;
    } on TimeoutException catch (e, st) {
      throw AiTimeoutException(
        message:
            'Tiempo de espera agotado (${config.timeout.inSeconds}s) con Anthropic Claude.',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw AiNetworkException(
        message:
            'Error de conexión HTTP / socket con Anthropic Claude: ${e.message}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw AiNetworkException(
        message: 'Error de red o comunicación con Anthropic Claude: $e',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    }
  }

  void _handleErrorResponse(int statusCode, String responseBody) {
    String extractedMessage = responseBody;
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['error'] != null) {
        extractedMessage =
            decoded['error']['message']?.toString() ?? responseBody;
      }
    } catch (e) {
      AiLog.warning(
        'No se pudo parsear el cuerpo de error de Anthropic Claude como JSON',
        modulo: 'AnthropicAdapter',
        details: e.toString(),
      );
    }

    if (statusCode == 401 || statusCode == 403) {
      throw AiAuthException(
        message: 'Error de autenticación Anthropic Claude: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 429) {
      throw AiRateLimitException(
        message:
            'Límite de tasa / cuota excedida en Anthropic Claude: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 400 || statusCode == 422) {
      throw AiInvalidRequestException(
        message: 'Solicitud inválida a Anthropic Claude: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 410) {
      throw AiModelRetiredException(
        message: 'El modelo fue retirado por Anthropic: $extractedMessage',
        provider: providerType,
      );
    } else if (statusCode >= 500) {
      throw AiServerException(
        message:
            'Error interno del servidor Anthropic Claude ($statusCode): $extractedMessage',
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
    final url = Uri.parse('${config.effectiveBaseUrl}/messages');

    final headers = <String, String>{
      'x-api-key': config.apiKey,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json; charset=utf-8',
      'accept': 'text/event-stream',
      'cache-control': 'no-cache',
      ...config.extraHeaders,
    };

    final systemMessages =
        mensajes.where((m) => m.role == AiMessageRole.system).toList();
    final nonSystemMessages =
        mensajes.where((m) => m.role != AiMessageRole.system).toList();

    final systemInstruction =
        systemMessages.map((m) => m.content).join('\n\n').trim();

    final payload = <String, dynamic>{
      'model': config.effectiveModelId,
      if (systemInstruction.isNotEmpty) 'system': systemInstruction,
      'messages':
          nonSystemMessages.map((m) {
            return {
              'role': m.role == AiMessageRole.user ? 'user' : 'assistant',
              'content': m.content,
            };
          }).toList(),
      'max_tokens': config.maxTokens ?? 1024,
      'temperature': config.temperature,
      'stream': true,
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
                      'Timeout de conexión inicial (${config.timeout.inSeconds}s) con Anthropic Claude',
                    ),
          );

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        final errorBody = await streamedResponse.stream.bytesToString();
        _handleErrorResponse(streamedResponse.statusCode, errorBody);
        throw AiServerException(
          message:
              'Error inesperado en Anthropic Claude con código ${streamedResponse.statusCode}',
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
                  'Timeout de inactividad (45s sin chunks) en stream Anthropic Claude',
                ),
              );
              sink.close();
            },
          );

      final streamStopwatch = Stopwatch()..start();
      String? currentEvent;

      await for (final line in streamLines) {
        if (streamStopwatch.elapsed > const Duration(seconds: 120)) {
          AiLog.warning(
            'Timeout global de stream Anthropic Claude (120s totales transcurridos)',
          );
          throw TimeoutException(
            'Timeout global: el stream excedió 120s de duración total '
            '(${streamStopwatch.elapsed.inSeconds}s transcurridos)',
          );
        }

        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          currentEvent = null;
          continue;
        }

        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring(6).trim();
          continue;
        }

        if (trimmed.startsWith('data:')) {
          final dataStr = trimmed.substring(5).trim();
          if (dataStr.isEmpty) continue;

          try {
            final json = jsonDecode(dataStr);
            if (json is Map<String, dynamic>) {
              final type = json['type']?.toString();
              if (currentEvent == 'content_block_delta' ||
                  type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  final deltaType = delta['type']?.toString();
                  final text = delta['text']?.toString();
                  if ((deltaType == null || deltaType == 'text_delta') &&
                      text != null &&
                      text.isNotEmpty) {
                    yield text;
                  }
                }
              } else if (currentEvent == 'message_stop' ||
                  type == 'message_stop') {
                break;
              }
            }
          } catch (e) {
            AiLog.warning(
              'AnthropicAdapter: chunk de stream no parseable, ignorado',
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
            'Tiempo de espera agotado con Anthropic Claude: ${e.message ?? e.toString()}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw AiNetworkException(
        message:
            'Error de conexión HTTP / socket con Anthropic Claude: ${e.message}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw AiNetworkException(
        message: 'Error de red o comunicación con Anthropic Claude: $e',
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
