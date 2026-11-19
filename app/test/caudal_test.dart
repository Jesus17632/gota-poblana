import 'package:flutter_test/flutter_test.dart';
import 'package:agua/core/caudal.dart';

void main() {
  test('dos puntos: recupera q = 33 mL/s y t0 = 30 ms', () {
    // V = 0.033 mL/ms · (t − 30)
    final c = calibrarCaudal(t1Ms: 500, v1Ml: 15.51, t2Ms: 1500, v2Ml: 48.51);
    expect(c.mlPorSegundo, closeTo(33.0, 0.01));
    expect(c.t0Ms, closeTo(30, 0.5));
    expect(c.volumen(250), closeTo(0.033 * 220, 0.01));
  });

  test('t0 negativo por ruido se recorta a 0', () {
    final c = calibrarCaudal(t1Ms: 500, v1Ml: 17, t2Ms: 1500, v2Ml: 50);
    expect(c.t0Ms, 0);
  });

  test('valores sin sentido lanzan error', () {
    expect(() => calibrarCaudal(t1Ms: 500, v1Ml: 20, t2Ms: 1500, v2Ml: 10),
        throwsArgumentError);
  });

  test('un punto: 33 mL en 1 s', () {
    expect(calibrarCaudalUnPunto(tMs: 1000, vMl: 33).mlPorSegundo, 33);
  });
}
