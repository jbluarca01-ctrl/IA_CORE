import 'ai_provider_type.dart';

/// Configuración inmutable para la invocación de un proveedor de IA.
class AiProviderConfig {
  final AiProviderType providerType;
  final String apiKey;
  final String? baseUrl;
  final String modelId;
  final Duration timeout;
  final double temperature;
  final int? maxTokens;
  final Map<String, String> extraHeaders;

  AiProviderConfig({
    required this.providerType,
    required this.apiKey,
    this.baseUrl,
    String? modelId,
    this.timeout = const Duration(seconds: 30),
    this.temperature = 0.2,
    this.maxTokens,
    this.extraHeaders = const {},
  })  : modelId = (modelId != null && modelId.trim().isNotEmpty)
            ? modelId.trim()
            : providerType.defaultModel {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('La API Key no puede estar vacía para el proveedor ${providerType.displayName}.');
    }
    if (temperature < 0.0 || temperature > 2.0) {
      throw ArgumentError('La temperatura debe estar en el rango [0.0, 2.0]. Valor recibido: $temperature');
    }
  }

  /// URL base efectiva: utiliza la personalizada si fue provista, o la oficial por defecto.
  String get effectiveBaseUrl {
    if (baseUrl != null && baseUrl!.trim().isNotEmpty) {
      return baseUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return providerType.defaultBaseUrl;
  }

  /// Identificador de modelo efectivo.
  String get effectiveModelId {
    if (modelId.trim().isNotEmpty) {
      return modelId.trim();
    }
    return providerType.defaultModel;
  }

  AiProviderConfig copyWith({
    AiProviderType? providerType,
    String? apiKey,
    String? baseUrl,
    String? modelId,
    Duration? timeout,
    double? temperature,
    int? maxTokens,
    Map<String, String>? extraHeaders,
  }) {
    return AiProviderConfig(
      providerType: providerType ?? this.providerType,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      modelId: modelId ?? this.modelId,
      timeout: timeout ?? this.timeout,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_type': providerType.name,
      'api_key': apiKey,
      if (baseUrl != null) 'base_url': baseUrl,
      'model_id': modelId,
      'timeout_ms': timeout.inMilliseconds,
      'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (extraHeaders.isNotEmpty) 'extra_headers': extraHeaders,
    };
  }

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    return AiProviderConfig(
      providerType: AiProviderType.fromString(json['provider_type'] as String? ?? 'nvidiaNim'),
      apiKey: json['api_key'] as String? ?? '',
      baseUrl: json['base_url'] as String?,
      modelId: json['model_id'] as String?,
      timeout: json['timeout_ms'] != null
          ? Duration(milliseconds: json['timeout_ms'] as int)
          : const Duration(seconds: 30),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      maxTokens: json['max_tokens'] as int?,
      extraHeaders: json['extra_headers'] != null
          ? Map<String, String>.from(json['extra_headers'] as Map)
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiProviderConfig &&
          runtimeType == other.runtimeType &&
          providerType == other.providerType &&
          apiKey == other.apiKey &&
          baseUrl == other.baseUrl &&
          modelId == other.modelId &&
          timeout == other.timeout &&
          temperature == other.temperature &&
          maxTokens == other.maxTokens;

  @override
  int get hashCode =>
      providerType.hashCode ^
      apiKey.hashCode ^
      baseUrl.hashCode ^
      modelId.hashCode ^
      timeout.hashCode ^
      temperature.hashCode ^
      maxTokens.hashCode;

  @override
  String toString() =>
      'AiProviderConfig(provider: ${providerType.displayName}, model: $effectiveModelId, baseUrl: $effectiveBaseUrl, timeout: ${timeout.inSeconds}s, temp: $temperature)';
}
