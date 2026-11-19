// ============================================================================
// CONSTANTES DEL CONTRATO CON EL ESP32 — edítalas aquí y solo aquí.
// No cambies nombres de temas, comandos ni campos sin avisar al equipo de
// firmware: ambos lados deben coincidir.
// ============================================================================

class DeviceConst {
  DeviceConst._();

  // ---------------- MQTT ----------------
  /// Interruptor general. Mientras el firmware no exista, la app NO intenta
  /// conectarse. Cámbialo a true cuando el ESP32 publique en el broker.
  static const bool mqttHabilitado = false;

  static const String mqttHostPorDefecto = '192.168.1.10';
  static const int mqttPuertoPorDefecto = 9001; // listener WebSocket
  static const String mqttRutaPorDefecto = '/mqtt';
  static const String nodoPorDefecto = 'nodo1';

  static const String temaBase = 'agua';
  static String tema(String nodo, String sub) => '$temaBase/$nodo/$sub';

  // ESP32 → app
  static const String subPh = 'ph';
  static const String subEstado = 'estado';
  static const String subTelemetria = 'telemetria';
  static const String subEvento = 'evento';
  static const String subHardware = 'hardware';
  // app → ESP32
  static const String subUmbral = 'umbral';
  static const String subCmd = 'cmd';

  // ---------------- Comandos (tema cmd) ----------------
  static const String cmdDosificar = 'dosificar';
  static const String cmdDetener = 'detener';
  static const String cmdPulso = 'p'; // "p <ms>"
  static const String cmdCalibrar = 'c'; // "c <pH>"
  static const String cmdAcido = 'a'; // "a 100"
  static const String cmdTestBuzzer = 'test_buzzer'; // inicio|fin|error
  static const String cmdTestLed = 'test_led'; // "<r> <g> <b>"

  // ---------------- Límites de seguridad (los aplica el firmware) ----------
  static const double umbralMin = 4.5;
  static const double umbralMax = 7.0;
  static const int pulsoMaxMs = 1500;
  static const int pulsoPruebaMs = 100;
  static const double margenRechazo = 0.05; // dosificar con pH ≤ umbral + esto → RECHAZO
  static const double mlPorSegundoBomba = 33.0;
  static const double acidoInicialMl = 100.0;
  static const double acidoBajoMl = 20.0;

  /// Si no llega respuesta en este tiempo → "Sin respuesta del dispositivo".
  static const Duration timeoutRespuesta = Duration(seconds: 3);

  // ---------------- Tonos (Hz, ms) ----------------
  static const List<(int, int)> tonosInicio = [(880, 150), (1320, 150)];
  static const List<(int, int)> tonosFin = [(1320, 150), (1100, 150), (880, 150)];
  static const List<(int, int)> tonosError = [(400, 150), (400, 150), (400, 150)];
  static const int pausaEntreTonosMs = 60;

  // ---------------- Simulador ----------------
  static const int retardoRedMinMs = 150;
  static const int retardoRedMaxMs = 400;
  static const int mezclaMs = 3000;
  static const double tolerancia = 0.03; // llega al umbral si pH ≤ umbral + esto
}
