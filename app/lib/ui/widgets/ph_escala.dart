import 'package:material_ui/material_ui.dart';

import '../../core/chem.dart';
import '../../core/palette.dart';
import '../../core/ph_colors.dart';
import '../app_scope.dart';
import '../tokens.dart';

/// Zona de pH en lenguaje claro: qué es peligroso y qué no.
({String titulo, String explicacion, Color color, IconData icono}) zonaPh(double ph) {
  if (ph < nomMin) {
    return (
      titulo: 'Ácido · fuera de la norma',
      explicacion: 'Por debajo de 6.5 el agua puede corroer tuberías y metales.',
      color: Palette.error,
      icono: Icons.warning_amber_rounded,
    );
  }
  if (ph > nomMax) {
    return (
      titulo: 'Alcalino · fuera de la norma',
      explicacion: 'Por encima de 8.5 el cloro casi no desinfecta.',
      color: Palette.error,
      icono: Icons.warning_amber_rounded,
    );
  }
  return (
    titulo: 'Dentro del rango de la norma',
    explicacion: 'La NOM-127 pide pH entre 6.5 y 8.5.',
    color: Palette.normal,
    icono: Icons.check_circle_outline,
  );
}

/// "Termómetro" horizontal de pH 0–14 con la zona de la norma marcada y una
/// aguja en el pH actual.
class PhEscala extends StatelessWidget {
  const PhEscala({super.key, required this.ph, this.mostrarTexto = true});
  final double? ph;
  final bool mostrarTexto;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final dur = animDur(context, 500);
    final z = ph == null ? null : zonaPh(ph!);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth;
        double x(double v) => (v.clamp(0, 14) / 14) * w;
        return SizedBox(
          height: 46,
          child: Stack(clipBehavior: Clip.none, children: [
            // Barra con los colores del indicador universal
            Positioned(
              left: 0,
              right: 0,
              top: 16,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(colors: kPhIndicatorColors),
                ),
              ),
            ),
            // Zonas fuera de la norma, atenuadas
            Positioned(
              left: 0,
              width: x(nomMin),
              top: 16,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.fondo.withValues(alpha: 0.45),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                ),
              ),
            ),
            Positioned(
              left: x(nomMax),
              right: 0,
              top: 16,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.fondo.withValues(alpha: 0.45),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                ),
              ),
            ),
            // Corchete de la norma
            Positioned(
              left: x(nomMin),
              width: x(nomMax) - x(nomMin),
              top: 10,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.texto, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            // Aguja
            if (ph != null)
              AnimatedPositioned(
                duration: dur,
                curve: Curves.easeOutCubic,
                left: x(ph!) - 9,
                top: 0,
                child: Column(children: [
                  Icon(Icons.arrow_drop_down_rounded, size: 18, color: c.texto),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: phIndicatorColor(ph!),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.superficie, width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4)
                      ],
                    ),
                  ),
                ]),
              ),
          ]),
        );
      }),
      const SizedBox(height: 2),
      // Marcas y zonas, alineadas con la barra
      LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth;
        double x(double v) => (v / 14) * w;
        return SizedBox(
          height: 34,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: 0, top: 0, child: _marca(context, '0')),
            Positioned(
                left: x(nomMin) - 20,
                width: 40,
                top: 0,
                child: _marca(context, '6.5', centro: true)),
            Positioned(
                left: x(nomMax) - 20,
                width: 40,
                top: 0,
                child: _marca(context, '8.5', centro: true)),
            Positioned(right: 0, top: 0, child: _marca(context, '14')),
            Positioned(left: 0, top: 16, child: _zona(context, 'Ácido')),
            Positioned(
                left: x(nomMin),
                width: x(nomMax) - x(nomMin),
                top: 16,
                child: _zona(context, 'Norma', centro: true)),
            Positioned(right: 0, top: 16, child: _zona(context, 'Alcalino')),
          ]),
        );
      }),
      if (mostrarTexto && z != null) ...[
        const SizedBox(height: Esp.m),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(z.icono, size: 20, color: Palette.legible(z.color, oscuro: c.oscuro)),
          const SizedBox(width: Esp.s),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${z.titulo}. ',
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.texto)),
              TextSpan(text: z.explicacion, style: TextStyle(color: c.texto2)),
            ])),
          ),
        ]),
      ],
    ]);
  }

  Widget _marca(BuildContext context, String t, {bool centro = false}) => Text(t,
      textAlign: centro ? TextAlign.center : null,
      style: TextStyle(
          fontSize: 11,
          color: context.ag.texto2,
          fontFeatures: const [FontFeature.tabularFigures()]));

  Widget _zona(BuildContext context, String t, {bool centro = false}) => Text(t,
      textAlign: centro ? TextAlign.center : null,
      maxLines: 1,
      overflow: TextOverflow.visible,
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: context.ag.texto2));
}
