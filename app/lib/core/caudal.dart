// Calibración de la bomba. El firmware modela el volumen de un pulso como
//   V = q · (t − t0)
// q  = caudal (mL/ms), t0 = tiempo muerto de arranque del motor (ms).
// Con dos pulsos de distinta duración se obtienen ambos.
import 'dart:math' as math;

class CalibracionCaudal {
  final double mlPorSegundo;
  final double t0Ms;
  const CalibracionCaudal(this.mlPorSegundo, this.t0Ms);

  /// mL que saldrían en un pulso de [ms].
  double volumen(int ms) => mlPorSegundo / 1000 * math.max(0.0, ms - t0Ms);
}

/// Dos puntos (t1, v1) y (t2, v2). Lanza ArgumentError si no tiene sentido
/// físico (el pulso largo debe sacar más líquido que el corto).
CalibracionCaudal calibrarCaudal({
  required int t1Ms,
  required double v1Ml,
  required int t2Ms,
  required double v2Ml,
}) {
  if (t2Ms <= t1Ms) throw ArgumentError('t2 debe ser mayor que t1');
  if (v1Ml < 0 || v2Ml <= v1Ml) {
    throw ArgumentError('El pulso largo debe sacar más mL que el corto');
  }
  final qMlMs = (v2Ml - v1Ml) / (t2Ms - t1Ms);
  var t0 = t1Ms - v1Ml / qMlMs;
  if (t0 < 0) t0 = 0; // ruido de medición: sin tiempo muerto negativo
  return CalibracionCaudal(qMlMs * 1000, t0);
}

/// Un solo punto (más simple, sin tiempo muerto).
CalibracionCaudal calibrarCaudalUnPunto({required int tMs, required double vMl}) {
  if (tMs <= 0 || vMl <= 0) throw ArgumentError('Valores inválidos');
  return CalibracionCaudal(vMl / tMs * 1000, 0);
}
