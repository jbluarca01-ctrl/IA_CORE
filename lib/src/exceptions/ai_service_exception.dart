import '../models/ai_provider_type.dart';

/// Jerarquía de excepciones tipadas para los servicios y adaptadores de IA.
abstract class AiServiceException implements Exception {
  final String message;
  final AiProviderType provider;
  final int? statusCode;
  final Object? originalException;
  final StackTrace? stackTrace;

  const AiServiceException({
    required this.message,
    required this.provider,
    this.statusCode,
    this.originalException,
    this.stackTrace,
  });

  @override
  String toString() =>
      '[$runtimeType] [${provider.displayName}] $message${statusCode != null ? ' (Status $statusCode)' : ''}';
}

/// Error de autenticación o autorización (HTTP 401 / 403: API Key inválida o sin permisos).
class AiAuthException extends AiServiceException {
  const AiAuthException({
    required super.message,
    required super.provider,
    super.statusCode = 401,
    super.originalException,
    super.stackTrace,
  });
}

/// Límite de tasa o cuota excedida (HTTP 429).
class AiRateLimitException extends AiServiceException {
  const AiRateLimitException({
    required super.message,
    required super.provider,
    super.statusCode = 429,
    super.originalException,
    super.stackTrace,
  });
}

/// Solicitud mal formada o parámetros rechazados por el proveedor (HTTP 400 / 422).
class AiInvalidRequestException extends AiServiceException {
  const AiInvalidRequestException({
    required super.message,
    required super.provider,
    super.statusCode = 400,
    super.originalException,
    super.stackTrace,
  });
}

/// El modelo solicitado fue retirado permanentemente por el proveedor (HTTP 410 Gone).
/// A diferencia de un 4XX genérico, esto significa que reintentar con el mismo
/// modelo nunca va a funcionar — hay que marcarlo deprecado y forzar al
/// usuario a elegir un reemplazo en Ajustes → Modelos de IA.
class AiModelRetiredException extends AiServiceException {
  const AiModelRetiredException({
    required super.message,
    required super.provider,
    super.statusCode = 410,
    super.originalException,
    super.stackTrace,
  });
}

/// Error interno o caída temporal en los servidores del proveedor (HTTP 500, 502, 503, 504).
class AiServerException extends AiServiceException {
  const AiServerException({
    required super.message,
    required super.provider,
    super.statusCode = 500,
    super.originalException,
    super.stackTrace,
  });
}

/// Tiempo de espera agotado al conectar o recibir respuesta.
class AiTimeoutException extends AiServiceException {
  const AiTimeoutException({
    required super.message,
    required super.provider,
    super.statusCode,
    super.originalException,
    super.stackTrace,
  });
}

/// Fallo de red física, socket interrumpido o error DNS.
class AiNetworkException extends AiServiceException {
  const AiNetworkException({
    required super.message,
    required super.provider,
    super.statusCode,
    super.originalException,
    super.stackTrace,
  });
}
