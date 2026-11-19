import 'package:flutter_test/flutter_test.dart';
import 'package:agua/core/chem.dart';
import 'package:agua/core/ph_colors.dart';

void main() {
  group('pKa', () {
    test('a 25 °C ≈ 7.54', () {
      expect(pKa(toKelvin(25)), closeTo(7.54, 0.01));
    });
  });

  group('% HOCl a 25 °C', () {
    test('pH 7.0 → ~77.5 %', () {
      expect(hoclPct(7.0, 25), closeTo(77.5, 0.2));
    });
    test('pH 8.0 → ~25.6 %', () {
      expect(hoclPct(8.0, 25), closeTo(25.6, 0.2));
    });
  });

  group('pH para fracción deseada', () {
    test('90 % a 25 °C → pH ~6.58', () {
      expect(phForFraction(0.90, 25), closeTo(6.58, 0.01));
    });
    test('90 % a 15 °C → pH ~6.68', () {
      expect(phForFraction(0.90, 15), closeTo(6.68, 0.01));
    });
    test('90 % a 35 °C → pH ~6.51', () {
      expect(phForFraction(0.90, 35), closeTo(6.51, 0.01));
    });
    test('90 % a 22 °C → pH ~6.61', () {
      expect(phForFraction(0.90, 22), closeTo(6.61, 0.01));
    });
    test('ida y vuelta pH → % → pH', () {
      final pct = hoclPct(6.8, 20);
      expect(phForFraction(pct / 100, 20), closeTo(6.8, 1e-9));
    });
    test('alpha fuera de (0,1) lanza error', () {
      expect(() => phForFraction(1.0, 25), throwsArgumentError);
      expect(() => phForFraction(0.0, 25), throwsArgumentError);
    });
  });

  group('pH recomendado', () {
    test('nunca baja de 6.5', () {
      expect(recommendedPh(35), closeTo(6.51, 0.01));
      expect(recommendedPh(60), greaterThanOrEqualTo(6.5));
    });
    test('a 15 °C ~6.68', () {
      expect(recommendedPh(15), closeTo(6.68, 0.01));
    });
  });

  group('NOM-127', () {
    test('límites inclusivos', () {
      expect(nomStatus(6.5), NomStatus.enRango);
      expect(nomStatus(8.5), NomStatus.enRango);
      expect(nomStatus(6.49), NomStatus.fueraRango);
      expect(nomStatus(8.51), NomStatus.fueraRango);
    });
  });

  group('Meta de eficacia', () {
    test('90 % a 22 °C con pH 7.2 → umbral ~6.61, hay que dosificar', () {
      final t = targetForEfficacy(pct: 90, tempC: 22, phActual: 7.2);
      expect(t.ph, closeTo(6.61, 0.01));
      expect(t.yaSeCumple, isFalse);
      expect(t.ajustadoAlMinimo, isFalse);
    });
    test('si el pH actual ya da esa eficacia → ya se cumple', () {
      final t = targetForEfficacy(pct: 90, tempC: 22, phActual: 6.5);
      expect(t.yaSeCumple, isTrue);
    });
    test('meta baja (pH > 7.0) → ya se cumple', () {
      final t = targetForEfficacy(pct: 50, tempC: 25, phActual: 7.6);
      expect(t.yaSeCumple, isTrue);
    });
    test('meta muy alta → se ajusta a 4.5', () {
      // 99.99 % a 25 °C da pH teórico ~3.54
      final t = targetForEfficacy(pct: 99.99, tempC: 25, phActual: 7.2);
      expect(t.ph, 4.5);
      expect(t.ajustadoAlMinimo, isTrue);
    });
  });

  group('Temperatura efectiva', () {
    test('sin sensor usa la de configuración y es supuesta', () {
      final t = temperaturaEfectiva(
          sensorC: null, sensorSupuesta: null, configC: 22, usarSensor: true);
      expect(t.tempC, 22);
      expect(t.supuesta, isTrue);
    });
    test('con sensor y "usar sensor" activo', () {
      final t = temperaturaEfectiva(
          sensorC: 24.5, sensorSupuesta: false, configC: 22, usarSensor: true);
      expect(t.tempC, 24.5);
      expect(t.supuesta, isFalse);
    });
  });

  group('Datos viejos', () {
    test('más de 10 s', () {
      final r = DateTime(2026, 11, 19, 10, 0, 0);
      expect(isStale(r, r.add(const Duration(seconds: 10))), isFalse);
      expect(isStale(r, r.add(const Duration(seconds: 11))), isTrue);
    });
  });

  group('Color del indicador', () {
    test('extremos y enteros exactos', () {
      expect(phIndicatorColor(0), kPhIndicatorColors[0]);
      expect(phIndicatorColor(7), kPhIndicatorColors[7]);
      expect(phIndicatorColor(14), kPhIndicatorColors[14]);
      expect(phIndicatorColor(-3), kPhIndicatorColors[0]);
      expect(phIndicatorColor(20), kPhIndicatorColors[14]);
    });
    test('tabla de 15 colores', () {
      expect(kPhIndicatorColors.length, 15);
    });
  });
}
