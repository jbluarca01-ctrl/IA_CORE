/// Punto de log del paquete. El paquete no depende de ninguna app: quien lo
/// consume registra aquí su propio destino (p. ej. PRAXIA lo enlaza a
/// `AppLogService`). Por defecto no hace nada.
typedef AiWarningSink = void Function(
  String message, {
  String? modulo,
  String? details,
});

class AiLog {
  AiLog._();

  /// Destino de los avisos; `null` = se descartan.
  static AiWarningSink? warningSink;

  static void warning(String message, {String? modulo, String? details}) {
    warningSink?.call(message, modulo: modulo, details: details);
  }
}
