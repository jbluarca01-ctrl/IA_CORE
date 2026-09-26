import 'models/ai_chat_message.dart';
import 'models/ai_chat_response.dart';
import 'models/ai_provider_config.dart';
import 'models/ai_provider_type.dart';
import 'models/modelo_ia.dart';

/// Contrato base unificado (Borne Común) para todos los motores y adaptadores de IA.
abstract class ChatCompletionService {
  /// Envía una lista de mensajes al proveedor configurado y devuelve la respuesta unificada.
  Future<AiChatResponse> enviarMensaje({
    required List<AiChatMessage> mensajes,
    required AiProviderConfig config,
  });

  /// Verifica la validez de las credenciales y conectividad con una petición mínima de prueba.
  Future<bool> validarConexion({required AiProviderConfig config});

  /// Consulta el catálogo de modelos disponibles del proveedor (`GET /models`
  /// o equivalente) y lo normaliza a [ModeloDisponible]. Alimenta el dropdown
  /// de selección manual — nunca se usa para auto-seleccionar un modelo.
  Future<List<ModeloDisponible>> listarModelos({
    required String apiKey,
    String? baseUrl,
  });

  /// Envía mensajes en modo streaming (SSE) y emite el contenido incremental
  /// (delta) token a token. Lanza las mismas excepciones tipadas que enviarMensaje
  /// si la conexión falla antes de recibir el primer chunk; errores a mitad de
  /// stream se propagan como error del Stream.
  Stream<String> enviarMensajeStream({
    required List<AiChatMessage> mensajes,
    required AiProviderConfig config,
  });

  /// Cierra la conexión HTTP activa de streaming, si existe. No-op por defecto
  /// para proveedores sin streaming en curso.
  void cancelarStream() {}

  /// Tipo de proveedor que maneja esta instancia.
  AiProviderType get providerType;
}
