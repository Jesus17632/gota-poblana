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
import 'shell.dart';
import 'tokens.dart';
import 'vista_estado.dart';
import 'widgets/bomba_indicador.dart';
import 'widgets/common.dart';
import 'widgets/diagnostico_panel.dart';
import 'widgets/fallas_card.dart';
import 'widgets/ph_escala.dart';
import 'widgets/ph_gauge.dart';

/// Llave del panel de diagnóstico, para desplazarse hasta él al iniciarlo.
final GlobalKey _kDiagnostico = GlobalKey();

/// Inicia el test completo y lleva la pantalla al panel (bajo la pecera).
void iniciarTest(BuildContext context) {
  final s = AppScope.of(context);
  if (s.diagnostico.corriendo) return;
  final dur = animDur(context, 350);
  s.iniciarDiagnostico();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = _kDiagnostico.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: dur, alignment: 0.1);
  });
}

/// Visible mientras el relé esté encendido o el estado ≠ IDLE.
bool mostrarDetener(AppState s) =>
    s.esTecnico && (s.rele || (s.hayDatos && s.estadoCtrl != CtrlEstado.idle));

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = Disposicion.of(context);
    return LayoutBuilder(builder: (context, c) {
      final dos = d.dosColumnas && c.maxWidth >= 560;
      final gauge = dos
          ? math.min(math.min(c.maxWidth * 0.40, d.alto * (d.compacto ? 0.62 : 0.5)), 340.0)
          : math.min(c.maxWidth * 0.78, 300.0);

      final principal = _Principal(gaugeSize: gauge);
      final resto = <Widget>[
        if (s.esTecnico && s.fallas.isNotEmpty) FallasCard(fallas: s.fallas),
        SectionCard(
          title: 'Escala de pH',
          child: PhEscala(ph: s.hayDatos && s.sensorOk ? s.ultimo!.ph : null),
        ),
        const _Resumen(),
        if (s.esTecnico) ...const [_PanelControlador(), _PanelObjetivo()],
        const _Promedio24h(),
        // Sin errores, el test queda al final como botón rectangular.
        if (!s.hayErrorEquipo) const _BotonTest(),
      ];
      final columna = Column(children: [
        for (var i = 0; i < resto.length; i++) ...[
          if (i > 0) const SizedBox(height: Esp.m),
          resto[i],
        ],
      ]);

      if (dos) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: c.maxWidth * 0.44, child: principal),
          const SizedBox(width: Esp.xl),
          Expanded(child: columna),
        ]);
      }
      return Column(children: [
        principal,
        const SizedBox(height: Esp.xl),
        columna,
      ]);
    });
  }
}

/// Pecera + estado + test (lo primero que se ve).
class _Principal extends StatelessWidget {
  const _Principal({required this.gaugeSize});
  final double gaugeSize;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final v = vistaDe(s);
    final ctrl = textoControlador(s.ultimo);
    final error = s.hayErrorEquipo;

    return Column(children: [
      PhGauge(
        ph: s.ultimo?.ph,
        vidrio: v.relleno,
        aguaConColor: v.indicador,
        atenuado: v.atenuado,
        error: error,
        size: gaugeSize,
        icono: s.sensorOk ? null : v.icono,
        // Con error reportado por el ESP32: toca la pecera para el test.
        accion: error ? 'Hacer test de errores' : null,
        onTap: error ? () => iniciarTest(context) : null,
      ),
      const SizedBox(height: Esp.l),
      StatusDot(color: v.punto, text: v.titulo, icon: v.icono, size: 17),
      if (v.detalle != null) ...[
        const SizedBox(height: 6),
        Text(v.detalle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.texto2, height: 1.35)),
      ],
      if (s.esTecnico && s.hayDatos && !error) ...[
        const SizedBox(height: Esp.s),
        StatusDot(color: ctrl.color, text: ctrl.texto, icon: ctrl.icono, bold: false, size: 14),
      ],
      if (v.queHacer != null) ...[
        const SizedBox(height: Esp.m),
        AvisoLinea(
          color: error || v.punto == Palette.error ? Palette.error : Palette.sinDatos,
          icon: error ? Icons.touch_app_outlined : Icons.info_outline,
          text: v.queHacer!,
        ),
      ],
      if (!s.esTecnico && s.hayFallasCriticas) ...[
        const SizedBox(height: Esp.s),
        AvisoLinea(
          color: Palette.sinDatos,
          icon: Icons.build_circle_outlined,
          text: 'El equipo reporta una falla; el operador fue notificado.',
        ),
      ],
      // El test aparece justo debajo de la pecera.
      Padding(
        padding: const EdgeInsets.only(top: Esp.l),
        child: DiagnosticoPanel(key: _kDiagnostico),
      ),
    ]);
  }
}

/// Cloro activo + lugar y antigüedad, en una sola tarjeta.
class _Resumen extends StatelessWidget {
  const _Resumen();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final hocl = s.sensorOk ? s.hoclActual : null;
    return SectionCard(
      child: IntrinsicHeight(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text('Cloro activo',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.texto2)),
                ),
                const SizedBox(width: 2),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _explicarHocl(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.info_outline, size: 16, color: c.texto2),
                  ),
                ),
              ]),
              Text(hocl == null ? sinValor : 'Trabaja al ${hocl.round()} %',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.texto)),
            ]),
          ),
          VerticalDivider(width: Esp.xl, color: c.linea),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Lugar',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.texto2)),
              const SizedBox(height: 4),
              Text(s.ubicacion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.texto)),
              Text(haceTiempo(s.recibido, s.ahora),
                  style: TextStyle(fontSize: 12, color: c.texto2)),
            ]),
          ),
        ]),
      ),
    );
  }

  void _explicarHocl(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cloro activo'),
          content: const Text(
              'A menor pH, mayor parte del cloro está como ácido hipocloroso, '
              'la forma que desinfecta.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ],
        ),
      );
}

/// Técnico: umbral, distancia, ácido y bomba.
class _PanelControlador extends StatelessWidget {
  const _PanelControlador();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.ultimo;
    final umbral = t?.umbral;
    final dist = (t != null && umbral != null) ? t.ph - umbral : null;
    final acido = t?.acidoRestanteMl;

    return SectionCard(
      title: 'Controlador',
      trailing: BombaIndicador(encendida: s.rele),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _Dato('Umbral activo', fmtPh(umbral))),
          Expanded(
              child: _Dato('pH − umbral',
                  dist == null ? sinValor : (dist >= 0 ? '+' : '') + fmtPh(dist))),
          Expanded(child: _Dato('Ácido', fmtNum(acido, unidad: 'mL'))),
        ]),
        if (acido != null && acido < 20) ...[
          const SizedBox(height: Esp.m),
          const AvisoLinea(
            color: Palette.precaucion,
            icon: Icons.science_outlined,
            text: 'Queda poco ácido (< 20 mL). Rellena el depósito.',
          ),
        ],
        if (s.temperatura.supuesta) ...[
          const SizedBox(height: Esp.s),
          AvisoLinea(
            color: Palette.precaucion,
            icon: Icons.thermostat,
            text: 'Temperatura supuesta: ${s.temperatura.tempC.toStringAsFixed(1)} °C',
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
    final c = context.ag;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: c.texto2)),
      const SizedBox(height: 4),
      Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.texto)),
    ]);
  }
}

/// Técnico: objetivo (pH o eficacia) y Dosificar.
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
    _objPh ??= roundToStep(s.ultimo?.umbral ?? s.pHRecomendado, 0.05)
        .clamp(phMinUmbral, phMaxUmbral)
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final temp = s.temperatura.tempC;
    final phActual = s.ultimo?.ph;
    final modo = _modo!;
    final ef = targetForEfficacy(pct: _metaPct!, tempC: temp, phActual: phActual);
    final umbral = modo == ModoUmbral.ph ? _objPh! : ef.ph;
    final yaSeCumple = modo == ModoUmbral.eficacia
        ? ef.yaSeCumple
        : (phActual != null && phActual <= umbral);
    final recomendado = s.pHRecomendado;
    final enviando = _enviando || s.enviando(Cmd.dosificar);
    final puede = !s.dosificando &&
        !s.rele &&
        !s.sinConexion &&
        s.sensorOk &&
        !s.datosViejos &&
        !s.hayErrorEquipo &&
        !yaSeCumple &&
        !enviando;

    return SectionCard(
      title: 'Objetivo',
      trailing: SegmentedButton<ModoUmbral>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: ModoUmbral.ph, label: Text('pH')),
          ButtonSegment(value: ModoUmbral.eficacia, label: Text('Eficacia')),
        ],
        selected: {modo},
        onSelectionChanged: (v) => setState(() => _modo = v.first),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (modo == ModoUmbral.ph) ...[
          Text('pH ${_objPh!.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.texto)),
          Slider(
            min: phMinUmbral,
            max: phMaxUmbral,
            divisions: ((phMaxUmbral - phMinUmbral) / 0.05).round(),
            value: _objPh!,
            label: _objPh!.toStringAsFixed(2),
            onChanged: (v) => setState(() => _objPh = roundToStep(v, 0.05)),
          ),
        ] else ...[
          Text('${_metaPct!.round()} % HOCl → pH ${ef.phSinAjuste.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.texto)),
          Text('a ${temp.toStringAsFixed(0)} °C',
              style: TextStyle(fontSize: 13, color: c.texto2)),
          Slider(
            min: 50,
            max: 99,
            divisions: 49,
            value: _metaPct!,
            label: '${_metaPct!.round()} %',
            onChanged: (v) => setState(() => _metaPct = v.roundToDouble()),
          ),
          if (ef.ajustadoAlMinimo)
            const AvisoLinea(
              color: Palette.precaucion,
              icon: Icons.vertical_align_bottom,
              text: 'Se ajustó al mínimo permitido: pH 4.50',
            ),
        ],
        ActionChip(
          avatar: const Icon(Icons.auto_awesome, size: 16),
          label: Text('Recomendado: pH ${recomendado.toStringAsFixed(2)} '
              'a ${temp.toStringAsFixed(0)} °C'),
          onPressed: () => setState(() {
            _modo = ModoUmbral.ph;
            _objPh = roundToStep(recomendado, 0.05)
                .clamp(phMinUmbral, phMaxUmbral)
                .toDouble();
          }),
        ),
        if (yaSeCumple) ...[
          const SizedBox(height: Esp.m),
          const AvisoLinea(
            color: Palette.normal,
            icon: Icons.check_circle_outline,
            text: 'Ya se cumple: no hace falta dosificar (solo se puede bajar el pH).',
          ),
        ],
        if (umbral < nomMin) ...[
          const SizedBox(height: Esp.m),
          const AvisoLinea(
            color: Palette.precaucion,
            icon: Icons.warning_amber_rounded,
            text: 'Fuera del rango de agua potable (6.5–8.5); válido solo como prueba del banco.',
          ),
        ],
        const SizedBox(height: Esp.l),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: puede ? () => _confirmar(umbral) : null,
            icon: enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Palette.blanco))
                : const Icon(Icons.water_drop),
            label: Text(enviando ? 'Enviando…' : 'Dosificar hasta pH ${umbral.toStringAsFixed(2)}'),
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
        content: Text('pH actual ${fmtPh(s.ultimo?.ph)}  →  umbral ${umbral.toStringAsFixed(2)}\n\n'
            'La bomba agregará ácido en pulsos hasta llegar al umbral. '
            'El equipo valida la orden y puede rechazarla.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dosificar')),
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

/// pH promedio de 24 h con mini barras de 3 h (como en el diseño original).
class _Promedio24h extends StatelessWidget {
  const _Promedio24h();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final desde = s.ahora.subtract(const Duration(hours: 24));
    final ls = s.lecturasDesde(desde);
    final prom = ls.isEmpty ? null : ls.map((l) => l.ph).reduce((a, b) => a + b) / ls.length;

    const n = 8;
    final buckets = List<List<double>>.generate(n, (_) => []);
    for (final l in ls) {
      final i = (l.t.difference(desde).inMinutes / (24 * 60 / n)).floor();
      buckets[i.clamp(0, n - 1)].add(l.ph);
    }
    final medias = buckets
        .map((b) => b.isEmpty ? null : b.reduce((a, x) => a + x) / b.length)
        .toList();

    return SectionCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Promedio 24 h',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.texto2)),
            const SizedBox(height: 4),
            Text(fmtPh(prom),
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.texto)),
          ]),
        ),
        SizedBox(
          height: 52,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: AnimatedContainer(
                  duration: animDur(context),
                  width: 14,
                  height: math.max(
                      8,
                      52 *
                          (medias[i] == null
                              ? 0.15
                              : ((medias[i]! - 4) / 5).clamp(0.15, 1.0).toDouble())),
                  decoration: BoxDecoration(
                    color: i == n - 1 && medias[i] != null ? Palette.dosificando : c.linea,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Botón rectangular de bordes redondeados al final de Inicio.
class _BotonTest extends StatelessWidget {
  const _BotonTest();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final corriendo = s.diagnostico.corriendo;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          backgroundColor: c.superficie,
          side: BorderSide(color: c.linea, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Esp.radio)),
        ),
        onPressed: corriendo ? null : () => iniciarTest(context),
        icon: const Icon(Icons.fact_check_outlined),
        label: Text(corriendo ? 'Test en curso…' : 'Test de hardware y conectividad'),
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
    final c = context.ag;
    final ctrl = textoControlador(s.ultimo);
    return Container(
      padding: const EdgeInsets.fromLTRB(Esp.l, Esp.m, Esp.m, Esp.m),
      decoration: BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(Esp.radio),
        border: Border.all(color: ctrl.color, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20)],
      ),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            StatusDot(color: ctrl.color, text: ctrl.texto, icon: ctrl.icono, size: 15),
            const SizedBox(height: 6),
            BombaIndicador(encendida: s.rele),
          ]),
        ),
        const SizedBox(width: Esp.m),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.error,
            foregroundColor: Palette.blanco,
            minimumSize: const Size(140, 56),
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
