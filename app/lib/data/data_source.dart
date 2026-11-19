// Servicio de dispositivos: interfaz única. La UI y AppState solo hablan con
// esto; SimuladorESP32 y MqttSource son intercambiables.
// La app NUNCA toca pines ni I2C: solo manda órdenes de alto nivel y refleja
// lo que el ESP32 reporta.
import '../core/device_constants.dart';
import 'models.dart';

enum ConexionEstado { desconectado, conectando, conectado, error }

abstract class DataSource {
  /// agua/<nodo>/telemetria (+ ph + estado combinados).
  Stream<Telemetria> get telemetria;

  /// agua/<nodo>/evento
  Stream<EventoDispositivo> get eventos;

  /// agua/<nodo>/hardware
  Stream<HardwareEstado> get hardware;

  Stream<ConexionEstado> get conexion;
  String? get errorConexion;
  String get descripcion;

  /// true mientras sea el simulador (la UI muestra "MODO SIMULADO").
  bool get simulado;

  Future<void> start();
  Future<void> stop();

  /// app→ESP: umbral de pH (4.5–7.0). El firmware puede rechazarlo.
  Future<void> enviarUmbral(double ph);

  /// app→ESP: ver [Cmd].
  Future<void> enviarCmd(String cmd);
}

/// Comandos del contrato (tema cmd).
class Cmd {
  Cmd._();
  static const dosificar = DeviceConst.cmdDosificar;
  static const detener = DeviceConst.cmdDetener;
  static String pulso(int ms) => '${DeviceConst.cmdPulso} $ms';
  static String calibrar(double phRef) =>
      '${DeviceConst.cmdCalibrar} ${phRef.toStringAsFixed(2)}';
  static String rellenarAcido(int ml) => '${DeviceConst.cmdAcido} $ml';
  static String testBuzzer(String tipo) => '${DeviceConst.cmdTestBuzzer} $tipo';
  static String testLed(int r, int g, int b) =>
      '${DeviceConst.cmdTestLed} $r $g $b';
  static String caudal(double mlPorSegundo, double t0Ms) =>
      '${DeviceConst.cmdCaudal} ${mlPorSegundo.toStringAsFixed(2)} ${t0Ms.round()}';
}
