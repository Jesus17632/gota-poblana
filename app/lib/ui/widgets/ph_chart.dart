import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/chem.dart';
import '../../core/palette.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../tokens.dart';

/// Gráfico de pH vs tiempo dibujado a mano (sin dependencias):
/// banda 6.5–8.5 sombreada, umbral opcional, marcadores de eventos y
/// % HOCl opcional en un segundo eje.
class PhChart extends StatelessWidget {
  const PhChart({
    super.key,
    required this.lecturas,
    required this.desde,
    required this.hasta,
    this.umbral,
    this.mostrarHocl = false,
    this.mostrarEventos = false,
    this.height = 240,
  });

  final List<Lectura> lecturas;
  final DateTime desde;
  final DateTime hasta;
  final double? umbral;
  final bool mostrarHocl;
  final bool mostrarEventos;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(
          c: context.ag,
          lecturas: lecturas,
          desde: desde,
          hasta: hasta,
          umbral: umbral,
          mostrarHocl: mostrarHocl,
          mostrarEventos: mostrarEventos,
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.c,
    required this.lecturas,
    required this.desde,
    required this.hasta,
    required this.umbral,
    required this.mostrarHocl,
    required this.mostrarEventos,
  });

  final AguaColors c;
  final List<Lectura> lecturas;
  final DateTime desde;
  final DateTime hasta;
  final double? umbral;
  final bool mostrarHocl;
  final bool mostrarEventos;

  Color get _hoclColor => c.texto2;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
        36, 10, size.width - (mostrarHocl ? 42 : 10), size.height - 24);
    if (plot.width <= 0 || plot.height <= 0) return;

    final rango = AppState.rangoPh(lecturas, umbral: umbral);
    var yMin = rango.min, yMax = rango.max;
    if (yMax - yMin < 2) yMax = yMin + 2;
    final spanMs =
        math.max(1, hasta.millisecondsSinceEpoch - desde.millisecondsSinceEpoch);

    double x(DateTime t) =>
        plot.left +
        (t.millisecondsSinceEpoch - desde.millisecondsSinceEpoch) /
            spanMs *
            plot.width;
    double y(double ph) =>
        plot.bottom - (ph - yMin) / (yMax - yMin) * plot.height;
    double y2(double pct) => plot.bottom - pct / 100 * plot.height;

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height));

    // Banda de la norma
    final bandTop = y(nomMax).clamp(plot.top, plot.bottom);
    final bandBot = y(nomMin).clamp(plot.top, plot.bottom);
    canvas.drawRect(
      Rect.fromLTRB(plot.left, bandTop, plot.right, bandBot),
      Paint()..color = Palette.normal.withValues(alpha: c.oscuro ? 0.16 : 0.10),
    );

    // Rejilla y etiquetas del eje pH
    final grid = Paint()
      ..color = c.linea
      ..strokeWidth = 1;
    final paso = (yMax - yMin) > 6 ? 2 : 1;
    for (var v = yMin.ceil(); v <= yMax; v += paso) {
      final yy = y(v.toDouble());
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      _texto(canvas, v.toString(), Offset(plot.left - 6, yy),
          alignRight: true);
    }

    // Eje secundario % HOCl
    if (mostrarHocl) {
      for (final p in [0, 50, 100]) {
        _texto(canvas, '$p%', Offset(plot.right + 6, y2(p.toDouble())),
            color: _hoclColor);
      }
    }

    // Etiquetas de tiempo
    final unDia = hasta.difference(desde) <= const Duration(hours: 24);
    String ft(DateTime t) => unDia ? hhmm(t) : '${ddmm(t)} ${hhmm(t)}';
    final medio = desde.add(hasta.difference(desde) ~/ 2);
    _texto(canvas, ft(desde), Offset(plot.left, plot.bottom + 12));
    _texto(canvas, ft(medio), Offset(x(medio), plot.bottom + 12),
        center: true);
    _texto(canvas, ft(hasta), Offset(plot.right, plot.bottom + 12),
        alignRight: true);

    if (lecturas.isEmpty) {
      _texto(canvas, 'Sin datos en este periodo', plot.center,
          center: true, size: 14);
      canvas.restore();
      return;
    }

    canvas.clipRect(plot.inflate(4));

    // Umbral
    if (umbral != null) {
      final yy = y(umbral!);
      _dashed(canvas, Offset(plot.left, yy), Offset(plot.right, yy),
          Paint()
            ..color = Palette.dosificando
            ..strokeWidth = 1.5);
      _texto(canvas, 'umbral ${umbral!.toStringAsFixed(2)}',
          Offset(plot.right - 4, yy - 9),
          alignRight: true, color: Palette.dosificando);
    }

    // Cortes en la línea si hay huecos grandes
    final hueco = math.max(180000, spanMs ~/ 60);

    Path serie(double Function(Lectura) fy, bool Function(Lectura) ok) {
      final path = Path();
      Lectura? prev;
      for (final l in lecturas) {
        if (!ok(l)) {
          prev = null;
          continue;
        }
        final pt = Offset(x(l.t), fy(l));
        if (prev == null ||
            l.t.millisecondsSinceEpoch - prev.t.millisecondsSinceEpoch >
                hueco) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
        prev = l;
      }
      return path;
    }

    if (mostrarHocl) {
      canvas.drawPath(
        serie((l) => y2(l.hoclPct ?? 0), (l) => l.hoclPct != null),
        Paint()
          ..color = _hoclColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    canvas.drawPath(
      serie((l) => y(l.ph), (_) => true),
      Paint()
        ..color = Palette.normal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Eventos
    if (mostrarEventos) {
      for (final l in lecturas.where((l) => l.evento != null)) {
        final xx = x(l.t);
        switch (l.evento) {
          case 'inicio':
          case 'fin':
            final ec =
                l.evento == 'inicio' ? Palette.dosificando : Palette.normal;
            canvas.drawLine(Offset(xx, plot.top), Offset(xx, plot.bottom),
                Paint()
                  ..color = ec
                  ..strokeWidth = 1.5);
            _texto(canvas, l.evento!, Offset(xx + 3, plot.top + 6), color: ec);
          case 'pulso':
            final pc = Offset(xx, y(l.ph));
            canvas.drawCircle(pc, 4.5, Paint()..color = Palette.mezclando);
            canvas.drawCircle(
                pc,
                4.5,
                Paint()
                  ..color = c.texto
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1);
        }
      }
    }
    canvas.restore();
  }

  void _dashed(Canvas cv, Offset a, Offset b, Paint p) {
    const dash = 6.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final e = math.min(d + dash, total);
      cv.drawLine(a + dir * d, a + dir * e, p);
      d = e + gap;
    }
  }

  void _texto(Canvas cv, String s, Offset at,
      {bool alignRight = false,
      bool center = false,
      Color? color,
      double size = 11}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size, color: color ?? c.texto2, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(cv, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
