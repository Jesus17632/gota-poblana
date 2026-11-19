// Modelo de estado unificado. Los nombres de los campos JSON son el contrato
// con el firmware: NO los cambies sin avisar.

double? _d(Object? v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
int? _i(Object? v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null);
bool? _b(Object? v) => v is bool
    ? v
    : (v is num ? v != 0 : (v is String ? v.toLowerCase() == 'true' : null));
String? _s(Object? v) => v?.toString();

enum CtrlEstado { idle, pulso, mezcla, error }

CtrlEstado? parseCtrlEstado(Object? v) =>
    switch (v?.toString().trim().toUpperCase()) {
      'IDLE' => CtrlEstado.idle,
      'PULSO' => CtrlEstado.pulso,
      'MEZCLA' => CtrlEstado.mezcla,
      'ERROR' => CtrlEstado.error,
      _ => null,
    };

String ctrlEstadoWire(CtrlEstado e) => switch (e) {
      CtrlEstado.idle => 'IDLE',
      CtrlEstado.pulso => 'PULSO',
      CtrlEstado.mezcla => 'MEZCLA',
      CtrlEstado.error => 'ERROR',
    };

enum SensorEstado { ok, fueraRango, sinRespuesta }

SensorEstado? parseSensor(Object? v) =>
    switch (v?.toString().trim().toUpperCase()) {
      'OK' => SensorEstado.ok,
      'FUERA_RANGO' => SensorEstado.fueraRango,
      'SIN_RESPUESTA' => SensorEstado.sinRespuesta,
      _ => null,
    };

String sensorWire(SensorEstado s) => switch (s) {
      SensorEstado.ok => 'OK',
      SensorEstado.fueraRango => 'FUERA_RANGO',
      SensorEstado.sinRespuesta => 'SIN_RESPUESTA',
    };

class Calib {
  final double? offset;
  final String? fecha;
  const Calib({this.offset, this.fecha});

  static Calib? fromMap(Object? v) => v is Map
      ? Calib(offset: _d(v['offset']), fecha: _s(v['fecha']))
      : null;

  Map<String, dynamic> toMap() => {'offset': offset, 'fecha': fecha};
}

/// Resumen de una sesión de dosificación.
class Resumen {
  final double? umbral;
  final double? phFinal;
  final double? error;
  final int? pulsos;
  final double? ml;
  final int? segundos;
  final DateTime? registrado; // lo pone la app al guardarlo

  const Resumen({
    this.umbral,
    this.phFinal,
    this.error,
    this.pulsos,
    this.ml,
    this.segundos,
    this.registrado,
  });

  static Resumen? fromMap(Object? v) => v is Map
      ? Resumen(
          umbral: _d(v['umbral']),
          phFinal: _d(v['ph_final']),
          error: _d(v['error']),
          pulsos: _i(v['pulsos']),
          ml: _d(v['ml']),
          segundos: _i(v['segundos']),
          registrado: v['registrado'] is String
              ? DateTime.tryParse(v['registrado'] as String)
              : null,
        )
      : null;

  Map<String, dynamic> toMap() => {
        'umbral': umbral,
        'ph_final': phFinal,
        'error': error,
        'pulsos': pulsos,
        'ml': ml,
        'segundos': segundos,
        if (registrado != null) 'registrado': registrado!.toIso8601String(),
      };

  Resumen conRegistro(DateTime t) => Resumen(
        umbral: umbral,
        phFinal: phFinal,
        error: error,
        pulsos: pulsos,
        ml: ml,
        segundos: segundos,
        registrado: t,
      );

  /// Para detectar si el firmware mandó un resumen nuevo.
  String get clave => '$umbral|$phFinal|$error|$pulsos|$ml|$segundos';
}

class Telemetria {
  final int ts; // epoch en segundos (del firmware)
  final double ph;
  final bool? conectado;
  final String? nodo;
  final String? ubicacion;
  final double? mv;
  final SensorEstado? sensor;
  final CtrlEstado? estado;
  final String? errorMsg;
  final bool? bomba;
  final double? umbral;
  final double? mlDosificados;
  final double? acidoRestanteMl;
  final int? pulsos;
  final double? sHat;
  final double? errorFinal;
  final double? tempC;
  final bool? tempSupuesta;
  final double? hoclPct;
  final Calib? calib;
  final Resumen? resumen;

  const Telemetria({
    required this.ts,
    required this.ph,
    this.conectado,
    this.nodo,
    this.ubicacion,
    this.mv,
    this.sensor,
    this.estado,
    this.errorMsg,
    this.bomba,
    this.umbral,
    this.mlDosificados,
    this.acidoRestanteMl,
    this.pulsos,
    this.sHat,
    this.errorFinal,
    this.tempC,
    this.tempSupuesta,
    this.hoclPct,
    this.calib,
    this.resumen,
  });

  /// Devuelve null si faltan los campos obligatorios (ts, ph).
  static Telemetria? fromMap(Map<String, dynamic> m) {
    final ts = _i(m['ts']);
    final ph = _d(m['ph']);
    if (ts == null || ph == null) return null;
    return Telemetria(
      ts: ts,
      ph: ph,
      conectado: _b(m['conectado']),
      nodo: _s(m['nodo']),
      ubicacion: _s(m['ubicacion']),
      mv: _d(m['mv']),
      sensor: parseSensor(m['sensor']),
      estado: parseCtrlEstado(m['estado']),
      errorMsg: _s(m['error_msg']),
      bomba: _b(m['bomba']),
      umbral: _d(m['umbral']),
      mlDosificados: _d(m['ml_dosificados']),
      acidoRestanteMl: _d(m['acido_restante_ml']),
      pulsos: _i(m['pulsos']),
      sHat: _d(m['s_hat']),
      errorFinal: _d(m['error_final']),
      tempC: _d(m['temp_c']),
      tempSupuesta: _b(m['temp_supuesta']),
      hoclPct: _d(m['hocl_pct']),
      calib: Calib.fromMap(m['calib']),
      resumen: Resumen.fromMap(m['resumen']),
    );
  }
}

/// Una lectura del historial.
class Lectura {
  final DateTime t;
  final double ph;
  final double? hoclPct;
  final String? evento; // "pulso" | "inicio" | "fin"

  const Lectura({required this.t, required this.ph, this.hoclPct, this.evento});

  Map<String, dynamic> toMap() => {
        'ts': t.millisecondsSinceEpoch ~/ 1000,
        'ph': ph,
        if (hoclPct != null) 'hocl_pct': hoclPct,
        if (evento != null) 'evento': evento,
      };

  static Lectura? fromMap(Object? v) {
    if (v is! Map) return null;
    final ts = _i(v['ts']);
    final ph = _d(v['ph']);
    if (ts == null || ph == null) return null;
    return Lectura(
      t: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
      ph: ph,
      hoclPct: _d(v['hocl_pct']),
      evento: _s(v['evento']),
    );
  }
}
