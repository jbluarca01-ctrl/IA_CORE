/// Rol de un mensaje dentro de una conversación con el motor de IA.
enum AiMessageRole {
  system,
  user,
  assistant;

  static AiMessageRole fromString(String value) {
    switch (value.toLowerCase().trim()) {
      case 'system':
        return AiMessageRole.system;
      case 'user':
        return AiMessageRole.user;
      case 'assistant':
      case 'model':
        return AiMessageRole.assistant;
      default:
        throw ArgumentError('Rol de mensaje no reconocido: $value');
    }
  }
}

/// Representación agnóstica y unificada de un mensaje de chat.
class AiChatMessage {
  final AiMessageRole role;
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  AiChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  AiChatMessage copyWith({
    AiMessageRole? role,
    String? content,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return AiChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    return AiChatMessage(
      role: AiMessageRole.fromString(json['role'] as String? ?? 'user'),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiChatMessage &&
          runtimeType == other.runtimeType &&
          role == other.role &&
          content == other.content &&
          timestamp.isAtSameMomentAs(other.timestamp);

  @override
  int get hashCode => role.hashCode ^ content.hashCode ^ timestamp.hashCode;

  @override
  String toString() => 'AiChatMessage(role: ${role.name}, content: $content, timestamp: $timestamp)';
}
