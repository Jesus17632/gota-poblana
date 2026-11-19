import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../../data/models.dart';
import 'common.dart';

/// Lista de fallas de hardware reportadas por el ESP32 (técnico).
class FallasCard extends StatelessWidget {
  const FallasCard({super.key, required this.fallas});
  final List<FallaHw> fallas;

  @override
  Widget build(BuildContext context) {
    final criticas = fallas.where((f) => f.critica).length;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: criticas > 0 ? Palette.error : Palette.precaucion, width: 2),
      ),
      child: SectionCard(
        title: 'Fallas de hardware (${fallas.length})',
        trailing: Icon(
          criticas > 0 ? Icons.error : Icons.warning_amber_rounded,
          color: criticas > 0 ? Palette.error : Palette.textoSecundario,
        ),
        child: Column(children: [
          for (final f in fallas) _FilaFalla(falla: f),
          if (criticas > 0) ...[
            const SizedBox(height: 4),
            const Text(
              'Con fallas críticas el equipo bloquea la bomba. '
              'Corrige la causa y pulsa "Detener" para limpiar el error.',
              style: TextStyle(fontSize: 12, color: Palette.textoSecundario),
            ),
          ],
        ]),
      ),
    );
  }
}

class _FilaFalla extends StatelessWidget {
  const _FilaFalla({required this.falla});
  final FallaHw falla;

  @override
  Widget build(BuildContext context) {
    final info = falla.info;
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
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            if (falla.detalle != null)
              Text(falla.detalle!,
                  style: const TextStyle(color: Palette.textoSecundario)),
            Text(info.queHacer, style: const TextStyle(fontSize: 13)),
            Text(
              '${falla.critica ? 'Crítica' : 'Advertencia'} · ${falla.codigo}',
              style: const TextStyle(
                  fontSize: 11, color: Palette.textoSecundario),
            ),
          ]),
        ),
      ]),
    );
  }
}
