// Paleta por SIGNIFICADO (igual en modo claro y oscuro).
// Cada color de estado va siempre acompañado de texto o ícono.
// Los neutros (fondo, texto, líneas) viven en ui/tokens.dart porque cambian
// con el tema.
import 'dart:ui' show Color;

class Palette {
  Palette._();

  static const normal = Color(0xFF218DAE); // normal / en rango
  static const dosificando = Color(0xFF2BBBD7); // activo
  static const mezclando = Color(0xFFFCE59A); // mezclando / esperando
  static const precaucion = Color(0xFFFFD758); // cerca del límite, ácido bajo, temp supuesta
  static const error = Color(0xFFE5484D); // error / fuera de norma
  static const sinDatos = Color(0xFF8E8E93); // sin datos / falla de sensor

  static const tinta = Color(0xFF15191C); // texto oscuro sobre colores claros
  static const blanco = Color(0xFFFFFFFF);

  /// Texto legible encima de un color (los amarillos llevan texto oscuro).
  static Color textoSobre(Color c) => c.computeLuminance() > 0.45 ? tinta : blanco;

  /// Versión de un color de estado apta para íconos/trazos sobre fondo claro
  /// (los amarillos se oscurecen para tener contraste).
  static Color legible(Color c, {required bool oscuro}) =>
      (!oscuro && c.computeLuminance() > 0.6)
          ? Color.lerp(c, tinta, 0.45)!
          : c;
}
