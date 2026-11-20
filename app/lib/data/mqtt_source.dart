// Cliente MQTT sobre WebSocket. Implementación completa del contrato, pero
// DESACTIVADA mientras DeviceConst.mqttHabilitado == false (no se conecta).
//
//   agua/<nodo>/ph          ESP→app  número (pH filtrado)
//   agua/<nodo>/estado      ESP→app  "IDLE" | "PULSO" | "MEZCLA" | "ERROR"
//   agua/<nodo>/telemetria  ESP→app  JSON (modelo unificado)
//   agua/<nodo>/evento      ESP→app  JSON {"ts","tipo","detalle","cmd"}
//   agua/<nodo>/hardware    ESP→app  JSON {"rele","led","buzzer","sensor","modulos"}
//   agua/<nodo>/umbral      app→ESP  número 4.5–7.0
//   agua/<nodo>/cmd         app→ESP  texto (ver Cmd)
import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';

import '../core/device_constants.dart';
import 'data_source.dart';
import 'models.dart';
import 'mqtt_factory.dart';

class MqttTopics {
  MqttTopics(this.nodo);
  final String nodo;
  String get ph => DeviceConst.tema(nodo, DeviceConst.subPh);
  String get estado => DeviceConst.tema(nodo, DeviceConst.subEstado);
  String get telemetria => DeviceConst.tema(nodo, DeviceConst.subTelemetria);
  String get evento => DeviceConst.tema(nodo, DeviceConst.subEvento);
  String get hardware => DeviceConst.tema(nodo, DeviceConst.subHardware);
  String get umbral => DeviceConst.tema(nodo, DeviceConst.subUmbral);
  String get cmd => DeviceConst.tema(nodo, DeviceConst.subCmd);

  List<String> get entrada => [ph, estado, telemetria, evento, hardware];
}

class MqttSource implements DataSource {
  MqttSource({
    required this.host,
    required this.port,
    required this.ruta,
    required this.nodo,
  }) : topics = MqttTopics(nodo);

  /// "192.168.1.10" o una URL completa "ws://host/ruta".
  final String host;
  final int port;
  final String ruta; // p. ej. "/mqtt"
  final String nodo;
  final MqttTopics topics;

  final _tele = StreamController<Telemetria>.broadcast();
  final _ev = StreamController<EventoDispositivo>.broadcast();
  final _hw = StreamController<HardwareEstado>.broadcast();
  final _con = StreamController<ConexionEstado>.broadcast();
  MqttClient? _client;

  /// Host configurado y, de respaldo, la red propia del ESP32 (192.168.4.1).
  /// Si uno falla, el siguiente reintento prueba el otro.
  late final List<String> _hosts = [
    host,
    if (!host.contains('://'))
      for (final h in DeviceConst.mqttHostsConocidos)
        if (h != host) h,
  ];
  int _iHost = 0;
  String get _hostActual => _hosts[_iHost];
  StreamSubscription? _sub;
  String? _error;
  Timer? _reintento;
  bool _activo = false; // false tras stop(): no reintentar

  /// Estado combinado de ph + estado + telemetria.
  final Map<String, dynamic> _merged = {};

  String get url {
    final h = _hostActual;
    if (h.contains('://')) return h;
    final r = ruta.isEmpty ? '' : (ruta.startsWith('/') ? ruta : '/$ruta');
    return 'ws://$h$r';
  }

  bool get enRespaldo => _hostActual != host;

  @override
  Stream<Telemetria> get telemetria => _tele.stream;
  @override
  Stream<EventoDispositivo> get eventos => _ev.stream;
  @override
  Stream<HardwareEstado> get hardware => _hw.stream;
  @override
  Stream<ConexionEstado> get conexion => _con.stream;
  @override
  String? get errorConexion => _error;
  @override
  String get descripcion =>
      'MQTT $url (puerto $port)${enRespaldo ? ' · IP alterna' : ''}';
  @override
  bool get simulado => false;

  @override
  Future<void> start() async {
    await stop();
    _activo = true;
    await _conectar();
  }

  void _programarReintento() {
    _reintento?.cancel();
    if (!_activo) return;
    _iHost = (_iHost + 1) % _hosts.length; // alterna principal ↔ respaldo
    _reintento = Timer(DeviceConst.mqttReintento, () {
      if (_activo) _conectar();
    });
  }

  Future<void> _conectar() async {
    if (!DeviceConst.mqttHabilitado) {
      _error = 'MQTT desactivado: el firmware aún no existe. '
          'Actívalo con DeviceConst.mqttHabilitado = true.';
      _con.add(ConexionEstado.desconectado);
      return;
    }
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
      _error = 'No se pudo conectar a $url:$port. '
          '${_hosts.length > 1 ? 'Probando también ${_hosts.where((h) => h != _hostActual).join(', ')}. ' : ''}'
          'Reintentando cada ${DeviceConst.mqttReintento.inSeconds} s…';
      client.disconnect();
      _client = null;
      _con.add(ConexionEstado.error);
      _programarReintento();
      return;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _error = 'El broker rechazó la conexión '
          '(${client.connectionStatus?.returnCode})';
      client.disconnect();
      _client = null;
      _con.add(ConexionEstado.error);
      _programarReintento();
      return;
    }
    _error = null;

    for (final t in topics.entrada) {
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

  Map<String, dynamic>? _json(String t) {
    try {
      final v = jsonDecode(t);
      return v is Map ? v.cast<String, dynamic>() : null;
    } catch (_) {
      return null; // JSON inválido: se ignora
    }
  }

  void _onMensaje(String topic, String text) {
    final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final t = text.trim();

    if (topic == topics.evento) {
      final m = _json(t);
      final e = m == null ? null : EventoDispositivo.fromMap(m);
      if (e != null && !_ev.isClosed) _ev.add(e);
      return;
    }
    if (topic == topics.hardware) {
      final m = _json(t);
      if (m != null && !_hw.isClosed) _hw.add(HardwareEstado.fromMap(m));
      return;
    }

    if (topic == topics.ph) {
      final v = double.tryParse(t);
      if (v == null) return;
      _merged['ph'] = v;
      _merged['ts'] = ahora;
    } else if (topic == topics.estado) {
      _merged['estado'] = t;
    } else if (topic == topics.telemetria) {
      final m = _json(t);
      if (m == null) return;
      _merged.addAll(m);
      if (!m.containsKey('ts')) _merged['ts'] = ahora;
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
    _activo = false;
    _reintento?.cancel();
    _reintento = null;
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
