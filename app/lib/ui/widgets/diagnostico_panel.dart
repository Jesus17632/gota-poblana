import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';
import '../../state/diagnostico.dart';
import '../app_scope.dart';
import 'common.dart';

/// Test completo estilo "arranque de Linux": cada verificación aparece en su
/// línea con [ OK ] / [FALLA] / [AVISO], pero con el diseño de la app.
class DiagnosticoPanel extends StatelessWidget {
  const DiagnosticoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = s.diagnostico;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        if (!d.visible) return const SizedBox.shrink();
        final visibles = d.pasos
            .where((p) => p.resultado != ResultadoPaso.pendiente)
            .toList();
        final total = d.pasos.length;
        final hechos = d.pasos.where((p) => p.hecho).length;

        return SectionCard(
          title: 'Test de hardware y conectividad',
          trailing: IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close),
            onPressed: d.cerrar,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: d.progreso,
                minHeight: 6,
                color: d.contar(ResultadoPaso.falla) > 0
                    ? Palette.error
                    : Palette.normal,
                backgroundColor: Palette.pista,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              d.terminado
                  ? 'Terminado en ${(d.fin!.difference(d.inicio!).inMilliseconds / 1000).toStringAsFixed(1)} s'
                  : 'Verificando $hechos de $total…',
              style: const TextStyle(
                  fontSize: 12, color: Palette.textoSecundario),
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: animDur(context, 200),
              alignment: Alignment.topCenter,
              child: Column(children: [
                for (final p in visibles)
                  _Linea(key: ValueKey(p.id), paso: p),
              ]),
            ),
            if (d.terminado) ...[
              const SizedBox(height: 12),
              _Resumen(d: d),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Repetir'),
                    onPressed: s.iniciarDiagnostico,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: d.cerrar,
                    child: const Text('Listo'),
                  ),
                ),
              ]),
            ],
          ]),
        );
      },
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({super.key, required this.paso});
  final PasoDiagnostico paso;

  @override
  Widget build(BuildContext context) {
    final reducir = reducirMovimiento(context);
    final contenido = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Etiqueta(resultado: paso.resultado),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(paso.titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            if (paso.detalle != null)
              Text(paso.detalle!,
                  style: const TextStyle(
                      fontSize: 13, color: Palette.textoSecundario)),
          ]),
        ),
        if (paso.duracion != null)
          Text('${paso.duracion!.inMilliseconds} ms',
              style: const TextStyle(
                  fontSize: 11,
                  color: Palette.textoSecundario,
                  fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
    if (reducir) return contenido;
    // Entrada suave de cada línea nueva.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: child),
      ),
      child: contenido,
    );
  }
}

/// Etiqueta tipo [ OK ] con color por significado y texto siempre legible.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.resultado});
  final ResultadoPaso resultado;

  @override
  Widget build(BuildContext context) {
    final (String txt, Color color, IconData? icon) = switch (resultado) {
      ResultadoPaso.ok => ('OK', Palette.normal, Icons.check),
      ResultadoPaso.aviso => ('AVISO', Palette.precaucion, Icons.priority_high),
      ResultadoPaso.falla => ('FALLA', Palette.error, Icons.close),
      ResultadoPaso.omitido => ('OMITIDO', Palette.sinDatos, Icons.remove),
      ResultadoPaso.corriendo => ('…', Palette.dosificando, null),
      ResultadoPaso.pendiente => ('', Palette.pista, null),
    };
    final fg = Palette.textoSobre(color);
    return Container(
      width: 92,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: resultado == ResultadoPaso.corriendo
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
              Text(txt,
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      letterSpacing: 0.5)),
            ]),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.d});
  final Diagnostico d;

  @override
  Widget build(BuildContext context) {
    final fallas = d.contar(ResultadoPaso.falla);
    final avisos = d.contar(ResultadoPaso.aviso);
    final ok = d.contar(ResultadoPaso.ok);
    final (Color c, IconData i, String t) = fallas > 0
        ? (Palette.error, Icons.error, '$fallas con falla · $avisos con aviso · $ok correctas')
        : avisos > 0
            ? (Palette.precaucion, Icons.warning_amber_rounded,
                '$avisos con aviso · $ok correctas')
            : (Palette.normal, Icons.verified, 'Todo en orden · $ok correctas');
    return AvisoLinea(color: c, icon: i, text: t);
  }
}
