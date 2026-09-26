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
import 'openai_sse_parser.dart';

/// Adaptador para la API oficial de OpenAI (Chat Completions).
class OpenAiAdapter implements ChatCompletionService {
  final http.Client _client;
  final bool _isCustomClient;
  http.Client? _activeStreamClient;

  OpenAiAdapter({http.Client? client})
    : _client = client ?? http.Client(),
      _isCustomClient = client != null;

  @override
  AiProviderType get providerType => AiProviderType.openAi;

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
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw AiServerException(
        message:
            'No se pudo obtener el catálogo de modelos de OpenAI (${response.statusCode}).',
        provider: providerType,
        statusCode: response.statusCode,
      );
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final data = json['data'] as List? ?? [];
    final ahora = DateTime.now();
    return data.map((m) {
      final id = (m as Map<String, dynamic>)['id'].toString();
      return ModeloDisponible(
        proveedor: providerType,
        modelId: id,
        nombreVisible: id,
        funcion: clasificarFuncionPorId(id),
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
    final url = Uri.parse('${config.effectiveBaseUrl}/chat/completions');

    final headers = <String, String>{
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      ...config.extraHeaders,
    };

    final body = jsonEncode({
      'model': config.effectiveModelId,
      'messages':
          mensajes
              .map((m) => {'role': m.role.name, 'content': m.content})
              .toList(),
      'temperature': config.temperature,
      if (config.maxTokens != null) 'max_tokens': config.maxTokens,
    });

    try {
      final response = await _client
          .post(url, headers: headers, body: body)
          .timeout(config.timeout);
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choices = json['choices'] as List? ?? [];
        if (choices.isEmpty) {
          throw AiInvalidRequestException(
            message:
                'La respuesta de OpenAI no contiene opciones generadas (choices vacío).',
            provider: providerType,
            statusCode: response.statusCode,
          );
        }
        final firstChoice = choices[0] as Map<String, dynamic>;
        final message = firstChoice['message'] as Map<String, dynamic>? ?? {};
        final content = message['content']?.toString() ?? '';
        final finishReason = firstChoice['finish_reason']?.toString();
        final usage = json['usage'] as Map<String, dynamic>?;

        return AiChatResponse(
          content: content,
          modelUsed: json['model']?.toString() ?? config.effectiveModelId,
          finishReason: finishReason,
          promptTokens: usage?['prompt_tokens'] as int?,
          completionTokens: usage?['completion_tokens'] as int?,
          totalTokens: usage?['total_tokens'] as int?,
          latency: stopwatch.elapsed,
          rawResponse: json,
        );
      }

      _handleErrorResponse(response.statusCode, response.body);
      throw AiServerException(
        message: 'Error inesperado en OpenAI con código ${response.statusCode}',
        provider: providerType,
        statusCode: response.statusCode,
      );
    } on AiServiceException {
      rethrow;
    } on TimeoutException catch (e, st) {
      throw AiTimeoutException(
        message:
            'Tiempo de espera agotado (${config.timeout.inSeconds}s) con OpenAI.',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw AiNetworkException(
        message: 'Error de conexión HTTP / socket con OpenAI: ${e.message}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw AiNetworkException(
        message: 'Error de red o comunicación con OpenAI: $e',
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
        'No se pudo parsear el cuerpo de error de OpenAI como JSON',
        modulo: 'OpenAiAdapter',
        details: e.toString(),
      );
    }

    if (statusCode == 401 || statusCode == 403) {
      throw AiAuthException(
        message: 'Error de autenticación OpenAI: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 429) {
      throw AiRateLimitException(
        message: 'Límite de tasa / cuota excedida en OpenAI: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 400 || statusCode == 422) {
      throw AiInvalidRequestException(
        message: 'Solicitud inválida a OpenAI: $extractedMessage',
        provider: providerType,
        statusCode: statusCode,
      );
    } else if (statusCode == 410) {
      throw AiModelRetiredException(
        message: 'El modelo fue retirado por OpenAI: $extractedMessage',
        provider: providerType,
      );
    } else if (statusCode >= 500) {
      throw AiServerException(
        message:
            'Error interno del servidor OpenAI ($statusCode): $extractedMessage',
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
    final url = Uri.parse('${config.effectiveBaseUrl}/chat/completions');

    final headers = <String, String>{
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      ...config.extraHeaders,
    };

    final body = jsonEncode({
      'model': config.effectiveModelId,
      'messages':
          mensajes
              .map((m) => {'role': m.role.name, 'content': m.content})
              .toList(),
      'temperature': config.temperature,
      if (config.maxTokens != null) 'max_tokens': config.maxTokens,
      'stream': true,
    });

    final client = _isCustomClient ? _client : http.Client();
    _activeStreamClient = client;

    try {
      final request =
          http.Request('POST', url)
            ..headers.addAll(headers)
            ..body = body;

      final streamedResponse = await client
          .send(request)
          .timeout(
            config.timeout,
            onTimeout:
                () =>
                    throw TimeoutException(
                      'Timeout de conexión inicial (${config.timeout.inSeconds}s) con OpenAI',
                    ),
          );

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        final errorBody = await streamedResponse.stream.bytesToString();
        _handleErrorResponse(streamedResponse.statusCode, errorBody);
        throw AiServerException(
          message:
              'Error inesperado en OpenAI con código ${streamedResponse.statusCode}',
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
                  'Timeout de inactividad (45s sin chunks) en stream OpenAI',
                ),
              );
              sink.close();
            },
          );

      final streamStopwatch = Stopwatch()..start();
      Stream<String> linesWithStopwatch() async* {
        await for (final line in streamLines) {
          if (streamStopwatch.elapsed > const Duration(seconds: 120)) {
            AiLog.warning(
              'Timeout global de stream OpenAI (120s totales transcurridos)',
            );
            throw TimeoutException(
              'Timeout global: el stream excedió 120s de duración total '
              '(${streamStopwatch.elapsed.inSeconds}s transcurridos)',
            );
          }
          yield line;
        }
      }

      yield* parseOpenAiCompatibleSse(linesWithStopwatch());
    } on AiServiceException {
      rethrow;
    } on TimeoutException catch (e, st) {
      throw AiTimeoutException(
        message:
            'Tiempo de espera agotado con OpenAI: ${e.message ?? e.toString()}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw AiNetworkException(
        message: 'Error de conexión HTTP / socket con OpenAI: ${e.message}',
        provider: providerType,
        originalException: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw AiNetworkException(
        message: 'Error de red o comunicación con OpenAI: $e',
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
