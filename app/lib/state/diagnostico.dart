// Test completo de hardware y conectividad. Cada paso solo LEE lo que reporta
// el ESP32 o le manda órdenes de prueba inocuas (LED, buzzer). Nunca enciende
// la bomba: eso se prueba a mano en Dispositivos, con confirmación.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/device_constants.dart';
import '../core/fallas.dart';
import '../data/data_source.dart';
import '../data/models.dart';
import 'app_state.dart';

enum ResultadoPaso { pendiente, corriendo, ok, aviso, falla, omitido }

class PasoDiagnostico {
  PasoDiagnostico(this.id, this.titulo);
  final String id;
  final String titulo;
  ResultadoPaso resultado = ResultadoPaso.pendiente;
  String? detalle;
  Duration? duracion;

  bool get hecho =>
      resultado != ResultadoPaso.pendiente &&
      resultado != ResultadoPaso.corriendo;
}

typedef _Res = (ResultadoPaso, String);

class Diagnostico extends ChangeNotifier {
  final List<PasoDiagnostico> pasos = [];
  bool corriendo = false;
  DateTime? inicio;
  DateTime? fin;
  int _gen = 0;

  bool get visible => pasos.isNotEmpty;
  bool get terminado => fin != null;
  int contar(ResultadoPaso r) => pasos.where((p) => p.resultado == r).length;
  double get progreso =>
      pasos.isEmpty ? 0 : pasos.where((p) => p.hecho).length / pasos.length;

  void cerrar() {
    _gen++;
    pasos.clear();
    corriendo = false;
    inicio = null;
    fin = null;
    notifyListeners();
  }

  Future<void> ejecutar(AppState s) async {
    final gen = ++_gen;
    corriendo = true;
    inicio = DateTime.now();
    fin = null;

    final inicioTest = DateTime.now();
    var conectado = false;

    // Pasos (id, título, función). Se muestran todos desde el inicio.
    final plan = <(String, String, Future<_Res> Function())>[
      ('fuente', 'Fuente de datos', () async {
        return (
          ResultadoPaso.ok,
          s.simulado
              ? 'MODO SIMULADO · ${s.fuenteDescripcion}'
              : s.fuenteDescripcion
        );
      }),
      ('conexion', 'Conexión con el ESP32', () async {
        conectado = await _esperar(() => !s.sinConexion, const Duration(seconds: 5));
        return conectado
            ? (ResultadoPaso.ok, 'Conectado')
            : (ResultadoPaso.falla, s.errorConexion ?? 'Sin conexión con el ESP32');
      }),
      ('datos', 'Recepción de lecturas', () async {
        if (!conectado) return (ResultadoPaso.omitido, 'Requiere conexión');
        final ok = await _esperar(
            () => s.recibido != null && s.recibido!.isAfter(inicioTest),
            const Duration(seconds: 4));
        if (!ok) {
          return (ResultadoPaso.falla, 'No llegan lecturas de telemetría');
        }
        return (ResultadoPaso.ok,
            'Lectura recibida ${DateTime.now().difference(s.recibido!).inMilliseconds} ms antes');
      }),
      ('controlador', 'Estado del controlador', () async {
        if (!s.hayDatos) return (ResultadoPaso.omitido, 'Sin datos');
        return switch (s.estadoCtrl) {
          CtrlEstado.error => (
              ResultadoPaso.falla,
              'ERROR: ${s.ultimo?.errorMsg ?? 'sin detalle'}'
            ),
          CtrlEstado.idle => (ResultadoPaso.ok, 'Listo (IDLE)'),
          CtrlEstado.pulso => (ResultadoPaso.ok, 'Dosificando (PULSO)'),
          CtrlEstado.mezcla => (ResultadoPaso.ok, 'Mezclando (MEZCLA)'),
        };
      }),
      ('sonda', 'Sonda de pH', () async {
        if (!s.hayDatos) return (ResultadoPaso.omitido, 'Sin datos');
        final f = _fallaModulo(s, 'PH', soloCriticas: true);
        if (f != null) return (ResultadoPaso.falla, _txt(f));
        if (!s.sensorOk) {
          return (
            ResultadoPaso.falla,
            'Revisar sensor (${sensorWire(s.ultimo!.sensor!)})'
          );
        }
        final ph = s.ultimo!.ph;
        if (ph <= 0 || ph >= 14) {
          return (ResultadoPaso.falla, 'Lectura imposible: pH ${ph.toStringAsFixed(2)}');
        }
        final mv = s.ultimo!.mv;
        return (
          ResultadoPaso.ok,
          'pH ${ph.toStringAsFixed(2)}${mv == null ? '' : ' · ${mv.toStringAsFixed(0)} mV'}'
        );
      }),
      ('temp', 'Sensor de temperatura', () async {
        if (!s.hayDatos) return (ResultadoPaso.omitido, 'Sin datos');
        final t = s.ultimo!.tempC;
        final desactivado =
            t == null || (s.hw?.tieneFalla(Fallas.sensorTempDesconectado) ?? false);
        if (desactivado) {
          // Sin alerta: el estado se consulta en Ajustes → Dispositivos.
          return (ResultadoPaso.omitido, 'Desactivado');
        }
        return (ResultadoPaso.ok, '${t.toStringAsFixed(1)} °C');
      }),
      ('xn13', 'Relé de la bomba (XN13 · 0x0D)', () => _modulo(s, conectado, 'XN13')),
      ('xn44', 'Buzzer (XN44 · 0x2C)', () => _modulo(s, conectado, 'XN44')),
      ('xn03', 'LED RGB (XN03 · 0x03)', () => _modulo(s, conectado, 'XN03')),
      ('acido', 'Inventario de ácido', () async {
        final a = s.ultimo?.acidoRestanteMl;
        if (s.hw?.tieneFalla(Fallas.acidoAgotado) ?? false) {
          return (ResultadoPaso.falla, 'Ácido agotado');
        }
        if (a == null) return (ResultadoPaso.aviso, 'El equipo no reporta inventario');
        if (a < DeviceConst.acidoBajoMl) {
          return (ResultadoPaso.aviso, 'Quedan ${a.toStringAsFixed(1)} mL');
        }
        return (ResultadoPaso.ok, '${a.toStringAsFixed(1)} mL');
      }),
      ('calib', 'Calibración', () async {
        final c = s.ultimo?.calib;
        if ((s.hw?.tieneFalla(Fallas.calibracionPendiente) ?? false) ||
            c?.fecha == null ||
            c!.fecha!.isEmpty) {
          // Sin alerta: se consulta en Ajustes → Dispositivos.
          return (ResultadoPaso.omitido, 'Pendiente · ver Ajustes → Dispositivos');
        }
        return (
          ResultadoPaso.ok,
          'Offset ${c.offset?.toStringAsFixed(2) ?? '—'} · ${c.fecha}'
        );
      }),
      ('respuesta', 'Respuesta a órdenes (LED)', () async {
        if (!s.esTecnico) return (ResultadoPaso.omitido, 'Solo en modo técnico');
        if (!conectado) return (ResultadoPaso.omitido, 'Requiere conexión');
        return _orden(s, Cmd.testLed(0, 255, 0), TipoEvento.led,
            () => s.probarLed(0, 255, 0));
      }),
      ('buzzer', 'Prueba del buzzer', () async {
        if (!s.esTecnico) return (ResultadoPaso.omitido, 'Solo en modo técnico');
        if (!conectado) return (ResultadoPaso.omitido, 'Requiere conexión');
        return _orden(s, Cmd.testBuzzer('fin'), TipoEvento.buzzer,
            () => s.probarBuzzer('fin'));
      }),
      ('bomba', 'Bomba', () async {
        return (
          ResultadoPaso.omitido,
          'No se enciende en el test (seguridad). Usa "Probar bomba" en Dispositivos.'
        );
      }),
      ('otras', 'Otras fallas reportadas', () async {
        if (s.hw == null) return (ResultadoPaso.omitido, 'Sin datos de hardware');
        const cubiertos = {'PH', 'TEMP', 'XN13', 'XN44', 'XN03'};
        const codigosCubiertos = {Fallas.acidoAgotado, Fallas.acidoBajo, Fallas.calibracionPendiente};
        final otras = s.fallas
            .where((f) =>
                !cubiertos.contains(f.modulo) && !codigosCubiertos.contains(f.codigo))
            .toList();
        if (otras.isEmpty) return (ResultadoPaso.ok, 'Ninguna');
        final hayCritica = otras.any((f) => f.critica);
        return (
          hayCritica ? ResultadoPaso.falla : ResultadoPaso.aviso,
          otras.map(_txt).join(' · ')
        );
      }),
    ];

    pasos
      ..clear()
      ..addAll([for (final p in plan) PasoDiagnostico(p.$1, p.$2)]);
    notifyListeners();

    for (var i = 0; i < plan.length; i++) {
      if (gen != _gen) return; // se cerró o se reinició
      final paso = pasos[i];
      paso.resultado = ResultadoPaso.corriendo;
      notifyListeners();
      final sw = Stopwatch()..start();
      _Res r;
      try {
        r = await plan[i].$3();
      } catch (e) {
        r = (ResultadoPaso.falla, 'Error interno del test: $e');
      }
      // Pausa mínima para que se vea el avance línea por línea.
      final resta = 220 - sw.elapsedMilliseconds;
      if (resta > 0) await Future.delayed(Duration(milliseconds: resta));
      if (gen != _gen) return;
      paso
        ..resultado = r.$1
        ..detalle = r.$2
        ..duracion = sw.elapsed;
      notifyListeners();
    }
    corriendo = false;
    fin = DateTime.now();
    notifyListeners();
  }

  // ---------- Ayudantes ----------

  static Future<bool> _esperar(bool Function() cond, Duration t) async {
    final limite = DateTime.now().add(t);
    while (DateTime.now().isBefore(limite)) {
      if (cond()) return true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return cond();
  }

  static String _txt(FallaHw f) =>
      f.info.titulo + (f.detalle == null ? '' : ' (${f.detalle})');

  static FallaHw? _fallaModulo(AppState s, String modulo,
      {bool soloCriticas = false}) {
    for (final f in s.fallas) {
      if (f.modulo == modulo && (!soloCriticas || f.critica)) return f;
    }
    return null;
  }

  static Future<_Res> _modulo(AppState s, bool conectado, String m) async {
    if (!conectado) return (ResultadoPaso.omitido, 'Requiere conexión');
    final ok = await _esperar(() => s.hw != null, const Duration(seconds: 3));
    if (!ok) {
      return (ResultadoPaso.aviso, 'El equipo no publica el tema hardware');
    }
    final f = _fallaModulo(s, m);
    if (f != null) {
      return (f.critica ? ResultadoPaso.falla : ResultadoPaso.aviso, _txt(f));
    }
    final det = s.hw!.modulos?[m];
    if (det == false) return (ResultadoPaso.falla, 'No detectado en el bus I2C');
    if (det == null) return (ResultadoPaso.aviso, 'Sin reporte del módulo');
    return (ResultadoPaso.ok, 'Responde');
  }

  /// Envía una orden de prueba y espera el evento de respuesta.
  static Future<_Res> _orden(AppState s, String cmd, TipoEvento esperado,
      Future<void> Function() enviar) async {
    final sw = Stopwatch()..start();
    final respuesta = s.eventosDispositivo
        .firstWhere((e) =>
            (e.cmd == cmd || e.cmd == null) &&
            (e.tipo == esperado || e.tipo == TipoEvento.rechazo))
        .timeout(DeviceConst.timeoutRespuesta);
    try {
      await enviar();
      final e = await respuesta;
      if (e.tipo == TipoEvento.rechazo) {
        return (ResultadoPaso.falla, 'Rechazado: ${e.detalle ?? 'sin motivo'}');
      }
      return (ResultadoPaso.ok, 'Responde en ${sw.elapsedMilliseconds} ms');
    } on TimeoutException {
      return (ResultadoPaso.falla, 'Sin respuesta del dispositivo');
    } catch (e) {
      // Evita un error no atrapado del futuro de respuesta.
      unawaited(respuesta.then((_) {}, onError: (_) {}));
      return (ResultadoPaso.falla, 'No se pudo enviar: $e');
    }
  }
}
