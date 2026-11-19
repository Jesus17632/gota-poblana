// Simulador local: permite hacer la demo sin hardware.
// pH ≈ 7.2 con ruido; "dosificar" corre PULSO → MEZCLA → … hasta el umbral.
import 'dart:async';
import 'dart:math' as math;

import 'data_source.dart';
import 'models.dart';

class SimulatorSource implements DataSource {
  SimulatorSource({this.nodo = 'nodo1', this.ubicacion = 'Mesa 4'});

  final String nodo;
  final String ubicacion;

  static const _tick = Duration(milliseconds: 250); // 4 lecturas/s
  static const _ticksPulso = 6; // 1.5 s con bomba encendida
  static const _ticksMezcla = 14; // 3.5 s mezclando
  static const _mlPorPulso = 1.2;
  static const _phBase = 7.2;
  static const _tolerancia = 0.03;

  final _tele = StreamController<Telemetria>.broadcast();
  final _con = StreamController<ConexionEstado>.broadcast();
  final _rnd = math.Random();
  Timer? _timer;

  double _phReal = _phBase;
  double _offset = 0.0;
  String? _calibFecha;
  CtrlEstado _estado = CtrlEstado.idle;
  double _umbral = 6.60;
  double _acido = 100.0;
  double _mlSesion = 0;
  int _pulsos = 0;
  double? _sHat;
  String? _errorMsg;
  double? _errorFinal;
  Resumen? _resumen;
  DateTime? _inicio;
  int _ticksFase = 0;
  double _bajadaPendiente = 0;
  double _phAntesMezcla = _phBase;

  @override
  Stream<Telemetria> get telemetria => _tele.stream;
  @override
  Stream<ConexionEstado> get conexion => _con.stream;
  @override
  String? get errorConexion => null;
  @override
  String get descripcion => 'Simulador';

  double get _phMedido => _phReal + _offset + (_rnd.nextDouble() - 0.5) * 0.03;

  @override
  Future<void> start() async {
    _timer?.cancel();
    _con.add(ConexionEstado.conectado);
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _con.add(ConexionEstado.desconectado);
  }

  void _onTick() {
    switch (_estado) {
      case CtrlEstado.idle:
      case CtrlEstado.error:
        // Para que la demo se pueda repetir, el agua "regresa" a 7.2 poco a poco.
        _phReal += (_phBase - _phReal) * 0.002;
      case CtrlEstado.pulso:
        _ticksFase++;
        if (_ticksFase >= _ticksPulso) {
          _acido = math.max(0.0, _acido - _mlPorPulso);
          _mlSesion += _mlPorPulso;
          // La bajada depende de qué tan lejos está del umbral (amortiguación).
          final dist = math.max(0.05, _phReal - _umbral);
          _bajadaPendiente =
              math.min(dist + 0.02, 0.18) * (0.8 + 0.4 * _rnd.nextDouble());
          _phAntesMezcla = _phReal;
          _estado = CtrlEstado.mezcla;
          _ticksFase = 0;
        }
      case CtrlEstado.mezcla:
        _phReal -= _bajadaPendiente / _ticksMezcla;
        _ticksFase++;
        if (_ticksFase >= _ticksMezcla) {
          _sHat = (_phAntesMezcla - _phReal) / _mlPorPulso;
          final ph = _phReal + _offset;
          if (ph <= _umbral + _tolerancia) {
            _terminar();
          } else if (_acido < _mlPorPulso) {
            _estado = CtrlEstado.error;
            _errorMsg = 'Ácido insuficiente';
          } else {
            _pulsos++;
            _estado = CtrlEstado.pulso;
            _ticksFase = 0;
          }
        }
    }
    _emitir();
  }

  void _terminar() {
    final ph = _phReal + _offset;
    _errorFinal = double.parse((ph - _umbral).toStringAsFixed(2));
    _resumen = Resumen(
      umbral: _umbral,
      phFinal: double.parse(ph.toStringAsFixed(2)),
      error: _errorFinal,
      pulsos: _pulsos,
      ml: double.parse(_mlSesion.toStringAsFixed(1)),
      segundos: _inicio == null
          ? 0
          : DateTime.now().difference(_inicio!).inSeconds,
    );
    _estado = CtrlEstado.idle;
    _inicio = null;
  }

  void _emitir() {
    if (_tele.isClosed) return;
    final ph = _phMedido;
    _tele.add(Telemetria(
      ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ph: ph,
      conectado: true,
      nodo: nodo,
      ubicacion: ubicacion,
      mv: 1784 + (6.84 - ph) * 177, // valor crudo ilustrativo
      sensor: SensorEstado.ok,
      estado: _estado,
      errorMsg: _errorMsg,
      bomba: _estado == CtrlEstado.pulso,
      umbral: _umbral,
      mlDosificados: _mlSesion,
      acidoRestanteMl: _acido,
      pulsos: _pulsos,
      sHat: _sHat,
      errorFinal: _errorFinal,
      // Sin sensor de temperatura: la app usa la de Configuración.
      calib: Calib(offset: _offset, fecha: _calibFecha),
      resumen: _resumen,
    ));
  }

  @override
  Future<void> enviarUmbral(double ph) async {
    // El firmware tiene la última palabra: ignora valores fuera de rango.
    if (ph < 4.5 || ph > 7.0) return;
    _umbral = ph;
  }

  @override
  Future<void> enviarCmd(String cmd) async {
    final c = cmd.trim();
    if (c == Cmd.dosificar) {
      _dosificar();
    } else if (c == Cmd.detener) {
      if (_estado == CtrlEstado.pulso || _estado == CtrlEstado.mezcla) {
        _terminar();
      } else if (_estado == CtrlEstado.error) {
        _estado = CtrlEstado.idle;
      }
    } else if (c.startsWith('c ')) {
      final ref = double.tryParse(c.substring(2).trim());
      if (ref != null) {
        _offset = ref - _phReal;
        final n = DateTime.now();
        _calibFecha = '${n.year}-${_2(n.month)}-${_2(n.day)}T'
            '${_2(n.hour)}:${_2(n.minute)}';
      }
    } else if (c.startsWith('a ')) {
      final ml = double.tryParse(c.substring(2).trim());
      if (ml != null) {
        _acido = ml;
        if (_estado == CtrlEstado.error) {
          _estado = CtrlEstado.idle;
          _errorMsg = null;
        }
      }
    }
    _emitir();
  }

  void _dosificar() {
    if (_estado == CtrlEstado.pulso || _estado == CtrlEstado.mezcla) return;
    final ph = _phReal + _offset;
    if (ph <= _umbral) {
      _errorMsg = 'El pH ya está en o por debajo del umbral';
      return; // rechazado: sigue en IDLE
    }
    if (_acido < _mlPorPulso) {
      _estado = CtrlEstado.error;
      _errorMsg = 'Ácido insuficiente';
      return;
    }
    _errorMsg = null;
    _errorFinal = null;
    _mlSesion = 0;
    _pulsos = 1;
    _inicio = DateTime.now();
    _estado = CtrlEstado.pulso;
    _ticksFase = 0;
  }

  static String _2(int v) => v.toString().padLeft(2, '0');
}
