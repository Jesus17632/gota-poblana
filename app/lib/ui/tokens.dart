// Tokens de diseño que cambian con el tema (claro / oscuro).
// Uso: `final c = context.ag;` y luego `c.texto`, `c.superficie`, …
import 'package:material_ui/material_ui.dart';

@immutable
class AguaColors extends ThemeExtension<AguaColors> {
  const AguaColors({
    required this.fondo,
    required this.superficie,
    required this.superficie2,
    required this.texto,
    required this.texto2,
    required this.linea,
    required this.seleccion,
    required this.sombra,
    required this.oscuro,
  });

  final Color fondo; // fondo de la pantalla
  final Color superficie; // tarjetas
  final Color superficie2; // elementos dentro de tarjetas
  final Color texto; // texto principal
  final Color texto2; // texto secundario
  final Color linea; // separadores, pistas inactivas
  final Color seleccion; // fondo del ítem activo
  final Color sombra;
  final bool oscuro;

  static const claro = AguaColors(
    fondo: Color(0xFFF4F6F7),
    superficie: Color(0xFFFFFFFF),
    superficie2: Color(0xFFF0F3F5),
    texto: Color(0xFF15191C),
    texto2: Color(0xFF68737B),
    linea: Color(0xFFE2E7EA),
    seleccion: Color(0xFFE3F1F6),
    sombra: Color(0x0D000000),
    oscuro: false,
  );

  static const oscuroTema = AguaColors(
    fondo: Color(0xFF0C0F11),
    superficie: Color(0xFF161A1D),
    superficie2: Color(0xFF1F2528),
    texto: Color(0xFFEFF3F5),
    texto2: Color(0xFF9AA6AE),
    linea: Color(0xFF283035),
    seleccion: Color(0xFF14313A),
    sombra: Color(0x00000000),
    oscuro: true,
  );

  @override
  AguaColors copyWith({
    Color? fondo,
    Color? superficie,
    Color? superficie2,
    Color? texto,
    Color? texto2,
    Color? linea,
    Color? seleccion,
    Color? sombra,
    bool? oscuro,
  }) =>
      AguaColors(
        fondo: fondo ?? this.fondo,
        superficie: superficie ?? this.superficie,
        superficie2: superficie2 ?? this.superficie2,
        texto: texto ?? this.texto,
        texto2: texto2 ?? this.texto2,
        linea: linea ?? this.linea,
        seleccion: seleccion ?? this.seleccion,
        sombra: sombra ?? this.sombra,
        oscuro: oscuro ?? this.oscuro,
      );

  @override
  AguaColors lerp(covariant AguaColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AguaColors(
      fondo: l(fondo, other.fondo),
      superficie: l(superficie, other.superficie),
      superficie2: l(superficie2, other.superficie2),
      texto: l(texto, other.texto),
      texto2: l(texto2, other.texto2),
      linea: l(linea, other.linea),
      seleccion: l(seleccion, other.seleccion),
      sombra: l(sombra, other.sombra),
      oscuro: t < 0.5 ? oscuro : other.oscuro,
    );
  }
}

extension AguaContext on BuildContext {
  AguaColors get ag => Theme.of(this).extension<AguaColors>() ?? AguaColors.claro;
}

/// Espaciado de 8 pt.
class Esp {
  Esp._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double radio = 20;
}
