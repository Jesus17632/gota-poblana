import 'dart:convert';
import 'package:http/http.dart' as http;

/// Estado que reporta el ESP32.
class Esp32Status {
  final bool blinking;
  final int interval;

  const Esp32Status({required this.blinking, required this.interval});

  factory Esp32Status.fromJson(Map<String, dynamic> json) => Esp32Status(
        blinking: json['blinking'] as bool,
        interval: json['interval'] as int,
      );
}

/// Toda la comunicación con el ESP32 vive aquí (HTTP sobre WiFi).
/// La UI no sabe nada de URLs ni de JSON.
class Esp32Service {
  Esp32Service(this.host);

  /// IP o host del ESP32, p. ej. "192.168.4.1"
  final String host;
  static const _timeout = Duration(seconds: 3);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.http(host, path, query);

  Future<Esp32Status> _request(Uri uri) async {
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('ESP32 respondió ${res.statusCode}');
    }
    return Esp32Status.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sirve también como "conectar": si responde, hay conexión.
  Future<Esp32Status> getStatus() => _request(_uri('/status'));

  Future<Esp32Status> setBlink({required bool on, required int interval}) =>
      _request(_uri('/blink', {
        'state': on ? 'on' : 'off',
        'interval': interval.toString(),
      }));
}
