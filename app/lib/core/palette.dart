// Paleta por SIGNIFICADO. Cada color de estado va siempre con texto o ícono.
import 'dart:ui' show Color;

class Palette {
  Palette._();

  static const normal = Color(0xFF218DAE); // normal / en rango
  static const dosificando = Color(0xFF2BBBD7); // activo
  static const mezclando = Color(0xFFFCE59A); // mezclando / esperando
  static const precaucion = Color(0xFFFFD758); // cerca del límite, ácido bajo, temp supuesta
  static const error = Color(0xFFE5484D); // error / fuera de norma
  static const sinDatos = Color(0xFF8E8E93); // sin datos / falla de sensor

  // Neutros de la interfaz
  static const fondo = Color(0xFFF7F8F9);
  static const tarjeta = Color(0xFFFFFFFF);
  static const texto = Color(0xFF1C2226);
  static const textoSecundario = Color(0xFF6E7880);
  static const pista = Color(0xFFE1E8EB); // barras inactivas, separadores
  static const seleccion = Color(0xFFE8F4F7); // fondo del ítem activo

  /// Texto legible encima de un color (los amarillos llevan texto oscuro).
  static Color textoSobre(Color c) =>
      c.computeLuminance() > 0.5 ? texto : const Color(0xFFFFFFFF);
}
