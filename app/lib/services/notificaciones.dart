// Notificaciones del SISTEMA (fuera de la app): barra de notificaciones de
// Android y de Linux. En web no hay: la clase base no hace nada.
import 'notificaciones_stub.dart'
    if (dart.library.io) 'notificaciones_io.dart' as impl;

class Notificaciones {
  /// Implementación de la plataforma actual (Android/Linux) o nula.
  static Notificaciones plataforma() => impl.crear();

  bool get disponible => false;

  /// Monitoreo en segundo plano (servicio en primer plano de Android).
  bool get soportaMonitoreo => false;

  Future<void> iniciar() async {}

  /// Pide el permiso (Android 13+). Devuelve si quedó concedido.
  Future<bool> pedirPermiso() async => false;

  Future<void> mostrar({
    required int id,
    required String titulo,
    required String cuerpo,
    String? resumen, // línea pequeña: lugar · nodo
    bool critica = false,
  }) async {}

  /// Mantiene viva la conexión con una notificación fija "Monitoreando…".
  Future<void> monitoreo(bool activo, {String? texto}) async {}
}
