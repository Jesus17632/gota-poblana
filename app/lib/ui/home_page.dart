import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/chem.dart';
import '../core/palette.dart';
import '../data/data_source.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'app_scope.dart';
import 'format.dart';
import 'vista_estado.dart';
import 'widgets/bomba_indicador.dart';
import 'widgets/common.dart';
import 'widgets/fallas_card.dart';
import 'widgets/ph_gauge.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final ancho = c.maxWidth >= 900;
      final principal = _Principal(gaugeSize: ancho ? 320 : 260);
      final extra = <Widget>[
        if (s.esTecnico && s.fallas.isNotEmpty) ...[
          FallasCard(fallas: s.fallas),
          const SizedBox(height: 16),
        ],
        if (s.esTecnico) ...[
          const _PanelControlador(),
          const SizedBox(height: 16),
          const _PanelObjetivo(),
          const SizedBox(height: 16),
        ],
        const _Promedio24h(),
      ];
      if (ancho) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: principal),
          const SizedBox(width: 24),
          Expanded(flex: 5, child: Column(children: extra)),
        ]);
      }
      return Column(children: [
        principal,
        const SizedBox(height: 24),
        ...extra,
      ]);
    });
  }
}

/// Indicador + estado + % HOCl + ubicación (lo que ve el ciudadano).
class _Principal extends StatelessWidget {
  const _Principal({required this.gaugeSize});
  final double gaugeSize;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final v = vistaDe(s);
    final hocl = s.hoclActual;
    final tecnico = s.esTecnico;
    final ctrl = textoControlador(s.ultimo);

    return Column(children: [
      const SizedBox(height: 8),
      PhGauge(
        ph: s.ultimo?.ph,
        relleno: v.relleno,
        mostrarIndicador: v.indicador,
        atenuado: v.atenuado,
        size: gaugeSize,
        icono: s.sensorOk ? null : v.icono,
      ),
      const SizedBox(height: 20),
      if (tecnico && s.hayDatos) ...[
        StatusDot(color: ctrl.color, text: ctrl.texto, icon: ctrl.icono),
        const SizedBox(height: 10),
      ],
      StatusDot(
        color: v.punto,
        text: v.titulo,
        icon: v.icono,
      ),
      if (v.detalle != null) ...[
        const SizedBox(height: 8),
        Text(v.detalle!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 16, color: Palette.textoSecundario, height: 1.35)),
      ],
      if (v.queHacer != null) ...[
        const SizedBox(height: 12),
        AvisoLinea(
          color: v.punto == Palette.sinDatos ? Palette.sinDatos : Palette.error,
          icon: Icons.info_outline,
          text: v.queHacer!,
        ),
      ],
      if (!tecnico && s.hayFallasCriticas) ...[
        const SizedBox(height: 12),
        const AvisoLinea(
          color: Palette.sinDatos,
          icon: Icons.build_circle_outlined,
          text: 'El equipo reporta una falla; el operador fue notificado.',
        ),
      ],
      const SizedBox(height: 16),
      if (hocl != null && s.sensorOk)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: Text('El cloro trabaja al ${hocl.round()} %',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: '¿Qué significa?',
            icon: const Icon(Icons.info_outline, size: 20),
            color: Palette.textoSecundario,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('¿Qué significa?'),
                content: const Text(
                    'A menor pH, mayor parte del cloro está como ácido '
                    'hipocloroso, la forma que desinfecta.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Entendido')),
                ],
              ),
            ),
          ),
        ]),
      Text(
        '${s.ubicacion} · ${haceTiempo(s.recibido, s.ahora)}',
        style: const TextStyle(fontSize: 14, color: Palette.textoSecundario),
      ),
    ]);
  }
}

/// Técnico: estado, umbral activo, distancia y ácido.
class _PanelControlador extends StatelessWidget {
  const _PanelControlador();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.ultimo;
    final umbral = t?.umbral;
    final dist = (t != null && umbral != null) ? t.ph - umbral : null;
    final acido = t?.acidoRestanteMl;
    final acidoBajo = acido != null && acido < 20;

    return SectionCard(
      title: 'Controlador',
      trailing: BombaIndicador(encendida: s.rele),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: _Dato('Umbral activo', fmtPh(umbral)),
          ),
          Expanded(
            child: _Dato('Distancia (pH − umbral)',
                dist == null ? sinValor : (dist >= 0 ? '+' : '') + fmtPh(dist)),
          ),
          Expanded(
            child: _Dato('Ácido restante', fmtNum(acido, unidad: 'mL')),
          ),
        ]),
        if (acidoBajo) ...[
          const SizedBox(height: 12),
          const AvisoLinea(
            color: Palette.precaucion,
            icon: Icons.science_outlined,
            text: 'Queda poco ácido (< 20 mL). Rellena el depósito.',
          ),
        ],
        if (s.temperatura.supuesta) ...[
          const SizedBox(height: 12),
          AvisoLinea(
            color: Palette.precaucion,
            icon: Icons.thermostat,
            text: 'Temperatura supuesta: '
                '${s.temperatura.tempC.toStringAsFixed(1)} °C',
          ),
        ],
      ]),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.label, this.valor);
  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 12, color: Palette.textoSecundario)),
      const SizedBox(height: 4),
      Text(valor,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    ]);
  }
}

/// Técnico: selector de objetivo (pH o eficacia) y botón Dosificar.
class _PanelObjetivo extends StatefulWidget {
  const _PanelObjetivo();

  @override
  State<_PanelObjetivo> createState() => _PanelObjetivoState();
}

class _PanelObjetivoState extends State<_PanelObjetivo> {
  ModoUmbral? _modo;
  double? _objPh;
  double? _metaPct;
  bool _enviando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _modo ??= s.settings.modoUmbral;
    _metaPct ??= s.settings.metaHoclPct;
    _objPh ??= roundToStep(
            (s.ultimo?.umbral ?? s.pHRecomendado), 0.05)
        .clamp(phMinUmbral, phMaxUmbral)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final temp = s.temperatura.tempC;
    final phActual = s.ultimo?.ph;
    final modo = _modo!;
    final eficacia = targetForEfficacy(
        pct: _metaPct!, tempC: temp, phActual: phActual);
    final umbral = modo == ModoUmbral.ph ? _objPh! : eficacia.ph;
    final yaSeCumple = modo == ModoUmbral.eficacia
        ? eficacia.yaSeCumple
        : (phActual != null && phActual <= umbral);
    final recomendado = s.pHRecomendado;
    final enviando = _enviando || s.enviando(Cmd.dosificar);
    final puede = !s.dosificando &&
        !s.rele &&
        !s.sinConexion &&
        s.sensorOk &&
        !s.datosViejos &&
        !yaSeCumple &&
        !enviando;

    return SectionCard(
      title: 'Objetivo',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<ModoUmbral>(
          segments: const [
            ButtonSegment(value: ModoUmbral.ph, label: Text('pH')),
            ButtonSegment(value: ModoUmbral.eficacia, label: Text('Eficacia')),
          ],
          selected: {modo},
          onSelectionChanged: (v) => setState(() => _modo = v.first),
        ),
        const SizedBox(height: 16),
        if (modo == ModoUmbral.ph) ...[
          Text('Umbral: pH ${_objPh!.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge),
          Slider(
            min: phMinUmbral,
            max: phMaxUmbral,
            divisions: ((phMaxUmbral - phMinUmbral) / 0.05).round(),
            value: _objPh!,
            label: _objPh!.toStringAsFixed(2),
            onChanged: (v) =>
                setState(() => _objPh = roundToStep(v, 0.05)),
          ),
        ] else ...[
          Text(
            '${_metaPct!.round()} % HOCl a ${temp.toStringAsFixed(0)} °C → '
            'pH ${eficacia.phSinAjuste.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Slider(
            min: 50,
            max: 99,
            divisions: 49,
            value: _metaPct!,
            label: '${_metaPct!.round()} %',
            onChanged: (v) => setState(() => _metaPct = v.roundToDouble()),
          ),
          if (eficacia.ajustadoAlMinimo)
            const AvisoLinea(
              color: Palette.precaucion,
              icon: Icons.vertical_align_bottom,
              text: 'Se ajustó al mínimo permitido: pH 4.50',
            ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(
            avatar: const Icon(Icons.auto_awesome, size: 18),
            label: Text('Recomendado: pH ${recomendado.toStringAsFixed(2)} '
                'a ${temp.toStringAsFixed(0)} °C'),
            onPressed: () => setState(() {
              _modo = ModoUmbral.ph;
              _objPh = roundToStep(recomendado, 0.05)
                  .clamp(phMinUmbral, phMaxUmbral)
                  .toDouble();
            }),
          ),
        ]),
        if (yaSeCumple) ...[
          const SizedBox(height: 12),
          const AvisoLinea(
            color: Palette.normal,
            icon: Icons.check_circle_outline,
            text: 'Ya se cumple, no hace falta dosificar '
                '(el sistema solo puede bajar el pH).',
          ),
        ],
        if (umbral < nomMin) ...[
          const SizedBox(height: 12),
          const AvisoLinea(
            color: Palette.precaucion,
            icon: Icons.warning_amber_rounded,
            text: 'Fuera del rango de agua potable (6.5–8.5); '
                'válido solo como prueba del banco.',
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: puede ? () => _confirmar(umbral) : null,
            icon: enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.water_drop),
            label: Text(enviando
                ? 'Enviando…'
                : 'Dosificar hasta pH ${umbral.toStringAsFixed(2)}'),
          ),
        ),
      ]),
    );
  }

  Future<void> _confirmar(double umbral) async {
    final s = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Iniciar dosificación?'),
        content: Text(
          'pH actual: ${fmtPh(s.ultimo?.ph)}\n'
          'Umbral: ${umbral.toStringAsFixed(2)}\n\n'
          'La bomba agregará solución ácida en pulsos hasta llegar al umbral. '
          'El equipo valida la orden y puede rechazarla.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dosificar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _enviando = true);
    try {
      await s.dosificar(umbral);
    } catch (_) {
      // El aviso con el motivo ya lo muestra el shell.
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }
}

/// Tarjeta del diseño ("Promedio semanal") adaptada a pH de 24 h.
class _Promedio24h extends StatelessWidget {
  const _Promedio24h();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ahora = s.ahora;
    final desde = ahora.subtract(const Duration(hours: 24));
    final ls = s.lecturasDesde(desde);
    final prom = ls.isEmpty
        ? null
        : ls.map((l) => l.ph).reduce((a, b) => a + b) / ls.length;

    // 8 bloques de 3 h
    const n = 8;
    final buckets = List<List<double>>.generate(n, (_) => []);
    for (final l in ls) {
      final i = (l.t.difference(desde).inMinutes / (24 * 60 / n)).floor();
      buckets[i.clamp(0, n - 1)].add(l.ph);
    }
    final medias = buckets
        .map((b) => b.isEmpty ? null : b.reduce((a, c) => a + c) / b.length)
        .toList();

    return SectionCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Promedio 24 h',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Palette.textoSecundario)),
            const SizedBox(height: 6),
            Text(fmtPh(prom),
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
          ]),
        ),
        SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < n; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _Barra(
                    altura: medias[i] == null
                        ? 0.15
                        : ((medias[i]! - 4) / 5).clamp(0.15, 1.0).toDouble(),
                    activa: i == n - 1 && medias[i] != null,
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.altura, required this.activa});
  final double altura;
  final bool activa;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: animDur(context),
      width: 18,
      height: math.max(10, 56 * altura),
      decoration: BoxDecoration(
        color: activa ? Palette.dosificando : Palette.pista,
        borderRadius: BorderRadius.circular(9),
      ),
    );
  }
}

/// Barra grande de Detener, visible en todas las vistas mientras estado ≠ IDLE.
class BarraDetener extends StatelessWidget {
  const BarraDetener({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ctrl = textoControlador(s.ultimo);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Palette.tarjeta,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ctrl.color, width: 2),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusDot(color: ctrl.color, text: ctrl.texto, icon: ctrl.icono),
              const SizedBox(height: 6),
              BombaIndicador(encendida: s.rele),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.error,
            minimumSize: const Size(150, 56),
          ),
          onPressed: () async {
            try {
              await s.detener();
            } catch (_) {}
          },
          icon: const Icon(Icons.stop_circle, size: 26),
          // Sigue activo aunque haya un envío en curso: detener se puede repetir.
          label: Text(s.enviando(Cmd.detener) ? 'Enviando…' : 'Detener',
              style: const TextStyle(fontSize: 18)),
        ),
      ]),
    );
  }
}

/// Utilidad para Data/Settings: ¿mostrar barra de detener?
/// Visible mientras el relé esté encendido o el estado ≠ IDLE.
bool mostrarDetener(AppState s) =>
    s.esTecnico &&
    (s.rele || (s.hayDatos && s.estadoCtrl != CtrlEstado.idle));
