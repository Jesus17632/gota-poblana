// Estado central de la app. La UI lo escucha; nunca habla con la fuente
// de datos directamente.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/chem.dart';
import '../data/data_source.dart';
import '../data/models.dart';
import '../data/mqtt_source.dart';
import '../data/simulator_source.dart';
import 'settings.dart';

enum TipoAviso { inicio, fin, error, fueraNorma, rechazo, info }

class Aviso {
  final TipoAviso tipo;
  final String mensaje;
  const Aviso(this.tipo, this.mensaje);
}

enum Rol { ciudadano, tecnico }

class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    settings.load(_prefs);
    _cargarHistorial();
  }

  final SharedPreferences _prefs;
  final Settings settings = Settings();

  // Refresco de pantalla a 2 Hz aunque lleguen más lecturas.
  static const _uiTick = Duration(milliseconds: 500);
  // Una lectura al historial cada 2 s (los eventos se guardan siempre).
  static const _cadaLectura = Duration(seconds: 2);
  // Pasada 1 h, el historial se compacta a una lectura por minuto.
  static const _detalleReciente = Duration(hours: 1);
  static const _retencion = Duration(days: 7);
  static const _kHist = 'historial.v1';
  static const _kSes = 'sesiones.v1';

  DataSource? _source;
  StreamSubscription? _subTele;
  StreamSubscription? _subCon;
  Timer? _uiTimer;
  Timer? _saveTimer;
  Timer? _rechazoTimer;
  bool _disposed = false;

  Rol rol = Rol.ciudadano;
  bool get esTecnico => rol == Rol.tecnico;

  ConexionEstado conexion = ConexionEstado.desconectado;
  String? get errorConexion => _source?.errorConexion;
  String get fuenteDescripcion => _source?.descripcion ?? '—';

  Telemetria? ultimo;
  DateTime? recibido; // hora local de la última lectura
  DateTime get ahora => DateTime.now();

  final List<Lectura> historial = [];
  final List<Resumen> sesiones = [];
  DateTime? inicioSesion; // última vez que arrancó una dosificación
  DateTime? finSesion;
  DateTime? ultimaAlerta;

  final _avisos = StreamController<Aviso>.broadcast();
  Stream<Aviso> get avisos => _avisos.stream;

  DateTime? _ultimaGuardada;
  String? _ultimoResumen;
  bool? _enNormaPrevio;

  // ---------- Ciclo de vida ----------

  Future<void> iniciar() async {
    _uiTimer = Timer.periodic(_uiTick, (_) => _notificar());
    _saveTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _guardarHistorial());
    await _conectarFuente();
  }

  Future<void> _conectarFuente() async {
    await _subTele?.cancel();
    await _subCon?.cancel();
    await _source?.stop();
    final src = settings.fuente == FuenteDatos.simulador
        ? SimulatorSource(nodo: settings.nodo)
        : MqttSource(
            host: settings.mqttHost,
            port: settings.mqttPort,
            nodo: settings.nodo,
          );
    _source = src;
    _subCon = src.conexion.listen((c) {
      conexion = c;
      _notificar();
    });
    _subTele = src.telemetria.listen(_onTelemetria);
    await src.start();
  }

  /// Llamar después de cambiar fuente/host/puerto/nodo.
  Future<void> reconectar() async {
    await guardarSettings();
    ultimo = null;
    recibido = null;
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
    _rechazoTimer?.cancel();
    _subTele?.cancel();
    _subCon?.cancel();
    _source?.stop();
    _guardarHistorial();
    _avisos.close();
    super.dispose();
  }

  // ---------- Entrada de datos ----------

  void _onTelemetria(Telemetria t) {
    final previo = ultimo;
    final now = DateTime.now();
    ultimo = t;
    recibido = now;

    final estPrev = previo?.estado ?? CtrlEstado.idle;
    final est = t.estado ?? CtrlEstado.idle;
    final activoPrev =
        estPrev == CtrlEstado.pulso || estPrev == CtrlEstado.mezcla;
    final activo = est == CtrlEstado.pulso || est == CtrlEstado.mezcla;

    String? evento;
    if (!activoPrev && activo) {
      evento = 'inicio';
      inicioSesion = now;
      finSesion = null;
      _rechazoTimer?.cancel();
      if (settings.notifInicio) {
        _avisar(TipoAviso.inicio, 'Inició la dosificación');
      }
    } else if (activoPrev && !activo && est != CtrlEstado.error) {
      evento = 'fin';
      finSesion = now;
      if (settings.notifFin) {
        _avisar(TipoAviso.fin, 'Terminó la dosificación');
      }
    } else if (est == CtrlEstado.pulso && estPrev != CtrlEstado.pulso) {
      evento = 'pulso';
    }

    if (est == CtrlEstado.error && estPrev != CtrlEstado.error) {
      if (activoPrev) finSesion = now;
      _rechazoTimer?.cancel();
      if (settings.notifError) {
        _avisar(TipoAviso.error, 'Error: ${t.errorMsg ?? 'sin detalle'}');
      }
    }

    // Fuera de norma (solo cuenta con sensor OK)
    final sensorOk = (t.sensor ?? SensorEstado.ok) == SensorEstado.ok;
    if (sensorOk) {
      final enNorma = nomStatus(t.ph) == NomStatus.enRango;
      if (!enNorma) ultimaAlerta = now;
      if (_enNormaPrevio == true && !enNorma) {
        final quiere = esTecnico ? settings.notifFueraNorma : settings.notifAlertas;
        if (quiere) {
          _avisar(TipoAviso.fueraNorma,
              'pH ${t.ph.toStringAsFixed(2)} fuera del rango de la norma');
        }
      }
      _enNormaPrevio = enNorma;
    }

    // Resumen de sesión nuevo
    final r = t.resumen;
    if (r != null && r.clave != _ultimoResumen) {
      if (_ultimoResumen != null || previo != null) {
        sesiones.insert(0, r.conRegistro(now));
      }
      _ultimoResumen = r.clave;
    }

    // Historial
    if (evento != null ||
        _ultimaGuardada == null ||
        now.difference(_ultimaGuardada!) >= _cadaLectura) {
      if (sensorOk) {
        historial.add(Lectura(
          t: now,
          ph: t.ph,
          hoclPct: hoclActual,
          evento: evento,
        ));
        _ultimaGuardada = now;
      }
    }
    // La pantalla se actualiza con el timer de 2 Hz, no aquí.
  }

  void _avisar(TipoAviso tipo, String msg) {
    if (!_avisos.isClosed) _avisos.add(Aviso(tipo, msg));
  }

  // ---------- Derivados ----------

  bool get hayDatos => ultimo != null && recibido != null;
  bool get sinConexion => conexion != ConexionEstado.conectado;
  bool get datosViejos => recibido == null || isStale(recibido!, DateTime.now());
  bool get sensorOk =>
      ultimo != null && (ultimo!.sensor ?? SensorEstado.ok) == SensorEstado.ok;
  CtrlEstado get estadoCtrl => ultimo?.estado ?? CtrlEstado.idle;
  bool get dosificando =>
      estadoCtrl == CtrlEstado.pulso || estadoCtrl == CtrlEstado.mezcla;

  ({double tempC, bool supuesta}) get temperatura => temperaturaEfectiva(
        sensorC: ultimo?.tempC,
        sensorSupuesta: ultimo?.tempSupuesta,
        configC: settings.tempAguaC,
        usarSensor: settings.usarSensorTemp,
      );

  /// % HOCl: el del firmware si lo manda; si no, calculado.
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
    if (!esTecnico) throw StateError('Solo el técnico puede controlar la bomba');
  }

  Future<void> _enviar(Future<void> Function(DataSource s) f) async {
    final s = _source;
    if (s == null) throw StateError('Sin fuente de datos');
    try {
      await f(s);
    } catch (e) {
      _avisar(TipoAviso.error, 'No se pudo enviar: $e');
      rethrow;
    }
  }

  Future<void> dosificar(double umbral) async {
    _exigirTecnico();
    final u = roundToStep(umbral, 0.01).clamp(phMinUmbral, phMaxUmbral);
    await _enviar((s) => s.enviarUmbral(u.toDouble()));
    await _enviar((s) => s.enviarCmd(Cmd.dosificar));
    // Si el equipo no arranca en 4 s, se considera rechazado.
    _rechazoTimer?.cancel();
    _rechazoTimer = Timer(const Duration(seconds: 4), () {
      if (dosificando) return;
      final t = ultimo;
      String motivo;
      if (t?.errorMsg != null && t!.errorMsg!.isNotEmpty) {
        motivo = t.errorMsg!;
      } else if (t != null && t.ph <= u) {
        motivo = 'el pH ya está por debajo del umbral';
      } else {
        motivo = 'el equipo no respondió';
      }
      _avisar(TipoAviso.rechazo, 'El equipo rechazó la orden: $motivo');
    });
  }

  Future<void> detener() async {
    _exigirTecnico();
    _rechazoTimer?.cancel();
    await _enviar((s) => s.enviarCmd(Cmd.detener));
  }

  Future<void> calibrar(double phRef) async {
    _exigirTecnico();
    await _enviar((s) => s.enviarCmd(Cmd.calibrar(phRef)));
    _avisar(TipoAviso.info, 'Calibración enviada (pH ${phRef.toStringAsFixed(2)})');
  }

  Future<void> rellenarAcido() async {
    _exigirTecnico();
    await _enviar((s) => s.enviarCmd(Cmd.rellenarAcido(100)));
    _avisar(TipoAviso.info, 'Ácido marcado como 100 mL');
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

  /// Para gráficos: rango Y que siempre incluye la banda de la norma.
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
