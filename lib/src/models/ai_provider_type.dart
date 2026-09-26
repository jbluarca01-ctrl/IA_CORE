/// Tipos de proveedores de Inteligencia Artificial soportados por PRAXIA Industrial.
enum AiProviderType {
  nvidiaNim,
  anthropic,
  gemini,
  openAi,
  openRouter;

  /// Nombre amigable para visualización en UI y reportes.
  String get displayName {
    switch (this) {
      case AiProviderType.nvidiaNim:
        return 'NVIDIA NIM';
      case AiProviderType.anthropic:
        return 'Anthropic Claude';
      case AiProviderType.gemini:
        return 'Google Gemini';
      case AiProviderType.openAi:
        return 'OpenAI';
      case AiProviderType.openRouter:
        return 'OpenRouter';
    }
  }

  /// URL base por defecto según la especificación oficial de la API de cada proveedor.
  String get defaultBaseUrl {
    switch (this) {
      case AiProviderType.nvidiaNim:
        return 'https://integrate.api.nvidia.com/v1';
      case AiProviderType.anthropic:
        return 'https://api.anthropic.com/v1';
      case AiProviderType.gemini:
        return 'https://generativelanguage.googleapis.com/v1beta';
      case AiProviderType.openAi:
        return 'https://api.openai.com/v1';
      case AiProviderType.openRouter:
        return 'https://openrouter.ai/api/v1';
    }
  }

  /// Modelo por defecto recomendado para diagnóstico industrial en cada proveedor.
  String get defaultModel {
    switch (this) {
      case AiProviderType.nvidiaNim:
        return 'meta/llama-3.1-70b-instruct';
      case AiProviderType.anthropic:
        return 'claude-3-5-sonnet-20241022';
      case AiProviderType.gemini:
        return 'gemini-1.5-pro';
      case AiProviderType.openAi:
        return 'gpt-4o';
      case AiProviderType.openRouter:
        return 'anthropic/claude-3.5-sonnet';
    }
  }

  /// Deserializa desde cadena persistida en configuración o base de datos.
  ///
  /// Acepta tanto el nombre de enum camelCase (`nvidiaNim`) como los alias
  /// persistidos en SharedPreferences en snake_case (`nvidia_nim`, `openai`,
  /// `openrouter`).
  static AiProviderType fromString(String value) {
    // Alias snake_case → enum value (para compatibilidad con SharedPreferences).
    const aliases = <String, AiProviderType>{
      'nvidia_nim': AiProviderType.nvidiaNim,
      'openai': AiProviderType.openAi,
      'openrouter': AiProviderType.openRouter,
      'gemini': AiProviderType.gemini,
      'anthropic': AiProviderType.anthropic,
    };
    final normalized = value.toLowerCase().trim();
    if (aliases.containsKey(normalized)) return aliases[normalized]!;
    return AiProviderType.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse:
          () => throw ArgumentError('Proveedor de IA no reconocido: $value'),
    );
  }
}
