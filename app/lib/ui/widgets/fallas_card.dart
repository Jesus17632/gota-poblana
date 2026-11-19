import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../../data/models.dart';
import '../tokens.dart';
import 'common.dart';

/// Lista de fallas de hardware reportadas por el ESP32 (técnico).
class FallasCard extends StatelessWidget {
  const FallasCard({super.key, required this.fallas});
  final List<FallaHw> fallas;

  @override
  Widget build(BuildContext context) {
    final criticas = fallas.where((f) => f.critica).length;
    final c = context.ag;
    return SectionCard(
        borde: criticas > 0 ? Palette.error : Palette.precaucion,
        title: 'Fallas de hardware (${fallas.length})',
        trailing: Icon(
          criticas > 0 ? Icons.error : Icons.warning_amber_rounded,
          color: criticas > 0 ? Palette.error : c.texto2,
        ),
        child: Column(children: [
          for (final f in fallas) _FilaFalla(falla: f),
          if (criticas > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Con fallas críticas el equipo bloquea la bomba. '
              'Corrige la causa y pulsa "Detener" para limpiar el error.',
              style: TextStyle(fontSize: 12, color: c.texto2),
            ),
          ],
        ]),
    );
  }
}

class _FilaFalla extends StatelessWidget {
  const _FilaFalla({required this.falla});
  final FallaHw falla;

  @override
  Widget build(BuildContext context) {
    final info = falla.info;
    final c = context.ag;
    final color = falla.critica ? Palette.error : Palette.precaucion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: StatusDot(
            color: color,
            text: '',
            icon: falla.critica ? Icons.error : Icons.warning_amber_rounded,
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${info.titulo}${falla.modulo == null ? '' : ' · ${falla.modulo}'}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.texto),
            ),
            if (falla.detalle != null)
              Text(falla.detalle!,
                  style: TextStyle(color: c.texto2)),
            Text(info.queHacer, style: TextStyle(fontSize: 13, color: c.texto)),
            Text(
              '${falla.critica ? 'Crítica' : 'Advertencia'} · ${falla.codigo}',
              style: TextStyle(fontSize: 11, color: c.texto2),
            ),
          ]),
        ),
      ]),
    );
  }
}
