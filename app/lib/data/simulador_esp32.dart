// SimuladorESP32: imita al firmware real para desarrollar sin hardware.
// Sus reglas son la REFERENCIA de comportamiento para el firmware:
//
//  dosificar  · pH ≤ umbral + 0.05            → RECHAZO "El pH ya está por debajo del objetivo"
//             · ácido < lo de un pulso        → RECHAZO "Ácido insuficiente"
//             · válido → INICIO; ciclos RELE_ON → (pulso) → RELE_OFF → MEZCLA (3 s)
//               → baja el pH → repite hasta el umbral → FIN con resumen
//  detener    · RELE_OFF inmediato, estado IDLE, limpia el error, ACK
//  p <ms>     · ms > 1500 → RECHAZO "Pulso mayor al máximo permitido (1500 ms)"
//             · si no → RELE_ON y RELE_OFF tras <ms>
//  c <pH>     · ajusta el offset → ACK
//  a <ml>     · inventario de ácido → ACK
//  test_buzzer <inicio|fin|error> → BUZZER
//  test_led <r> <g> <b>           → LED
//  Fallas críticas activas → dosificar / p se RECHAZAN con el motivo.
//  Ácido: ~33 mL por segundo de bomba.
//  Cada orden se responde con 150–400 ms de retardo (como la red).
import 'dart:async';
import 'dart:math' as math;

import '../core/device_constants.dart';
import '../core/fallas.dart';
import 'data_source.dart';
import 'models.dart';

class SimuladorESP32 implements DataSource {
  SimuladorESP32({this.nodo = DeviceConst.nodoPorDefecto, this.ubicacion = 'Mesa 4'});

  final String nodo;
  final String ubicacion;

  static const _tick = Duration(milliseconds: 250); // 4 lecturas/s
  static const _phBase = 7.2;
  static const _sHatReal = 0.06; // pH que baja por mL (varía ±20 %)

  final _tele = StreamController<Telemetria>.broadcast();
  final _ev = StreamController<EventoDispositivo>.broadcast();
  final _hw = StreamController<HardwareEstado>.broadcast();
  final _con = StreamController<ConexionEstado>.broadcast();
  final _rnd = math.Random();
  Timer? _timer;

  // Estado "del firmware"
  double _phReal = _phBase;
  double _offset = 0.0;
  String? _calibFecha;
  CtrlEstado _estado = CtrlEstado.idle;
  double _umbral = 6.60;
  double _acido = DeviceConst.acidoInicialMl;
  double _mlSesion = 0;
  int _pulsos = 0;
  double? _sHat;
  String? _errorMsg;
  double? _errorFinal;
  Resumen? _resumen;
  DateTime? _inicio;
  bool _rele = false;
  List<int>? _ledPrueba;
  DateTime? _ledPruebaHasta;
  bool _buzzer = false;
  SensorEstado _sensor = SensorEstado.ok;

  /// Fallas simuladas activas (códigos de Fallas). "detener" las limpia.
  final Set<String> _fallasSim = {};

  /// Temperatura del agua simulada (°C). Se cambia desde el panel Dispositivos.
  double temperaturaC = 22.0;

  /// Cada "detener"/falla incrementa esto e invalida los ciclos en curso.
  int _gen = 0;

  @override
  Stream<Telemetria> get telemetria => _tele.stream;
  @override
  Stream<EventoDispositivo> get eventos => _ev.stream;
  @override
  Stream<HardwareEstado> get hardware => _hw.stream;
  @override
  Stream<ConexionEstado> get conexion => _con.stream;
  @override
  String? get errorConexion => null;
  @override
  String get descripcion => 'Simulador ESP32';
  @override
  bool get simulado => true;

  bool get _activo => _estado == CtrlEstado.pulso || _estado == CtrlEstado.mezcla;
  double get _ph => _phReal + _offset;

  @override
  Future<void> start() async {
    _timer?.cancel();
    _con.add(ConexionEstado.conectado);
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  @override
  Future<void> stop() async {
    _gen++;
    _timer?.cancel();
    _timer = null;
    _rele = false;
    _con.add(ConexionEstado.desconectado);
  }

  void _onTick() {
    if (!_activo) {
      // Para repetir la demo, el agua "regresa" a 7.2 poco a poco.
      _phReal += (_phBase - _phReal) * 0.002;
    }
    _emitir();
  }

  // ---------------- Salidas ----------------

  List<int> get _ledActual {
    if (_ledPrueba != null &&
        _ledPruebaHasta != null &&
        DateTime.now().isBefore(_ledPruebaHasta!)) {
      return _ledPrueba!;
    }
    return switch (_estado) {
      CtrlEstado.idle => const [0, 255, 0],
      CtrlEstado.pulso => const [0, 180, 255],
      CtrlEstado.mezcla => const [255, 200, 0],
      CtrlEstado.error => const [255, 0, 0],
    };
  }

  void _emitir() {
    if (_tele.isClosed) return;
    final ph = _ph + (_rnd.nextDouble() - 0.5) * 0.03;
    _tele.add(Telemetria(
      ts: _ahoraTs,
      ph: ph,
      conectado: true,
      nodo: nodo,
      ubicacion: ubicacion,
      mv: 1784 + (6.84 - ph) * 177, // valor crudo ilustrativo
      sensor: _sensor,
      estado: _estado,
      errorMsg: _errorMsg,
      bomba: _rele,
      umbral: _umbral,
      mlDosificados: double.parse(_mlSesion.toStringAsFixed(1)),
      acidoRestanteMl: double.parse(_acido.toStringAsFixed(1)),
      pulsos: _pulsos,
      sHat: _sHat,
      errorFinal: _errorFinal,
      tempC: temperaturaC + (_rnd.nextDouble() - 0.5) * 0.1,
      tempSupuesta: false,
      calib: Calib(offset: _offset, fecha: _calibFecha),
      resumen: _resumen,
    ));
    _hw.add(HardwareEstado(
      rele: _rele,
      led: _ledActual,
      buzzer: _buzzer ? 'sonando' : 'silencio',
      sensor: _sensor,
      modulos: {
        'XN03': !_fallasSim.contains(Fallas.ledNoResponde),
        'XN13': !_fallasSim.contains(Fallas.releNoResponde),
        'XN44': !_fallasSim.contains(Fallas.buzzerNoResponde),
      },
      fallas: _fallasActivas,
    ));
  }

  void _evento(TipoEvento t, {String? detalle, String? cmd}) {
    if (_ev.isClosed) return;
    _ev.add(EventoDispositivo(ts: _ahoraTs, tipo: t, detalle: detalle, cmd: cmd));
  }

  int get _ahoraTs => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<void> _retardoRed() => Future.delayed(Duration(
      milliseconds: DeviceConst.retardoRedMinMs +
          _rnd.nextInt(
              DeviceConst.retardoRedMaxMs - DeviceConst.retardoRedMinMs + 1)));

  // ---------------- Entradas ----------------

  @override
  Future<void> enviarUmbral(double ph) async {
    await _retardoRed();
    if (ph < DeviceConst.umbralMin || ph > DeviceConst.umbralMax) {
      _evento(TipoEvento.rechazo,
          detalle: 'Umbral fuera de rango (4.5–7.0)', cmd: 'umbral $ph');
      return;
    }
    _umbral = ph;
    _emitir();
  }

  @override
  Future<void> enviarCmd(String cmd) async {
    await _retardoRed();
    final partes = cmd.trim().split(RegExp(r'\s+'));
    final orden = partes.first;
    final arg = partes.length > 1 ? partes[1] : null;

    switch (orden) {
      case DeviceConst.cmdDosificar:
        _dosificar(cmd);
      case DeviceConst.cmdDetener:
        _detener(cmd);
      case DeviceConst.cmdPulso:
        await _pulsoManual(cmd, int.tryParse(arg ?? ''));
      case DeviceConst.cmdCalibrar:
        final ref = double.tryParse(arg ?? '');
        if (ref == null || ref <= 0 || ref >= 14) {
          _evento(TipoEvento.rechazo, detalle: 'pH de referencia inválido', cmd: cmd);
        } else {
          _offset = ref - _phReal;
          final n = DateTime.now();
          _calibFecha = '${n.year}-${_2(n.month)}-${_2(n.day)}T'
              '${_2(n.hour)}:${_2(n.minute)}';
          _evento(TipoEvento.ack,
              detalle: 'Calibrado con pH ${ref.toStringAsFixed(2)}', cmd: cmd);
        }
      case DeviceConst.cmdAcido:
        final ml = double.tryParse(arg ?? '');
        if (ml == null || ml < 0) {
          _evento(TipoEvento.rechazo, detalle: 'Cantidad inválida', cmd: cmd);
        } else {
          _acido = ml;
          _evento(TipoEvento.ack,
              detalle: 'Ácido: ${ml.toStringAsFixed(0)} mL', cmd: cmd);
        }
      case DeviceConst.cmdTestBuzzer:
        if (!const ['inicio', 'fin', 'error'].contains(arg)) {
          _evento(TipoEvento.rechazo, detalle: 'Secuencia desconocida', cmd: cmd);
        } else {
          _buzzer = true;
          _evento(TipoEvento.buzzer, detalle: arg, cmd: cmd);
          Future.delayed(const Duration(milliseconds: 700), () => _buzzer = false);
        }
      case DeviceConst.cmdTestLed:
        final rgb = partes.skip(1).map(int.tryParse).toList();
        if (rgb.length != 3 || rgb.any((v) => v == null || v < 0 || v > 255)) {
          _evento(TipoEvento.rechazo, detalle: 'Color inválido (0–255)', cmd: cmd);
        } else {
          _ledPrueba = rgb.cast<int>();
          _ledPruebaHasta = DateTime.now().add(const Duration(seconds: 5));
          _evento(TipoEvento.led, detalle: rgb.join(' '), cmd: cmd);
        }
      default:
        _evento(TipoEvento.rechazo, detalle: 'Orden desconocida: $orden', cmd: cmd);
    }
    _emitir();
  }

  /// Fallas activas: las simuladas + las de inventario (automáticas).
  List<FallaHw> get _fallasActivas {
    final codigos = {..._fallasSim};
    if (_acido < _mlDe(40)) {
      codigos.add(Fallas.acidoAgotado);
    } else if (_acido < DeviceConst.acidoBajoMl) {
      codigos.add(Fallas.acidoBajo);
    }
    return [
      for (final c in codigos)
        FallaHw(
            codigo: c,
            severidad: Fallas.info(c).severidad,
            modulo: Fallas.info(c).modulo),
    ];
  }

  FallaHw? get _primeraCritica {
    for (final f in _fallasActivas) {
      // El ácido agotado ya tiene su propio rechazo ("Ácido insuficiente").
      if (f.critica && f.codigo != Fallas.acidoAgotado) return f;
    }
    return null;
  }

  /// Botón de desarrollo: la sonda deja de responder.
  void simularFallaSensor() => simularFalla(Fallas.sensorPhSinRespuesta);

  /// Botón de desarrollo: activa una falla de hardware.
  /// Las críticas apagan el relé y pasan a ERROR, como el firmware real.
  void simularFalla(String codigo) {
    _fallasSim.add(codigo);
    final info = Fallas.info(codigo);
    if (codigo == Fallas.sensorPhSinRespuesta ||
        codigo == Fallas.sensorPhDesconectado) {
      _sensor = SensorEstado.sinRespuesta;
    } else if (codigo == Fallas.sensorPhFueraRango) {
      _sensor = SensorEstado.fueraRango;
    }
    if (info.severidad == Severidad.critica) {
      _gen++;
      if (_rele) {
        _rele = false;
        _evento(TipoEvento.releOff, detalle: 'Paro por falla: ${info.titulo}');
      }
      _estado = CtrlEstado.error;
      _errorMsg = info.titulo;
      _inicio = null;
      _evento(TipoEvento.error, detalle: info.titulo);
    }
    _emitir();
  }

  /// Botón de desarrollo: quita todas las fallas simuladas.
  void limpiarFallas() {
    _fallasSim.clear();
    _sensor = SensorEstado.ok;
    if (_estado == CtrlEstado.error) {
      _estado = CtrlEstado.idle;
      _errorMsg = null;
    }
    _emitir();
  }

  // ---------------- Lógica de dosificación ----------------

  double _mlDe(int ms) => DeviceConst.mlPorSegundoBomba * ms / 1000;

  /// Pulso proporcional a la distancia, apunta al 60 % de lo necesario.
  int _msPulso() {
    final dist = math.max(0.0, _ph - _umbral);
    final mlNecesarios = dist / _sHatReal;
    final ms = mlNecesarios / DeviceConst.mlPorSegundoBomba * 1000 * 0.6;
    return ms.clamp(40, 150).round();
  }

  void _dosificar(String cmd) {
    final falla = _primeraCritica;
    if (falla != null && _sensor == SensorEstado.ok) {
      _evento(TipoEvento.rechazo,
          detalle: 'Falla de hardware: ${falla.info.titulo}', cmd: cmd);
      return;
    }
    if (_sensor != SensorEstado.ok) {
      _evento(TipoEvento.rechazo, detalle: 'Sensor sin respuesta', cmd: cmd);
      return;
    }
    if (_activo) {
      _evento(TipoEvento.rechazo,
          detalle: 'Ya hay una dosificación en curso', cmd: cmd);
      return;
    }
    if (_ph <= _umbral + DeviceConst.margenRechazo) {
      _evento(TipoEvento.rechazo,
          detalle: 'El pH ya está por debajo del objetivo', cmd: cmd);
      return;
    }
    if (_acido < _mlDe(_msPulso())) {
      _evento(TipoEvento.rechazo, detalle: 'Ácido insuficiente', cmd: cmd);
      return;
    }
    final gen = ++_gen;
    _errorMsg = null;
    _errorFinal = null;
    _mlSesion = 0;
    _pulsos = 0;
    _inicio = DateTime.now();
    _estado = CtrlEstado.pulso;
    _evento(TipoEvento.inicio,
        detalle: 'Umbral ${_umbral.toStringAsFixed(2)}', cmd: cmd);
    _emitir();
    _ciclo(gen);
  }

  Future<void> _ciclo(int gen) async {
    while (gen == _gen) {
      final ms = _msPulso();
      final ml = _mlDe(ms);
      if (_acido < ml) {
        _estado = CtrlEstado.idle;
        _inicio = null;
        _evento(TipoEvento.rechazo, detalle: 'Ácido insuficiente');
        _emitir();
        return;
      }
      // Pulso
      _pulsos++;
      _estado = CtrlEstado.pulso;
      _rele = true;
      _evento(TipoEvento.releOn, detalle: 'Pulso de $ms ms');
      _emitir();
      await Future.delayed(Duration(milliseconds: ms));
      if (gen != _gen) return;
      _rele = false;
      _acido = math.max(0.0, _acido - ml);
      _mlSesion += ml;
      _evento(TipoEvento.releOff);
      _estado = CtrlEstado.mezcla;
      _emitir();

      // Mezcla: el pH baja gradualmente
      final caida = _sHatReal * ml * (0.8 + 0.4 * _rnd.nextDouble());
      final pasos = DeviceConst.mezclaMs ~/ _tick.inMilliseconds;
      for (var i = 0; i < pasos; i++) {
        await Future.delayed(_tick);
        if (gen != _gen) return;
        _phReal -= caida / pasos;
      }
      _sHat = double.parse((caida / ml).toStringAsFixed(3));

      if (_ph <= _umbral + DeviceConst.tolerancia) {
        _terminar();
        return;
      }
    }
  }

  void _terminar() {
    final ph = _ph;
    _errorFinal = double.parse((ph - _umbral).toStringAsFixed(2));
    _resumen = Resumen(
      umbral: _umbral,
      phFinal: double.parse(ph.toStringAsFixed(2)),
      error: _errorFinal,
      pulsos: _pulsos,
      ml: double.parse(_mlSesion.toStringAsFixed(1)),
      segundos: _inicio == null ? 0 : DateTime.now().difference(_inicio!).inSeconds,
    );
    _estado = CtrlEstado.idle;
    _inicio = null;
    _emitir(); // telemetría con el resumen antes del evento
    _evento(TipoEvento.fin,
        detalle: 'Objetivo alcanzado: pH ${ph.toStringAsFixed(2)} '
            '(error ±${_errorFinal!.abs().toStringAsFixed(2)})');
  }

  void _detener(String cmd) {
    _gen++;
    if (_rele) {
      _rele = false;
      _evento(TipoEvento.releOff, detalle: 'Paro inmediato');
    }
    _estado = CtrlEstado.idle;
    _errorMsg = null;
    // En el simulador, detener "repara" el hardware simulado.
    _sensor = SensorEstado.ok;
    _fallasSim.clear();
    _inicio = null;
    _evento(TipoEvento.ack, detalle: 'Bomba detenida', cmd: cmd);
  }

  Future<void> _pulsoManual(String cmd, int? ms) async {
    if (ms == null || ms <= 0) {
      _evento(TipoEvento.rechazo, detalle: 'Duración inválida', cmd: cmd);
      return;
    }
    if (ms > DeviceConst.pulsoMaxMs) {
      _evento(TipoEvento.rechazo,
          detalle: 'Pulso mayor al máximo permitido (${DeviceConst.pulsoMaxMs} ms)',
          cmd: cmd);
      return;
    }
    if (_activo) {
      _evento(TipoEvento.rechazo,
          detalle: 'Hay una dosificación en curso', cmd: cmd);
      return;
    }
    for (final c in const [Fallas.bombaDesconectada, Fallas.releNoResponde, Fallas.busI2c]) {
      if (_fallasSim.contains(c)) {
        _evento(TipoEvento.rechazo,
            detalle: 'Falla de hardware: ${Fallas.info(c).titulo}', cmd: cmd);
        return;
      }
    }
    final ml = _mlDe(ms);
    if (_acido < ml) {
      _evento(TipoEvento.rechazo, detalle: 'Ácido insuficiente', cmd: cmd);
      return;
    }
    final gen = _gen;
    _rele = true;
    _evento(TipoEvento.releOn, detalle: 'Pulso manual de $ms ms', cmd: cmd);
    _emitir();
    await Future.delayed(Duration(milliseconds: ms));
    if (gen != _gen) return; // "detener" ya apagó el relé
    _rele = false;
    _acido = math.max(0.0, _acido - ml);
    _evento(TipoEvento.releOff, detalle: 'Pulso manual terminado');
  }

  static String _2(int v) => v.toString().padLeft(2, '0');
}
