import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../../core/ph_colors.dart';
import '../app_scope.dart';
import '../tokens.dart';

/// Indicador principal: una PECERA. El agua tiene el color del indicador
/// universal del pH actual, con olas y burbujas animadas. El borde de vidrio
/// lleva el color de ESTADO (paleta). Con movimiento reducido queda quieta.
class PhGauge extends StatefulWidget {
  const PhGauge({
    super.key,
    required this.ph,
    required this.vidrio,
    required this.aguaConColor,
    required this.atenuado,
    this.error = false,
    this.etiqueta = 'pH',
    this.size = 280,
    this.icono,
    this.onTap,
    this.accion,
  });

  final double? ph;
  final Color vidrio; // color de estado (borde)
  final bool aguaConColor; // false → agua gris (sin datos / falla de sensor)
  final bool atenuado; // datos viejos
  final bool error; // velo rojo + acción
  final String etiqueta;
  final double size;
  final IconData? icono;
  final VoidCallback? onTap;
  final String? accion;

  @override
  State<PhGauge> createState() => _PhGaugeState();
}

class _PhGaugeState extends State<PhGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _olas =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducirMovimiento(context)) {
      _olas.stop();
    } else if (!_olas.isAnimating) {
      _olas.repeat();
    }
  }

  @override
  void dispose() {
    _olas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final dur = animDur(context, 600);
    final size = widget.size;

    final gauge = AnimatedOpacity(
      duration: dur,
      opacity: widget.atenuado ? 0.5 : 1,
      child: TweenAnimationBuilder<double>(
        duration: dur,
        curve: Curves.easeOutCubic,
        tween: Tween(end: widget.ph ?? 7.0),
        builder: (context, v, _) {
          final agua = widget.aguaConColor
              ? phIndicatorColor(v)
              : Palette.sinDatos;
          // El número va dentro del agua: se elige el color más legible.
          final base = widget.error ? Color.lerp(agua, Palette.error, 0.55)! : agua;
          final txt = Palette.textoSobre(base);
          return SizedBox(
            width: size,
            height: size,
            child: AnimatedBuilder(
              animation: _olas,
              builder: (context, child) => CustomPaint(
                painter: _PeceraPainter(
                  t: _olas.value,
                  agua: agua,
                  vidrio: widget.vidrio,
                  fondoVidrio: c.superficie2,
                  error: widget.error,
                  oscuro: c.oscuro,
                ),
                child: child,
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.icono != null)
                    Icon(widget.icono, color: txt, size: size * 0.1),
                  Text(
                    widget.ph == null ? '—' : v.toStringAsFixed(2), // nunca 3 decimales
                    style: TextStyle(
                      fontSize: size * 0.23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                      height: 1.0,
                      color: txt,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10)
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (widget.accion != null)
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: size * 0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Palette.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.accion!,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: math.max(13, size * 0.05),
                          fontWeight: FontWeight.w800,
                          color: Palette.blanco,
                        ),
                      ),
                    )
                  else
                    Text(
                      widget.etiqueta,
                      style: TextStyle(
                        fontSize: size * 0.06,
                        fontWeight: FontWeight.w700,
                        color: txt.withValues(alpha: 0.85),
                      ),
                    ),
                ]),
              ),
            ),
          );
        },
      ),
    );

    final sem = widget.ph == null
        ? 'pH sin datos'
        : 'pH ${widget.ph!.toStringAsFixed(2)}';
    if (widget.onTap == null) return Semantics(label: sem, child: gauge);
    return Semantics(
      button: true,
      label: '$sem. ${widget.accion ?? ''}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: gauge,
        ),
      ),
    );
  }
}

class _PeceraPainter extends CustomPainter {
  _PeceraPainter({
    required this.t,
    required this.agua,
    required this.vidrio,
    required this.fondoVidrio,
    required this.error,
    required this.oscuro,
  });

  final double t; // 0–1, fase de la animación
  final Color agua;
  final Color vidrio;
  final Color fondoVidrio;
  final bool error;
  final bool oscuro;

  static const _nivel = 0.66; // fracción del diámetro con agua
  static const _burbujas = [
    (0.30, 0.00, 0.020, 1.0),
    (0.46, 0.35, 0.014, 1.3),
    (0.62, 0.65, 0.018, 0.9),
    (0.72, 0.15, 0.011, 1.5),
    (0.38, 0.80, 0.012, 1.2),
  ]; // (x, desfase, radio, velocidad)

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final rExt = math.min(size.width, size.height) / 2;
    final borde = rExt * (error ? 0.075 : 0.05);
    final r = rExt - borde;
    final circulo = Rect.fromCircle(center: centro, radius: r);

    // Sombra suave de color del agua (solo en claro)
    if (!oscuro) {
      canvas.drawCircle(
        centro.translate(0, rExt * 0.08),
        r * 0.92,
        Paint()
          ..color = agua.withValues(alpha: 0.28)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rExt * 0.12),
      );
    }

    // Vidrio (interior vacío)
    canvas.drawCircle(centro, r, Paint()..color = fondoVidrio);

    canvas.save();
    canvas.clipPath(Path()..addOval(circulo));

    final top = circulo.top + (1 - _nivel) * circulo.height;
    final amp = r * 0.035;
    final fase = t * 2 * math.pi;

    Path ola(double desfase, double ampl, double frecuencia) {
      final p = Path()..moveTo(circulo.left, circulo.bottom);
      p.lineTo(circulo.left, top);
      for (var x = 0.0; x <= circulo.width; x += 4) {
        final y = top +
            math.sin((x / circulo.width) * 2 * math.pi * frecuencia + fase + desfase) *
                ampl;
        p.lineTo(circulo.left + x, y);
      }
      p.lineTo(circulo.right, circulo.bottom);
      p.close();
      return p;
    }

    // Ola de atrás (más clara) y de adelante (con degradado)
    canvas.drawPath(
      ola(math.pi * 0.8, amp * 0.8, 1.3),
      Paint()..color = Color.lerp(agua, Palette.blanco, 0.35)!.withValues(alpha: 0.65),
    );
    canvas.drawPath(
      ola(0, amp, 1.0),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(agua, Palette.blanco, 0.12)!,
            Color.lerp(agua, Palette.tinta, 0.22)!,
          ],
        ).createShader(Rect.fromLTRB(circulo.left, top, circulo.right, circulo.bottom)),
    );

    // Burbujas que suben (solo dentro del agua)
    final altoAgua = circulo.bottom - top;
    for (final (bx, desf, br, vel) in _burbujas) {
      final avance = (t * vel + desf) % 1.0;
      final y = circulo.bottom - avance * altoAgua * 0.95;
      final x = circulo.left + bx * circulo.width + math.sin(avance * 6 + desf * 9) * r * 0.03;
      final radio = r * br * (0.7 + 0.6 * avance);
      canvas.drawCircle(
        Offset(x, y),
        radio,
        Paint()
          ..color = Palette.blanco.withValues(alpha: 0.35 * (1 - avance * 0.6))
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r * 0.006),
      );
    }

    // Velo rojo si hay error en el equipo
    if (error) {
      canvas.drawRect(circulo, Paint()..color = Palette.error.withValues(alpha: 0.42));
    }

    // Reflejo del vidrio
    canvas.drawArc(
      circulo.deflate(r * 0.1),
      math.pi * 1.08,
      math.pi * 0.32,
      false,
      Paint()
        ..color = Palette.blanco.withValues(alpha: oscuro ? 0.18 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.045,
    );
    canvas.restore();

    // Borde de vidrio con el color de estado
    canvas.drawCircle(
      centro,
      rExt - borde / 2,
      Paint()
        ..color = vidrio
        ..style = PaintingStyle.stroke
        ..strokeWidth = borde,
    );
  }

  @override
  bool shouldRepaint(_PeceraPainter o) =>
      o.t != t ||
      o.agua != agua ||
      o.vidrio != vidrio ||
      o.error != error ||
      o.fondoVidrio != fondoVidrio;
}
