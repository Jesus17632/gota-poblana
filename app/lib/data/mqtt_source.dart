// Cliente MQTT sobre WebSocket. Temas (contrato con el firmware):
//   agua/<nodo>/ph          ESP→app  número (pH filtrado)
//   agua/<nodo>/estado      ESP→app  "IDLE" | "PULSO" | "MEZCLA" | "ERROR"
//   agua/<nodo>/telemetria  ESP→app  JSON (modelo unificado)
//   agua/<nodo>/umbral      app→ESP  número 4.5–7.0
//   agua/<nodo>/cmd         app→ESP  "dosificar" | "detener" | "c <pH>" | "a 100"
import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';

import 'data_source.dart';
import 'models.dart';
import 'mqtt_factory.dart';

class MqttTopics {
  MqttTopics(this.nodo);
  final String nodo;
  String get ph => 'agua/$nodo/ph';
  String get estado => 'agua/$nodo/estado';
  String get telemetria => 'agua/$nodo/telemetria';
  String get umbral => 'agua/$nodo/umbral';
  String get cmd => 'agua/$nodo/cmd';
}

class MqttSource implements DataSource {
  MqttSource({required this.host, required this.port, required this.nodo})
      : topics = MqttTopics(nodo);

  /// "broker.local", "192.168.1.10" o una URL completa "ws://host:puerto/ruta".
  final String host;
  final int port;
  final String nodo;
  final MqttTopics topics;

  final _tele = StreamController<Telemetria>.broadcast();
  final _con = StreamController<ConexionEstado>.broadcast();
  MqttClient? _client;
  StreamSubscription? _sub;
  String? _error;

  /// Estado combinado de los tres temas de entrada.
  final Map<String, dynamic> _merged = {};

  String get url => host.contains('://') ? host : 'ws://$host/mqtt';

  @override
  Stream<Telemetria> get telemetria => _tele.stream;
  @override
  Stream<ConexionEstado> get conexion => _con.stream;
  @override
  String? get errorConexion => _error;
  @override
  String get descripcion => 'MQTT $url:$port';

  @override
  Future<void> start() async {
    await stop();
    _error = null;
    _con.add(ConexionEstado.conectando);
    final id = 'agua-app-${DateTime.now().millisecondsSinceEpoch}';
    final client = crearClienteMqtt(url, id, port);
    client.logging(on: false);
    client.setProtocolV311();
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage =
        MqttConnectMessage().withClientIdentifier(id).startClean();
    client.onConnected = () => _con.add(ConexionEstado.conectado);
    client.onAutoReconnect = () => _con.add(ConexionEstado.conectando);
    client.onAutoReconnected = () => _con.add(ConexionEstado.conectado);
    client.onDisconnected = () => _con.add(ConexionEstado.desconectado);
    _client = client;

    try {
      await client.connect();
    } catch (e) {
      _error = e.toString();
      client.disconnect();
      _client = null;
      _con.add(ConexionEstado.error);
      return;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _error = 'El broker rechazó la conexión '
          '(${client.connectionStatus?.returnCode})';
      client.disconnect();
      _client = null;
      _con.add(ConexionEstado.error);
      return;
    }

    for (final t in [topics.ph, topics.estado, topics.telemetria]) {
      client.subscribe(t, MqttQos.atMostOnce);
    }
    _sub = client.updates?.listen((msgs) {
      for (final m in msgs) {
        final p = m.payload;
        if (p is! MqttPublishMessage) continue;
        final text = MqttPublishPayload.bytesToStringAsString(p.payload.message);
        _onMensaje(m.topic, text);
      }
    });
  }

  void _onMensaje(String topic, String text) {
    final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final t = text.trim();
    if (topic == topics.ph) {
      final v = double.tryParse(t);
      if (v == null) return;
      _merged['ph'] = v;
      _merged['ts'] = ahora;
    } else if (topic == topics.estado) {
      _merged['estado'] = t;
    } else if (topic == topics.telemetria) {
      try {
        final json = jsonDecode(t);
        if (json is! Map) return;
        _merged.addAll(json.cast<String, dynamic>());
        _merged['ts'] ??= ahora;
        if (!json.containsKey('ts')) _merged['ts'] = ahora;
      } catch (_) {
        return; // JSON inválido: se ignora
      }
    } else {
      return;
    }
    _merged['conectado'] = true;
    final tel = Telemetria.fromMap(_merged);
    if (tel != null && !_tele.isClosed) _tele.add(tel);
  }

  void _publicar(String topic, String text) {
    final c = _client;
    if (c == null ||
        c.connectionStatus?.state != MqttConnectionState.connected) {
      throw StateError('Sin conexión con el broker');
    }
    final b = MqttClientPayloadBuilder()..addString(text);
    c.publishMessage(topic, MqttQos.atLeastOnce, b.payload!);
  }

  @override
  Future<void> enviarUmbral(double ph) async =>
      _publicar(topics.umbral, ph.toStringAsFixed(2));

  @override
  Future<void> enviarCmd(String cmd) async => _publicar(topics.cmd, cmd);

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      c.autoReconnect = false;
      c.disconnect();
    }
  }
}
