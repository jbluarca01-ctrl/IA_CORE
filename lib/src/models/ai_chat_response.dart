/// Respuesta normalizada emitida por cualquier proveedor de IA integrado.
class AiChatResponse {
  final String content;
  final String modelUsed;
  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final Duration latency;
  final Map<String, dynamic>? rawResponse;

  const AiChatResponse({
    required this.content,
    required this.modelUsed,
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.latency = Duration.zero,
    this.rawResponse,
  });

  AiChatResponse copyWith({
    String? content,
    String? modelUsed,
    String? finishReason,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    Duration? latency,
    Map<String, dynamic>? rawResponse,
  }) {
    return AiChatResponse(
      content: content ?? this.content,
      modelUsed: modelUsed ?? this.modelUsed,
      finishReason: finishReason ?? this.finishReason,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      latency: latency ?? this.latency,
      rawResponse: rawResponse ?? this.rawResponse,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'model_used': modelUsed,
      if (finishReason != null) 'finish_reason': finishReason,
      if (promptTokens != null) 'prompt_tokens': promptTokens,
      if (completionTokens != null) 'completion_tokens': completionTokens,
      if (totalTokens != null) 'total_tokens': totalTokens,
      'latency_ms': latency.inMilliseconds,
      if (rawResponse != null) 'raw_response': rawResponse,
    };
  }

  factory AiChatResponse.fromJson(Map<String, dynamic> json) {
    return AiChatResponse(
      content: json['content'] as String? ?? '',
      modelUsed: json['model_used'] as String? ?? '',
      finishReason: json['finish_reason'] as String?,
      promptTokens: json['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
      latency: json['latency_ms'] != null
          ? Duration(milliseconds: json['latency_ms'] as int)
          : Duration.zero,
      rawResponse: json['raw_response'] != null
          ? Map<String, dynamic>.from(json['raw_response'] as Map)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiChatResponse &&
          runtimeType == other.runtimeType &&
          content == other.content &&
          modelUsed == other.modelUsed &&
          finishReason == other.finishReason &&
          promptTokens == other.promptTokens &&
          completionTokens == other.completionTokens &&
          totalTokens == other.totalTokens &&
          latency == other.latency;

  @override
  int get hashCode =>
      content.hashCode ^
      modelUsed.hashCode ^
      finishReason.hashCode ^
      promptTokens.hashCode ^
      completionTokens.hashCode ^
      totalTokens.hashCode ^
      latency.hashCode;

  @override
  String toString() =>
      'AiChatResponse(model: $modelUsed, latency: ${latency.inMilliseconds}ms, promptTokens: $promptTokens, completionTokens: $completionTokens, preview: ${content.length > 40 ? '${content.substring(0, 40)}...' : content})';
}
