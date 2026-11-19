import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../../core/ph_colors.dart';
import '../app_scope.dart';

/// Indicador circular del diseño: círculo relleno con el color de ESTADO
/// (paleta) y, alrededor, un anillo con el color del INDICADOR UNIVERSAL.
class PhGauge extends StatelessWidget {
  const PhGauge({
    super.key,
    required this.ph,
    required this.relleno,
    required this.mostrarIndicador,
    required this.atenuado,
    this.etiqueta = 'pH',
    this.size = 280,
    this.icono,
    this.onTap,
    this.accion,
  });

  final double? ph;
  final Color relleno; // color de estado (paleta)
  final bool mostrarIndicador; // false → anillo gris (sin datos / falla)
  final bool atenuado; // datos viejos
  final String etiqueta;
  final double size;
  final IconData? icono; // p. ej. falla de sensor
  final VoidCallback? onTap; // círculo tocable (p. ej. "Hacer test de errores")
  final String? accion; // texto de la acción, va en lugar de la etiqueta

  @override
  Widget build(BuildContext context) {
    final dur = animDur(context, 500);
    final textoColor = Palette.textoSobre(relleno);
    final gauge = AnimatedOpacity(
        duration: dur,
        opacity: atenuado ? 0.45 : 1,
        child: TweenAnimationBuilder<double>(
          duration: dur,
          curve: Curves.easeOutCubic,
          tween: Tween(end: ph ?? 7.0),
          builder: (context, v, _) {
            final anillo = mostrarIndicador
                ? phIndicatorColor(v)
                : Palette.sinDatos.withValues(alpha: 0.35);
            return SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _RingPainter(anillo),
                child: Padding(
                  padding: EdgeInsets.all(size * 0.075),
                  child: AnimatedContainer(
                    duration: dur,
                    decoration: BoxDecoration(
                      color: relleno,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: relleno.withValues(alpha: 0.30),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icono != null)
                          Icon(icono, color: textoColor, size: size * 0.1),
                        Text(
                          // pH con 2 decimales, nunca 3
                          ph == null ? '—' : v.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: size * 0.24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            height: 1.0,
                            color: textoColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (accion != null)
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: size * 0.1),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: textoColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              accion!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: size * 0.055,
                                fontWeight: FontWeight.w800,
                                color: textoColor,
                              ),
                            ),
                          )
                        else
                          Text(
                            etiqueta,
                            style: TextStyle(
                              fontSize: size * 0.06,
                              fontWeight: FontWeight.w700,
                              color: textoColor.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

    final etiquetaSem =
        ph == null ? 'pH sin datos' : 'pH ${ph!.toStringAsFixed(2)}';
    if (onTap == null) {
      return Semantics(label: etiquetaSem, child: gauge);
    }
    return Semantics(
      button: true,
      label: '$etiquetaSem. ${accion ?? ''}',
      // Sin recorte, para no cortar la sombra del círculo.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
            customBorder: const CircleBorder(), onTap: onTap, child: gauge),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2;
    final stroke = r * 0.07;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(size.center(Offset.zero), r - stroke / 2, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
