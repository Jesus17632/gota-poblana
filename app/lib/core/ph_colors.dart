// Tabla del indicador universal de pH (0–14).
// EDITA AQUÍ si quieres usar la misma tabla que el firmware:
// un color por cada pH entero, de 0 a 14 (15 colores).
import 'dart:ui' show Color;

const List<Color> kPhIndicatorColors = [
  Color(0xFFD7263D), // 0  rojo
  Color(0xFFE23B2E), // 1
  Color(0xFFEE5A28), // 2
  Color(0xFFF47D2A), // 3  naranja
  Color(0xFFF79F35), // 4
  Color(0xFFF9C23C), // 5
  Color(0xFFF2DD3A), // 6  amarillo
  Color(0xFF5DBB46), // 7  verde
  Color(0xFF1FA67A), // 8
  Color(0xFF1C82C4), // 9  azul
  Color(0xFF2D5FB8), // 10 azul
  Color(0xFF4B4BA8), // 11
  Color(0xFF6A3D9A), // 12 violeta
  Color(0xFF74348F), // 13
  Color(0xFF7B2D86), // 14
];

/// Interpola linealmente entre los colores de la tabla.
Color phIndicatorColor(double ph) {
  final p = ph.clamp(0.0, 14.0).toDouble();
  final i = p.floor();
  if (i >= 14) return kPhIndicatorColors[14];
  return Color.lerp(kPhIndicatorColors[i], kPhIndicatorColors[i + 1], p - i)!;
}
