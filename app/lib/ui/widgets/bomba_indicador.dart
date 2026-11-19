import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../app_scope.dart';
import '../tokens.dart';

/// "Bomba encendida/apagada" con punto animado (sin animación si el
/// movimiento reducido está activo). Refleja SOLO lo que reporta el equipo.
class BombaIndicador extends StatefulWidget {
  const BombaIndicador({super.key, required this.encendida});
  final bool encendida;

  @override
  State<BombaIndicador> createState() => _BombaIndicadorState();
}

class _BombaIndicadorState extends State<BombaIndicador>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  bool _animar = false;

  void _sincronizar() {
    _animar = widget.encendida && !reducirMovimiento(context);
    if (_animar && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!_animar && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sincronizar();
  }

  @override
  void didUpdateWidget(BombaIndicador old) {
    super.didUpdateWidget(old);
    _sincronizar();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animar = _animar;
    final color = widget.encendida ? Palette.dosificando : Palette.sinDatos;
    return Semantics(
      liveRegion: true,
      label: widget.encendida ? 'Bomba encendida' : 'Bomba apagada',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: animar
              ? Tween(begin: 0.3, end: 1.0).animate(_c)
              : const AlwaysStoppedAnimation(1.0),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: widget.encendida
                  ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(widget.encendida ? Icons.power : Icons.power_off,
            size: 18, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
          widget.encendida ? 'Bomba encendida' : 'Bomba apagada',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: context.ag.texto),
          ),
        ),
      ]),
    );
  }
}
