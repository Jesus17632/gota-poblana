import 'dart:convert';
import 'package:http/http.dart' as http;

/// Lo que devuelve GET /datos del firmware.
class SensorData {
  final double temperatura;
  final int humedad;
  final int uptime; // segundos desde que arrancó el ESP32

  const SensorData({
    required this.temperatura,
    required this.humedad,
    required this.uptime,
  });

  // `num` porque ArduinoJson puede mandar 25 o 25.3 según el valor
  factory SensorData.fromJson(Map<String, dynamic> json) => SensorData(
        temperatura: (json['temperatura'] as num).toDouble(),
        humedad: (json['humedad'] as num).toInt(),
        uptime: (json['uptime'] as num).toInt(),
      );
}

/// Toda la comunicación con el ESP32 vive aquí (HTTP sobre WiFi).
/// La UI no sabe nada de URLs ni de JSON.
///
/// API del firmware:
///   GET /datos             -> {"temperatura":27.3,"humedad":61,"uptime":120}
///   GET /led?estado=1|0    -> "OK" (texto plano)
class Esp32Service {
  Esp32Service(this.host);

  /// IP del ESP32, opcionalmente con puerto: "172.20.10.9" o "172.20.10.9:8080"
  final String host;
  static const _timeout = Duration(seconds: 3);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.http(host, path, query);

  Future<http.Response> _get(Uri uri) async {
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('ESP32 respondió ${res.statusCode} en ${uri.path}');
    }
    return res;
  }

  /// También sirve como "conectar": si responde, hay conexión.
  Future<SensorData> getDatos() async {
    final res = await _get(_uri('/datos'));
    return SensorData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> setLed(bool on) =>
      _get(_uri('/led', {'estado': on ? '1' : '0'}));

  /// Debug: GET a cualquier ruta y devuelve código + cuerpo sin interpretar.
  Future<({int code, String body})> getRaw(String path) async {
    final res = await http.get(_uri(path)).timeout(_timeout);
    return (code: res.statusCode, body: res.body);
  }
}
