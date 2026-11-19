// Cálculos químicos puros (sin Flutter) para poder probarlos con unit tests.
import 'dart:math' as math;

const double kKelvinOffset = 273.15;
const double phMinUmbral = 4.5;
const double phMaxUmbral = 7.0;
const double nomMin = 6.5;
const double nomMax = 8.5;
const Duration staleAfter = Duration(seconds: 10);

double log10(num x) => math.log(x) / math.ln10;

/// T en kelvin a partir de °C.
double toKelvin(double tempC) => tempC + kKelvinOffset;

/// pKa del ácido hipocloroso en función de T (kelvin).
double pKa(double tempK) => 3000 / tempK - 10.0686 + 0.0253 * tempK;

/// Fracción (0–1) del cloro libre presente como HOCl.
double hoclFraction(double ph, double tempC) =>
    1 / (1 + math.pow(10, ph - pKa(toKelvin(tempC))));

/// Porcentaje (0–100) de HOCl.
double hoclPct(double ph, double tempC) => 100 * hoclFraction(ph, tempC);

/// pH necesario para tener una fracción `alpha` (0–1, exclusivo) de HOCl.
double phForFraction(double alpha, double tempC) {
  if (alpha <= 0 || alpha >= 1) {
    throw ArgumentError.value(alpha, 'alpha', 'debe estar entre 0 y 1');
  }
  return pKa(toKelvin(tempC)) + log10((1 - alpha) / alpha);
}

/// pH recomendado: el que da 90 % HOCl, sin bajar de 6.5 (norma).
double recommendedPh(double tempC) =>
    math.max(nomMin, phForFraction(0.90, tempC));

enum NomStatus { enRango, fueraRango }

NomStatus nomStatus(double ph) =>
    (ph >= nomMin && ph <= nomMax) ? NomStatus.enRango : NomStatus.fueraRango;

/// Lectura vieja: más de 10 s desde que se recibió.
bool isStale(DateTime recibido, DateTime ahora) =>
    ahora.difference(recibido) > staleAfter;

/// Resultado de convertir una meta de eficacia (% HOCl) a umbral de pH.
class EfficacyTarget {
  final double ph; // umbral a enviar (ya ajustado a 4.5–7.0)
  final double phSinAjuste; // pH teórico antes de ajustar
  final bool yaSeCumple; // no hace falta dosificar
  final bool ajustadoAlMinimo; // se recortó a 4.5

  const EfficacyTarget({
    required this.ph,
    required this.phSinAjuste,
    required this.yaSeCumple,
    required this.ajustadoAlMinimo,
  });
}

/// Solo se puede BAJAR el pH: si la meta pide pH > 7.0 o el pH actual ya
/// la cumple, no hace falta dosificar.
EfficacyTarget targetForEfficacy({
  required double pct,
  required double tempC,
  double? phActual,
}) {
  final ph = phForFraction(pct / 100, tempC);
  final yaSeCumple = ph > phMaxUmbral || (phActual != null && phActual <= ph);
  final ajustado = ph < phMinUmbral;
  return EfficacyTarget(
    ph: ph.clamp(phMinUmbral, phMaxUmbral).toDouble(),
    phSinAjuste: ph,
    yaSeCumple: yaSeCumple,
    ajustadoAlMinimo: ajustado,
  );
}

/// Temperatura a usar en los cálculos y si es supuesta.
({double tempC, bool supuesta}) temperaturaEfectiva({
  required double? sensorC,
  required bool? sensorSupuesta,
  required double configC,
  required bool usarSensor,
}) {
  if (usarSensor && sensorC != null) {
    return (tempC: sensorC, supuesta: sensorSupuesta ?? false);
  }
  return (tempC: configC, supuesta: true);
}

/// Redondea al paso más cercano (p. ej. 0.05).
double roundToStep(double v, double step) => (v / step).round() * step;
