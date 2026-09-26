import 'ai_provider_type.dart';

/// Subcadena que identifica la ÚNICA familia de modelos de embeddings NVIDIA
/// compatible con la dimensión actualmente compilada en el índice vectorial
/// ObjectBox (ver `NvidiaEmbeddingService.dimension` y
/// `VectorChunkEntity.embedding` en `lib/models/vector_chunk_entity.dart`,
/// que deben coincidir siempre entre sí y con esta familia).
///
/// Única fuente de verdad: se usa aquí (auto-selección) y en el dropdown
/// manual de Ajustes → Modelos de IA. Mantenerlos como una sola constante
/// evita que se desincronicen entre archivos — eso fue exactamente lo que
/// permitió que un modelo incompatible (`llama-nemotron-embed-vl-1b-v2`
/// antes de este cambio) quedara seleccionable/pegado (ver
/// INFORME_INVESTIGACION_LOOP_REELECCION_EMBEDDING_ROTO_2026-09-05.md).
///
/// Cambiar este valor SIEMPRE debe ir acompañado de actualizar
/// `NvidiaEmbeddingService.dimension` y el `@HnswIndex(dimensions: ...)` de
/// `VectorChunkEntity` a la dimensión real del modelo nuevo, y regenerar
/// `objectbox.g.dart` — `VectorIndexMigrationService` se encarga de
/// reindexar automáticamente los manuales ya importados en el siguiente
/// arranque tras ese cambio.
const String familiaEmbeddingCompatible = 'llama-nemotron-embed-vl';

/// Función/tarea de IA a la que se aplica un modelo. Cada función tiene su
/// propia selección independiente de modelo activo (requisito: "uno para
/// chat, uno para embeddings", extendido a las 4 tareas internas que también
/// dependían de un modelo hardcodeado).
enum FuncionIa {
  chat,
  embeddings,
  clasificacion,
  vision,
  ocr;

  String get nombreVisible {
    switch (this) {
      case FuncionIa.chat:
        return 'Chat / Diagnóstico';
      case FuncionIa.embeddings:
        return 'Embeddings (búsqueda RAG)';
      case FuncionIa.clasificacion:
        return 'Clasificación de manuales';
      case FuncionIa.vision:
        return 'Visión (identificación por foto)';
      case FuncionIa.ocr:
        return 'OCR de manuales escaneados';
    }
  }

  static FuncionIa fromString(String value) {
    return FuncionIa.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Función de IA no reconocida: $value'),
    );
  }
}

/// Heurística para clasificar un modelo del catálogo `/models` de un
/// proveedor como de chat o de embeddings — es lo único que se puede inferir
/// de forma confiable de un listado genérico sin llamar a cada modelo.
/// Los modelos de chat sirven también para las tareas internas de
/// clasificación/visión/OCR (todas son llamadas chat-completions a un
/// modelo específico): el dropdown de esas 3 funciones reutiliza el
/// catálogo de 'chat', no se piden catálogos separados por proveedor.
FuncionIa clasificarFuncionPorId(String modelId) {
  final id = modelId.toLowerCase();
  if (id.contains('embed') || id.contains('embedding')) {
    return FuncionIa.embeddings;
  }
  return FuncionIa.chat;
}

/// Funciones que comparten un único modelo elegido manualmente por el
/// usuario (selector "general" en Ajustes → Modelos de IA). Embeddings queda
/// fuera adrede: técnicamente no puede ser el mismo modelo de chat, así que
/// se autoselecciona por separado (ver [elegirMejorEmbedding]) — es la única
/// excepción deliberada a "cero auto-selección", pedida explícitamente para
/// no exigirle al usuario elegir algo que no puede evaluar (formato de
/// vector, dimensión) desde la UI.
const List<FuncionIa> funcionesDelSelectorGeneral = [
  FuncionIa.chat,
  FuncionIa.clasificacion,
  FuncionIa.vision,
  FuncionIa.ocr,
];

/// Elige automáticamente el mejor modelo de embeddings vigente del catálogo
/// para autoseleccionar sin intervención del usuario.
///
/// Solo auto-selecciona modelos de [familiaEmbeddingCompatible] — la única
/// validada para la dimensión que espera el índice vectorial ObjectBox HNSW
/// actual. NO cae a "el primero vigente que sea": el catálogo `/v1/models`
/// de NVIDIA no reporta dimensión de salida, y un modelo de otra familia con
/// otra dimensión rompe el índice en tiempo de ejecución de forma silenciosa
/// para el manual completo. Si no hay ninguno vigente de esa familia, se
/// devuelve `null` — el técnico debe elegir uno manualmente en Ajustes →
/// Modelos de IA (dropdown agregado para esto).
ModeloDisponible? elegirMejorEmbedding(List<ModeloDisponible> catalogo) {
  final vigentes = catalogo.where(
    (m) =>
        m.funcion == FuncionIa.embeddings &&
        m.estado == EstadoModelo.vigente &&
        m.modelId.contains(familiaEmbeddingCompatible),
  );
  return vigentes.isEmpty ? null : vigentes.first;
}

/// Se lanza cuando un servicio necesita el modelo activo de [funcion] y el
/// usuario todavía no ha elegido ninguno en Ajustes → Modelos de IA. Nunca se
/// resuelve auto-seleccionando un modelo — el llamador debe mostrar un
/// mensaje claro guiando al usuario a configurarlo.
class ModeloNoConfiguradoException implements Exception {
  final FuncionIa funcion;
  ModeloNoConfiguradoException(this.funcion);

  @override
  String toString() =>
      'No hay un modelo seleccionado para "${funcion.nombreVisible}". '
      'Ve a Ajustes → Modelos de IA y elige uno.';
}

/// Estado de vigencia de un modelo tal como lo reporta el catálogo del
/// proveedor (cuando el proveedor no reporta estado, se asume vigente).
enum EstadoModelo {
  vigente,
  deprecado;

  static EstadoModelo fromString(String value) {
    return EstadoModelo.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EstadoModelo.vigente,
    );
  }
}

/// Un modelo tal como lo reporta el catálogo `/models` de un proveedor,
/// normalizado a una forma común para los 5 proveedores soportados.
class ModeloDisponible {
  final AiProviderType proveedor;
  final String modelId;
  final String nombreVisible;
  final FuncionIa funcion;
  final EstadoModelo estado;
  final DateTime actualizadoEn;

  const ModeloDisponible({
    required this.proveedor,
    required this.modelId,
    required this.nombreVisible,
    required this.funcion,
    this.estado = EstadoModelo.vigente,
    required this.actualizadoEn,
  });

  Map<String, dynamic> toDbMap() => {
        'proveedor': proveedor.name,
        'model_id': modelId,
        'nombre_visible': nombreVisible,
        'funcion': funcion.name,
        'estado': estado.name,
        'actualizado_en': actualizadoEn.toIso8601String(),
      };

  factory ModeloDisponible.fromDbMap(Map<String, dynamic> map) {
    return ModeloDisponible(
      proveedor: AiProviderType.fromString(map['proveedor'] as String),
      modelId: map['model_id'] as String,
      nombreVisible: map['nombre_visible'] as String,
      funcion: FuncionIa.fromString(map['funcion'] as String),
      estado: EstadoModelo.fromString(map['estado'] as String),
      actualizadoEn: DateTime.parse(map['actualizado_en'] as String),
    );
  }

  @override
  String toString() =>
      'ModeloDisponible(${proveedor.name}/$modelId, funcion: ${funcion.name}, estado: ${estado.name})';
}

/// La selección manual y explícita del usuario para una función dada. Solo
/// existe una fila por función (constraint UNIQUE en `funcion`).
class ModeloActivo {
  final FuncionIa funcion;
  final AiProviderType proveedor;
  final String modelId;
  final DateTime seleccionadoEn;

  const ModeloActivo({
    required this.funcion,
    required this.proveedor,
    required this.modelId,
    required this.seleccionadoEn,
  });

  Map<String, dynamic> toDbMap() => {
        'funcion': funcion.name,
        'proveedor': proveedor.name,
        'model_id': modelId,
        'seleccionado_en': seleccionadoEn.toIso8601String(),
      };

  factory ModeloActivo.fromDbMap(Map<String, dynamic> map) {
    return ModeloActivo(
      funcion: FuncionIa.fromString(map['funcion'] as String),
      proveedor: AiProviderType.fromString(map['proveedor'] as String),
      modelId: map['model_id'] as String,
      seleccionadoEn: DateTime.parse(map['seleccionado_en'] as String),
    );
  }
}
