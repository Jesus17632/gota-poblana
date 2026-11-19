// Estado central de la app. La UI lo escucha; nunca habla con la fuente
// de datos directamente. Regla: la app NO da por hecho que algo ocurrió;
// solo refleja los eventos y el estado que reporta el ESP32 (o el simulador).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/chem.dart';
import '../core/device_constants.dart';
import '../core/fallas.dart';
import '../data/data_source.dart';
import '../data/models.dart';
import '../data/mqtt_source.dart';
import '../data/simulador_esp32.dart';
import '../services/sonidos.dart';
import 'settings.dart';

enum TipoAviso { inicio, fin, error, fueraNorma, rechazo, advertencia, info }

class Aviso {
  final TipoAviso tipo;
  final String mensaje;
  const Aviso(this.tipo, this.mensaje);
}

/// Entrada del "Registro de eventos" (vista técnico).
class RegistroItem {
  final DateTime t;
  final String tipo; // INICIO, FIN, RECHAZO, ..., "→ ORDEN", "SIN RESPUESTA"
  final String detalle;
  const RegistroItem(this.t, this.tipo, this.detalle);
}

enum Rol { ciudadano, tecnico }

class AppState extends ChangeNotifier {
  AppState(this._prefs, {Sonidos? sonidos}) : _sonidos = sonidos ?? Sonidos() {
    settings.load(_prefs);
    _cargarHistorial();
  }

  final SharedPreferences _prefs;
  final Sonidos _sonidos;
  final Settings settings = Settings();

  static const _uiTick = Duration(milliseconds: 500); // refresco a 2 Hz
  static const _cadaLectura = Duration(seconds: 2);
  static const _detalleReciente = Duration(hours: 1);
  static const _retencion = Duration(days: 7);
  static const _maxRegistro = 300;
  static const _kHist = 'historial.v1';
  static const _kSes = 'sesiones.v1';

  DataSource? _source;
  final List<StreamSubscription> _subs = [];
  Timer? _uiTimer;
  Timer? _saveTimer;
  bool _disposed = false;

  Rol rol = Rol.ciudadano;
  bool get esTecnico => rol == Rol.tecnico;

  ConexionEstado conexion = ConexionEstado.desconectado;
  String? get errorConexion => _source?.errorConexion;
  String get fuenteDescripcion => _source?.descripcion ?? '—';
  bool get simulado => _source?.simulado ?? false;

  Telemetria? ultimo;
  DateTime? recibido;
  HardwareEstado? hw;
  DateTime? hwRecibido;
  bool rele = false; // último estado reportado del relé
  DateTime get ahora => DateTime.now();

  final List<Lectura> historial = [];
  final List<Resumen> sesiones = [];
  final List<RegistroItem> registro = []; // más reciente primero
  DateTime? inicioSesion;
  DateTime? finSesion;
  DateTime? ultimaAlerta;

  final _avisos = StreamController<Aviso>.broadcast();
  Stream<Aviso> get avisos => _avisos.stream;

  /// Órdenes enviadas que aún no tienen respuesta del dispositivo.
  final Map<String, Timer> _pendientes = {};
  bool enviando(String cmd) => _pendientes.containsKey(cmd);
  bool get hayPendientes => _pendientes.isNotEmpty;

  DateTime? _ultimaGuardada;
  String? _ultimoResumen;
  bool? _enNormaPrevio;
  String? _marcador; // evento a guardar con la siguiente lectura

  // ---------- Ciclo de vida ----------

  Future<void> iniciar() async {
    _uiTimer = Timer.periodic(_uiTick, (_) => _notificar());
    _saveTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _guardarHistorial());
    await _conectarFuente();
  }

  Future<void> _conectarFuente() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final t in _pendientes.values) {
      t.cancel();
    }
    _pendientes.clear();
    await _source?.stop();

    final src = settings.fuente == FuenteDatos.simulador
        ? SimuladorESP32(nodo: settings.nodo)
        : MqttSource(
            host: settings.mqttHost,
            port: settings.mqttPort,
            ruta: settings.mqttRuta,
            nodo: settings.nodo,
          );
    _source = src;
    _subs.addAll([
      src.conexion.listen((c) {
        conexion = c;
        _notificar();
      }),
      src.telemetria.listen(_onTelemetria),
      src.eventos.listen(_onEvento),
      src.hardware.listen(_onHardware),
    ]);
    await src.start();
  }

  Future<void> reconectar() async {
    await guardarSettings();
    ultimo = null;
    recibido = null;
    hw = null;
    rele = false;
    await _conectarFuente();
  }

  Future<void> guardarSettings() async {
    await settings.save(_prefs);
    _notificar();
  }

  void _notificar() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _uiTimer?.cancel();
    _saveTimer?.cancel();
    for (final t in _pendientes.values) {
      t.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    _source?.stop();
    _sonidos.dispose();
    _guardarHistorial();
    _avisos.close();
    super.dispose();
  }

  // ---------- Entrada: telemetría ----------

  void _onTelemetria(Telemetria t) {
    final previo = ultimo;
    final now = DateTime.now();
    ultimo = t;
    recibido = now;
    if (t.bomba != null) rele = t.bomba!;

    final sensorOk = (t.sensor ?? SensorEstado.ok) == SensorEstado.ok;
    if (sensorOk) {
      final enNorma = nomStatus(t.ph) == NomStatus.enRango;
      if (!enNorma) ultimaAlerta = now;
      if (_enNormaPrevio == true && !enNorma) {
        final quiere =
            esTecnico ? settings.notifFueraNorma : settings.notifAlertas;
        _log('FUERA_NORMA', 'pH ${t.ph.toStringAsFixed(2)}');
        if (quiere) {
          _avisar(TipoAviso.fueraNorma,
              'pH ${t.ph.toStringAsFixed(2)} fuera del rango de la norma');
        }
      }
      _enNormaPrevio = enNorma;
    }

    final r = t.resumen;
    if (r != null && r.clave != _ultimoResumen) {
      if (_ultimoResumen != null || previo != null) {
        sesiones.insert(0, r.conRegistro(now));
      }
      _ultimoResumen = r.clave;
    }

    final marcador = _marcador;
    if (sensorOk &&
        (marcador != null ||
            _ultimaGuardada == null ||
            now.difference(_ultimaGuardada!) >= _cadaLectura)) {
      historial.add(Lectura(
          t: now, ph: t.ph, hoclPct: hoclActual, evento: marcador));
      _ultimaGuardada = now;
      _marcador = null;
    }
  }

  void _onHardware(HardwareEstado h) {
    final antes = {for (final f in hw?.fallas ?? const <FallaHw>[]) f.codigo};
    hw = h;
    hwRecibido = DateTime.now();
    if (h.rele != null) rele = h.rele!;

    final ahora = {for (final f in h.fallas) f.codigo};
    for (final f in h.fallas.where((f) => !antes.contains(f.codigo))) {
      final txt = f.info.titulo + (f.detalle == null ? '' : ' (${f.detalle})');
      _log('FALLA', '$txt [${f.codigo}]');
      if (f.critica) {
        _alerta(TipoAviso.error, 'Falla de hardware: $txt', Tono.error,
            settings.notifError);
      } else if (esTecnico) {
        _avisar(TipoAviso.advertencia, txt);
      }
    }
    for (final c in antes.difference(ahora)) {
      _log('FALLA RESUELTA', '${Fallas.info(c).titulo} [$c]');
    }
  }

  /// Fallas de hardware activas, críticas primero.
  List<FallaHw> get fallas {
    final l = [...?hw?.fallas];
    l.sort((a, b) => (a.critica ? 0 : 1).compareTo(b.critica ? 0 : 1));
    return l;
  }

  bool get hayFallasCriticas => hw?.hayCriticas ?? false;

  // ---------- Entrada: eventos ----------

  void _onEvento(EventoDispositivo e) {
    _resolverPendiente(e);
    final detalle = e.detalle ?? '';
    _log(tipoEventoWire(e.tipo), [
      if (detalle.isNotEmpty) detalle,
      if (e.cmd != null) '(${e.cmd})',
    ].join(' '));

    final now = DateTime.now();
    switch (e.tipo) {
      case TipoEvento.inicio:
        inicioSesion = now;
        finSesion = null;
        _marcador = 'inicio';
        _alerta(TipoAviso.inicio, 'Dosificación iniciada', Tono.inicio,
            settings.notifInicio);
      case TipoEvento.fin:
        finSesion = now;
        _marcador = 'fin';
        _alerta(TipoAviso.fin, _textoFin(e), Tono.fin, settings.notifFin);
      case TipoEvento.rechazo:
        _alerta(TipoAviso.rechazo,
            'Rechazado: ${detalle.isEmpty ? 'sin motivo' : detalle}',
            Tono.error, true);
      case TipoEvento.error:
        if (inicioSesion != null && finSesion == null) finSesion = now;
        _alerta(TipoAviso.error,
            'Error: ${detalle.isEmpty ? 'sin detalle' : detalle}',
            Tono.error, settings.notifError);
      case TipoEvento.releOn:
        rele = true;
        if (inicioSesion != null && finSesion == null) _marcador = 'pulso';
      case TipoEvento.releOff:
        rele = false;
      case TipoEvento.buzzer:
        // En modo simulado, el "buzzer" suena en la app.
        final tono = tonoDe(e.detalle);
        if (simulado && tono != null && settings.sonidos) _sonidos.tocar(tono);
      case TipoEvento.led:
        break;
      case TipoEvento.ack:
        if (e.cmd == Cmd.detener) {
          if (inicioSesion != null && finSesion == null) {
            finSesion = now;
            _marcador = 'fin';
          }
          _avisar(TipoAviso.info, detalle.isEmpty ? 'Bomba detenida' : detalle);
        } else if (detalle.isNotEmpty) {
          _avisar(TipoAviso.info, detalle);
        }
    }
    _notificar();
  }

  String _textoFin(EventoDispositivo e) {
    final r = ultimo?.resumen;
    if (r?.phFinal != null && r?.error != null) {
      return 'Objetivo alcanzado: pH ${r!.phFinal!.toStringAsFixed(2)} '
          '(error ±${r.error!.abs().toStringAsFixed(2)})';
    }
    return (e.detalle?.isNotEmpty ?? false) ? e.detalle! : 'Objetivo alcanzado';
  }

  void _alerta(TipoAviso tipo, String msg, Tono tono, bool visible) {
    if (visible) _avisar(tipo, msg);
    if (settings.sonidos) _sonidos.tocar(tono);
    if (settings.vibracion) _sonidos.vibrar(tono);
  }

  void _avisar(TipoAviso tipo, String msg) {
    if (!_avisos.isClosed) _avisos.add(Aviso(tipo, msg));
  }

  void _log(String tipo, String detalle) {
    registro.insert(0, RegistroItem(DateTime.now(), tipo, detalle));
    if (registro.length > _maxRegistro) registro.removeLast();
  }

  /// Respuesta a una orden: por "cmd" exacto, o la más antigua pendiente si
  /// el firmware no incluyó "cmd".
  void _resolverPendiente(EventoDispositivo e) {
    if (_pendientes.isEmpty) return;
    const respuestas = {
      TipoEvento.inicio,
      TipoEvento.rechazo,
      TipoEvento.ack,
      TipoEvento.releOn,
      TipoEvento.buzzer,
      TipoEvento.led,
      TipoEvento.error,
    };
    if (!respuestas.contains(e.tipo)) return;
    final c = e.cmd?.trim();
    final clave = (c != null && _pendientes.containsKey(c))
        ? c
        : (c == null ? _pendientes.keys.first : null);
    if (clave != null) _pendientes.remove(clave)?.cancel();
  }

  // ---------- Derivados ----------

  bool get hayDatos => ultimo != null && recibido != null;
  bool get sinConexion => conexion != ConexionEstado.conectado;
  bool get datosViejos =>
      recibido == null || isStale(recibido!, DateTime.now());
  bool get sensorOk =>
      ultimo != null && (ultimo!.sensor ?? SensorEstado.ok) == SensorEstado.ok;
  CtrlEstado get estadoCtrl => ultimo?.estado ?? CtrlEstado.idle;
  bool get dosificando =>
      estadoCtrl == CtrlEstado.pulso || estadoCtrl == CtrlEstado.mezcla;

  /// El XC01 está en línea si hay conexión y datos frescos.
  bool get xc01EnLinea => !sinConexion && !datosViejos;

  ({double tempC, bool supuesta}) get temperatura => temperaturaEfectiva(
        sensorC: ultimo?.tempC,
        sensorSupuesta: ultimo?.tempSupuesta,
        configC: settings.tempAguaC,
        usarSensor: settings.usarSensorTemp,
      );

  double? get hoclActual {
    final t = ultimo;
    if (t == null) return null;
    return t.hoclPct ?? hoclPct(t.ph, temperatura.tempC);
  }

  String get ubicacion {
    if (settings.ubicacion.trim().isNotEmpty) return settings.ubicacion;
    return ultimo?.ubicacion ?? '—';
  }

  String get nodo => ultimo?.nodo ?? settings.nodo;

  double get pHRecomendado => recommendedPh(temperatura.tempC);

  // ---------- Simulador (desarrollo) ----------

  SimuladorESP32? get _sim =>
      _source is SimuladorESP32 ? _source as SimuladorESP32 : null;

  double? get temperaturaSimulada => _sim?.temperaturaC;
  set temperaturaSimulada(double? v) {
    if (v != null) _sim?.temperaturaC = v;
    _notificar();
  }

  void simularFallaSensor() {
    _exigirTecnico();
    _sim?.simularFallaSensor();
  }

  void simularFalla(String codigo) {
    _exigirTecnico();
    _sim?.simularFalla(codigo);
  }

  void limpiarFallasSimuladas() {
    _exigirTecnico();
    _sim?.limpiarFallas();
  }

  // ---------- Roles ----------

  bool entrarTecnico(String pin) {
    if (pin.trim() != settings.pin) return false;
    rol = Rol.tecnico;
    _notificar();
    return true;
  }

  void salirTecnico() {
    rol = Rol.ciudadano;
    _notificar();
  }

  // ---------- Órdenes (solo técnico) ----------

  void _exigirTecnico() {
    if (!esTecnico) {
      throw StateError('Solo el técnico puede enviar órdenes');
    }
  }

  /// Envía y marca como pendiente hasta recibir el evento de respuesta.
  Future<void> _orden(String cmd, {bool esperarRespuesta = true}) async {
    final s = _source;
    if (s == null) throw StateError('Sin fuente de datos');
    _log('→ ORDEN', cmd);
    if (esperarRespuesta) {
      _pendientes.remove(cmd)?.cancel();
      _pendientes[cmd] = Timer(DeviceConst.timeoutRespuesta, () {
        if (_pendientes.remove(cmd) == null) return;
        _log('SIN RESPUESTA', cmd);
        _alerta(TipoAviso.error, 'Sin respuesta del dispositivo ($cmd)',
            Tono.error, true);
        _notificar();
      });
    }
    _notificar();
    try {
      await s.enviarCmd(cmd);
    } catch (e) {
      _pendientes.remove(cmd)?.cancel();
      _log('ERROR ENVÍO', '$cmd: $e');
      _alerta(TipoAviso.error, 'No se pudo enviar: $e', Tono.error, true);
      _notificar();
      rethrow;
    }
  }

  Future<void> dosificar(double umbral) async {
    _exigirTecnico();
    final u = roundToStep(umbral, 0.01)
        .clamp(DeviceConst.umbralMin, DeviceConst.umbralMax)
        .toDouble();
    final s = _source;
    if (s == null) throw StateError('Sin fuente de datos');
    try {
      _log('→ UMBRAL', u.toStringAsFixed(2));
      await s.enviarUmbral(u);
    } catch (e) {
      _alerta(TipoAviso.error, 'No se pudo enviar el umbral: $e', Tono.error, true);
      rethrow;
    }
    await _orden(Cmd.dosificar);
  }

  Future<void> detener() async {
    _exigirTecnico();
    await _orden(Cmd.detener);
  }

  Future<void> calibrar(double phRef) async {
    _exigirTecnico();
    await _orden(Cmd.calibrar(phRef));
  }

  Future<void> rellenarAcido() async {
    _exigirTecnico();
    await _orden(Cmd.rellenarAcido(DeviceConst.acidoInicialMl.round()));
  }

  Future<void> probarBomba([int ms = DeviceConst.pulsoPruebaMs]) async {
    _exigirTecnico();
    await _orden(Cmd.pulso(ms));
  }

  Future<void> probarBuzzer(String tipo) async {
    _exigirTecnico();
    await _orden(Cmd.testBuzzer(tipo));
  }

  Future<void> probarLed(int r, int g, int b) async {
    _exigirTecnico();
    await _orden(Cmd.testLed(r, g, b));
  }

  // ---------- Historial ----------

  List<Lectura> lecturasDesde(DateTime desde, [DateTime? hasta]) => historial
      .where((l) =>
          !l.t.isBefore(desde) && (hasta == null || !l.t.isAfter(hasta)))
      .toList();

  void _compactar() {
    final now = DateTime.now();
    final limite = now.subtract(_detalleReciente);
    final corte = now.subtract(_retencion);
    final out = <Lectura>[];
    int? minutoPrevio;
    for (final l in historial) {
      if (l.t.isBefore(corte)) continue;
      if (l.t.isAfter(limite) || l.evento != null) {
        out.add(l);
        continue;
      }
      final minuto = l.t.millisecondsSinceEpoch ~/ 60000;
      if (minuto != minutoPrevio) {
        out.add(l);
        minutoPrevio = minuto;
      }
    }
    historial
      ..clear()
      ..addAll(out);
  }

  void _guardarHistorial() {
    try {
      _compactar();
      _prefs.setString(
          _kHist, jsonEncode(historial.map((l) => l.toMap()).toList()));
      _prefs.setString(_kSes,
          jsonEncode(sesiones.take(200).map((r) => r.toMap()).toList()));
    } catch (e) {
      debugPrint('No se pudo guardar el historial: $e');
    }
  }

  void _cargarHistorial() {
    try {
      final h = _prefs.getString(_kHist);
      if (h != null) {
        for (final v in jsonDecode(h) as List) {
          final l = Lectura.fromMap(v);
          if (l != null) historial.add(l);
        }
      }
      final s = _prefs.getString(_kSes);
      if (s != null) {
        for (final v in jsonDecode(s) as List) {
          final r = Resumen.fromMap(v);
          if (r != null) sesiones.add(r);
        }
      }
    } catch (e) {
      debugPrint('Historial dañado, se ignora: $e');
    }
  }

  String sesionesCsv() {
    final b = StringBuffer(
        'registrado,umbral,ph_final,error,pulsos,ml,segundos\n');
    String f(Object? v) => v?.toString() ?? '';
    for (final r in sesiones) {
      b.writeln([
        f(r.registrado?.toIso8601String()),
        f(r.umbral),
        f(r.phFinal),
        f(r.error),
        f(r.pulsos),
        f(r.ml),
        f(r.segundos),
      ].join(','));
    }
    return b.toString();
  }

  static ({double min, double max}) rangoPh(Iterable<Lectura> ls,
      {double? umbral}) {
    var lo = nomMin, hi = nomMax;
    for (final l in ls) {
      lo = math.min(lo, l.ph);
      hi = math.max(hi, l.ph);
    }
    if (umbral != null) lo = math.min(lo, umbral);
    return (min: (lo - 0.3).floorToDouble(), max: (hi + 0.3).ceilToDouble());
  }
}
