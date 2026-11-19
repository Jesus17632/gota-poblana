// Vista de varios nodos. Por ahora solo el nodo conectado es real; los demás
// son DATOS DE DEMOSTRACIÓN para mostrar cómo se verá la red.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/chem.dart';
import '../core/palette.dart';
import '../core/ph_colors.dart';
import 'app_scope.dart';
import 'format.dart';
import 'tokens.dart';
import 'widgets/common.dart';
import 'widgets/ph_escala.dart';

enum _EstadoNodo { enNorma, fueraNorma, falla, sinConexion }

class _Nodo {
  const _Nodo({
    required this.id,
    required this.nombre,
    required this.ubicacion,
    required this.ph,
    required this.estado,
    required this.visto,
    this.detalle,
    this.real = false,
  });
  final String id;
  final String nombre;
  final String ubicacion;
  final double? ph;
  final _EstadoNodo estado;
  final DateTime? visto;
  final String? detalle;
  final bool real;
}

/// Nodos de demostración con pH que varía suavemente con el tiempo.
List<_Nodo> _demo(DateTime ahora) {
  final t = ahora.millisecondsSinceEpoch / 1000;
  double ola(double base, double amp, double periodo, double fase) =>
      base + amp * math.sin(t / periodo + fase);
  final p2 = ola(7.35, 0.08, 40, 0);
  final p3 = ola(6.25, 0.05, 55, 1);
  return [
    _Nodo(
      id: 'nodo2',
      nombre: 'Tanque norte',
      ubicacion: 'Colonia Centro',
      ph: p2,
      estado: _EstadoNodo.enNorma,
      visto: ahora.subtract(const Duration(seconds: 3)),
    ),
    _Nodo(
      id: 'nodo3',
      nombre: 'Escuela primaria',
      ubicacion: 'Calle Morelos 12',
      ph: p3,
      estado: _EstadoNodo.fueraNorma,
      visto: ahora.subtract(const Duration(seconds: 5)),
    ),
    _Nodo(
      id: 'nodo4',
      nombre: 'Centro de salud',
      ubicacion: 'Av. Juárez',
      ph: ola(7.05, 0.04, 70, 2),
      estado: _EstadoNodo.falla,
      visto: ahora.subtract(const Duration(seconds: 2)),
      detalle: 'Bomba desconectada',
    ),
    _Nodo(
      id: 'nodo5',
      nombre: 'Pozo 3',
      ubicacion: 'Ejido San José',
      ph: 7.48,
      estado: _EstadoNodo.sinConexion,
      visto: ahora.subtract(const Duration(hours: 2, minutes: 14)),
    ),
  ];
}

({Color color, String texto, IconData icono}) _estilo(_EstadoNodo e) => switch (e) {
      _EstadoNodo.enNorma => (color: Palette.normal, texto: 'En norma', icono: Icons.check_circle),
      _EstadoNodo.fueraNorma =>
        (color: Palette.error, texto: 'Fuera de norma', icono: Icons.warning_rounded),
      _EstadoNodo.falla => (color: Palette.error, texto: 'Falla del equipo', icono: Icons.build_circle),
      _EstadoNodo.sinConexion =>
        (color: Palette.sinDatos, texto: 'Sin conexión', icono: Icons.cloud_off),
    };

class NodosPage extends StatelessWidget {
  const NodosPage({super.key, required this.abrirInicio});

  /// Al tocar el nodo real se abre Inicio.
  final VoidCallback abrirInicio;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final ahora = s.ahora;

    final t = s.ultimo;
    final _EstadoNodo estadoReal = s.sinConexion || !s.hayDatos
        ? _EstadoNodo.sinConexion
        : s.hayErrorEquipo
            ? _EstadoNodo.falla
            : (nomStatus(t!.ph) == NomStatus.enRango
                ? _EstadoNodo.enNorma
                : _EstadoNodo.fueraNorma);
    final real = _Nodo(
      id: s.nodo,
      nombre: s.ubicacion == sinValor ? 'Este equipo' : s.ubicacion,
      ubicacion: s.simulado ? 'Simulador' : s.fuenteDescripcion,
      ph: t?.ph,
      estado: estadoReal,
      visto: s.recibido,
      detalle: s.errorEquipoTexto,
      real: true,
    );
    final nodos = [real, ..._demo(ahora)];

    int cuenta(_EstadoNodo e) => nodos.where((n) => n.estado == e).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Resumen de la red
      Row(children: [
        for (final e in _EstadoNodo.values) ...[
          Expanded(
            child: _Contador(
              valor: cuenta(e),
              texto: _estilo(e).texto,
              color: _estilo(e).color,
            ),
          ),
          if (e != _EstadoNodo.values.last) const SizedBox(width: Esp.s),
        ],
      ]),
      const SizedBox(height: Esp.m),
      AvisoLinea(
        color: Palette.precaucion,
        icon: Icons.science_outlined,
        text: 'Solo "${real.id}" es real. Los demás son datos de demostración.',
      ),
      const SizedBox(height: Esp.l),
      LayoutBuilder(builder: (context, cons) {
        final cols = cons.maxWidth >= 900 ? 3 : (cons.maxWidth >= 520 ? 2 : 1);
        const gap = Esp.m;
        final w = (cons.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final n in nodos)
            SizedBox(
              width: w,
              height: 132,
              child: _TarjetaNodo(
                n: n,
                ahora: ahora,
                onTap: n.real ? abrirInicio : () => _detalle(context, n),
              ),
            ),
          SizedBox(
            width: w,
            height: 132,
            child: _AgregarNodo(onTap: () => _agregar(context)),
          ),
        ]);
      }),
      const SizedBox(height: Esp.s),
      Text('Cada nodo es un ESP32 con su propio tema MQTT: agua/<nodo>/…',
          style: TextStyle(fontSize: 12, color: c.texto2)),
    ]);
  }

  void _detalle(BuildContext context, _Nodo n) {
    final st = _estilo(n.estado);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.ag.superficie,
      builder: (ctx) {
        final c = ctx.ag;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Esp.xl, 0, Esp.xl, Esp.xl),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(n.nombre, style: Theme.of(ctx).textTheme.headlineSmall)),
              const _Insignia(texto: 'DEMO', color: Palette.precaucion),
            ]),
            Text('${n.id} · ${n.ubicacion}', style: TextStyle(color: c.texto2)),
            const SizedBox(height: Esp.l),
            StatusDot(color: st.color, text: n.detalle ?? st.texto, icon: st.icono),
            const SizedBox(height: Esp.l),
            if (n.estado != _EstadoNodo.sinConexion) PhEscala(ph: n.ph) else
              Text('Última lectura: pH ${fmtPh(n.ph)} · ${haceTiempo(n.visto, DateTime.now())}',
                  style: TextStyle(color: c.texto)),
            const SizedBox(height: Esp.m),
            Text('Vista previa con datos de demostración.',
                style: TextStyle(fontSize: 12, color: c.texto2)),
          ]),
        );
      },
    );
  }

  void _agregar(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Agregar nodo'),
          content: const Text(
              'Próximamente. Cada equipo nuevo será otro ESP32 con su propio nombre de '
              'nodo (por ejemplo nodo2) que publica en agua/nodo2/…, y aparecerá aquí.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ],
        ),
      );
}

class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.texto, required this.color});
  final int valor;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: Esp.m, vertical: Esp.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$valor', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.texto)),
        const SizedBox(height: 2),
        StatusDot(color: color, text: texto, bold: false, size: 12),
      ]),
    );
  }
}

class _TarjetaNodo extends StatelessWidget {
  const _TarjetaNodo({required this.n, required this.ahora, required this.onTap});
  final _Nodo n;
  final DateTime ahora;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final st = _estilo(n.estado);
    final conColor = n.ph != null && n.estado != _EstadoNodo.sinConexion;
    final agua = conColor ? phIndicatorColor(n.ph!) : Palette.sinDatos;
    return Material(
      color: c.superficie,
      borderRadius: BorderRadius.circular(Esp.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Esp.radio),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Esp.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Esp.radio),
            border: Border.all(
                color: n.estado == _EstadoNodo.enNorma ? c.linea : st.color.withValues(alpha: 0.6),
                width: 1.2),
          ),
          child: Row(children: [
            // Mini pecera
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.34, 0.34, 1.0],
                  colors: [c.superficie2, c.superficie2, agua, Color.lerp(agua, Palette.tinta, 0.2)!],
                ),
                border: Border.all(color: st.color, width: 3),
              ),
              child: Text(
                fmtPh(n.ph),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Palette.textoSobre(agua),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: Esp.l),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(n.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.texto)),
                    ),
                    _Insignia(
                      texto: n.real ? 'EN VIVO' : 'DEMO',
                      color: n.real ? Palette.dosificando : Palette.precaucion,
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('${n.id} · ${n.ubicacion}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.texto2)),
                  const SizedBox(height: Esp.s),
                  StatusDot(
                      color: st.color,
                      text: n.estado == _EstadoNodo.falla && n.detalle != null ? n.detalle! : st.texto,
                      icon: st.icono,
                      size: 13),
                  const SizedBox(height: 2),
                  Text(haceTiempo(n.visto, ahora), style: TextStyle(fontSize: 12, color: c.texto2)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto, required this.color});
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(texto,
          style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w800,
              color: Palette.textoSobre(color))),
    );
  }
}

class _AgregarNodo extends StatelessWidget {
  const _AgregarNodo({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Esp.radio),
      child: InkWell(
        borderRadius: BorderRadius.circular(Esp.radio),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Esp.radio),
            border: Border.all(color: c.linea, width: 1.5),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_circle_outline, size: 28, color: c.texto2),
              const SizedBox(height: 6),
              Text('Agregar nodo',
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.texto2)),
            ]),
          ),
        ),
      ),
    );
  }
}
