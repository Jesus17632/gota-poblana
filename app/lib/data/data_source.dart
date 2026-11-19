// Interfaz única de la capa de datos. La UI y el estado de la app solo
// hablan con esto; Simulador y MQTT son intercambiables.
import 'models.dart';

enum ConexionEstado { desconectado, conectando, conectado, error }

abstract class DataSource {
  /// Lecturas/estado del equipo (puede llegar varias veces por segundo).
  Stream<Telemetria> get telemetria;

  /// Cambios de conexión.
  Stream<ConexionEstado> get conexion;

  /// Último mensaje de error de conexión, si hubo.
  String? get errorConexion;

  /// Nombre para mostrar ("Simulador", "MQTT ws://…").
  String get descripcion;

  Future<void> start();
  Future<void> stop();

  /// app→ESP: umbral de pH (4.5–7.0). El firmware puede rechazarlo.
  Future<void> enviarUmbral(double ph);

  /// app→ESP: "dosificar" | "detener" | "c <pH>" | "a 100"
  Future<void> enviarCmd(String cmd);
}

/// Comandos del contrato con el firmware.
class Cmd {
  Cmd._();
  static const dosificar = 'dosificar';
  static const detener = 'detener';
  static String calibrar(double phRef) => 'c ${phRef.toStringAsFixed(2)}';
  static String rellenarAcido(int ml) => 'a $ml';
}
