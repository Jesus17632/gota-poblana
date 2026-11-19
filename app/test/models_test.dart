import 'package:flutter_test/flutter_test.dart';
import 'package:agua/data/models.dart';

void main() {
  test('Telemetria: parsea el ejemplo del contrato', () {
    final t = Telemetria.fromMap({
      'ts': 1763571240,
      'conectado': true,
      'nodo': 'nodo1',
      'ubicacion': 'Mesa 4',
      'ph': 6.84,
      'mv': 1784,
      'sensor': 'OK',
      'estado': 'MEZCLA',
      'bomba': false,
      'umbral': 6.60,
      'ml_dosificados': 7.4,
      'acido_restante_ml': 88.2,
      'pulsos': 4,
      's_hat': 0.18,
      'error_final': null,
      'temp_c': 22.0,
      'temp_supuesta': true,
      'hocl_pct': 83.1,
      'calib': {'offset': 0.05, 'fecha': '2026-11-19T10:20'},
      'resumen': {
        'umbral': 6.5,
        'ph_final': 6.53,
        'error': 0.03,
        'pulsos': 6,
        'ml': 9.1,
        'segundos': 74
      },
    })!;
    expect(t.ph, 6.84);
    expect(t.estado, CtrlEstado.mezcla);
    expect(t.sensor, SensorEstado.ok);
    expect(t.mv, 1784.0);
    expect(t.errorFinal, isNull);
    expect(t.calib?.offset, 0.05);
    expect(t.resumen?.segundos, 74);
  });

  test('Telemetria: sin ts o ph devuelve null', () {
    expect(Telemetria.fromMap({'ph': 7.0}), isNull);
    expect(Telemetria.fromMap({'ts': 1}), isNull);
  });

  test('Telemetria: campos opcionales ausentes quedan en null', () {
    final t = Telemetria.fromMap({'ts': 1, 'ph': '7.1'})!;
    expect(t.ph, 7.1);
    expect(t.estado, isNull);
    expect(t.acidoRestanteMl, isNull);
  });

  test('Lectura: ida y vuelta por JSON', () {
    final l = Lectura(
        t: DateTime.fromMillisecondsSinceEpoch(1763571240000),
        ph: 6.9,
        hoclPct: 80,
        evento: 'pulso');
    final r = Lectura.fromMap(l.toMap())!;
    expect(r.t, l.t);
    expect(r.ph, 6.9);
    expect(r.evento, 'pulso');
  });
}
