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

/// "Termómetro" de pH 0–14. Muestra la zona de la norma y una aguja con el pH
/// actual. Si se pasa [onObjetivo], la MISMA barra es el control del objetivo:
/// se toca o arrastra un marcador limitado a [objMin]–[objMax].
class PhEscala extends StatelessWidget {
  const PhEscala({
    super.key,
    required this.ph,
    this.mostrarTexto = true,
    this.objetivo,
    this.onObjetivo,
    this.objMin = phMinUmbral,
    this.objMax = phMaxUmbral,
    this.paso = 0.05,
  });

  final double? ph;
  final bool mostrarTexto;
  final double? objetivo;
  final ValueChanged<double>? onObjetivo;
  final double objMin;
  final double objMax;
  final double paso;

  bool get _interactiva => onObjetivo != null && objetivo != null;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final dur = animDur(context, 450);
    final z = ph == null ? null : zonaPh(ph!);
    final primario = Theme.of(context).colorScheme.primary;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, cons) {
        const lado = 14.0; // margen para que los marcadores no se corten
        final w = cons.maxWidth - lado * 2;
        double x(double v) => lado + (v.clamp(0, 14) / 14) * w;
        double aPh(double dx) => ((dx - lado) / w * 14);

        void elegir(double dx) {
          final v = roundToStep(aPh(dx), paso).clamp(objMin, objMax).toDouble();
          if (v != objetivo) onObjetivo!(v);
        }

        const barraTop = 22.0;
        final alto = _interactiva ? 74.0 : 50.0;

        final barra = SizedBox(
          height: alto,
          child: Stack(clipBehavior: Clip.none, children: [
            // Barra con los colores del indicador universal
            Positioned(
              left: lado,
              right: lado,
              top: barraTop,
              height: 12,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  gradient: LinearGradient(colors: kPhIndicatorColors),
                ),
              ),
            ),
            // Fuera de la norma: atenuado
            Positioned(
              left: lado,
              width: x(nomMin) - lado,
              top: barraTop,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.fondo.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                ),
              ),
            ),
            Positioned(
              left: x(nomMax),
              right: lado,
              top: barraTop,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.fondo.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                ),
              ),
            ),
            // Corchete de la norma
            Positioned(
              left: x(nomMin),
              width: x(nomMax) - x(nomMin),
              top: barraTop - 6,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: c.texto, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            // Rango permitido para el objetivo (4.5–7.0)
            if (_interactiva)
              Positioned(
                left: x(objMin),
                width: x(objMax) - x(objMin),
                top: barraTop + 16,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: primario.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            // Aguja del pH actual (arriba)
            if (ph != null)
              AnimatedPositioned(
                duration: dur,
                curve: Curves.easeOutCubic,
                left: x(ph!) - 10,
                top: barraTop - 18,
                child: Column(children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: phIndicatorColor(ph!),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.superficie, width: 3),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4)
                      ],
                    ),
                  ),
                ]),
              ),
            // Marcador del objetivo (abajo), arrastrable
            if (_interactiva)
              Positioned(
                left: x(objetivo!) - 28,
                top: barraTop - 2,
                child: SizedBox(
                  width: 56,
                  child: Column(children: [
                    Container(width: 3, height: 16, color: primario),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: primario,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        objetivo!.toStringAsFixed(2),
                        style: TextStyle(
                          color: Palette.textoSobre(primario),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        );

        if (!_interactiva) return barra;
        return Semantics(
          slider: true,
          label: 'Objetivo de pH',
          value: objetivo!.toStringAsFixed(2),
          increasedValue: (objetivo! + paso).clamp(objMin, objMax).toStringAsFixed(2),
          decreasedValue: (objetivo! - paso).clamp(objMin, objMax).toStringAsFixed(2),
          onIncrease: () => onObjetivo!((objetivo! + paso).clamp(objMin, objMax).toDouble()),
          onDecrease: () => onObjetivo!((objetivo! - paso).clamp(objMin, objMax).toDouble()),
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => elegir(d.localPosition.dx),
              onHorizontalDragStart: (d) => elegir(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => elegir(d.localPosition.dx),
              child: barra,
            ),
          ),
        );
      }),
      const SizedBox(height: 2),
      // Marcas y zonas, alineadas con la barra
      LayoutBuilder(builder: (context, cons) {
        const lado = 14.0;
        final w = cons.maxWidth - lado * 2;
        double x(double v) => lado + (v / 14) * w;
        return SizedBox(
          height: 34,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: lado - 4, top: 0, child: _marca(context, '0')),
            Positioned(
                left: x(nomMin) - 20, width: 40, top: 0, child: _marca(context, '6.5', centro: true)),
            Positioned(
                left: x(nomMax) - 20, width: 40, top: 0, child: _marca(context, '8.5', centro: true)),
            Positioned(right: lado - 6, top: 0, child: _marca(context, '14')),
            Positioned(left: lado - 4, top: 16, child: _zona(context, 'Ácido')),
            Positioned(
                left: x(nomMin),
                width: x(nomMax) - x(nomMin),
                top: 16,
                child: _zona(context, 'Norma', centro: true)),
            Positioned(right: lado - 6, top: 16, child: _zona(context, 'Alcalino')),
          ]),
        );
      }),
      if (mostrarTexto && z != null) ...[
        const SizedBox(height: Esp.s),
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
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.ag.texto2));
}
