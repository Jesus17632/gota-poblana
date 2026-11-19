import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/chem.dart';
import '../core/palette.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'format.dart';
import 'widgets/common.dart';
import 'widgets/ph_chart.dart';

enum Periodo { sesion, h1, h24, d7 }

extension on Periodo {
  String get etiqueta => switch (this) {
        Periodo.sesion => 'Sesión',
        Periodo.h1 => '1 h',
        Periodo.h24 => '24 h',
        Periodo.d7 => '7 días',
      };
}

class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  Periodo _periodo = Periodo.h24;
  bool _hocl = false;

  ({DateTime desde, DateTime hasta}) _rango(AppState s) {
    final ahora = s.ahora;
    switch (_periodo) {
      case Periodo.sesion:
        final ini = s.inicioSesion;
        if (ini == null) {
          return (desde: ahora.subtract(const Duration(minutes: 5)), hasta: ahora);
        }
        final fin = s.dosificando ? ahora : (s.finSesion ?? ahora);
        return (
          desde: ini.subtract(const Duration(seconds: 10)),
          hasta: fin.add(const Duration(seconds: 10)),
        );
      case Periodo.h1:
        return (desde: ahora.subtract(const Duration(hours: 1)), hasta: ahora);
      case Periodo.h24:
        return (desde: ahora.subtract(const Duration(hours: 24)), hasta: ahora);
      case Periodo.d7:
        return (desde: ahora.subtract(const Duration(days: 7)), hasta: ahora);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tecnico = s.esTecnico;
    final periodos = tecnico
        ? Periodo.values
        : const [Periodo.h24, Periodo.d7];
    if (!periodos.contains(_periodo)) _periodo = Periodo.h24;

    final r = _rango(s);
    final ls = s.lecturasDesde(r.desde, r.hasta);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<Periodo>(
          showSelectedIcon: false,
          segments: [
            for (final p in periodos)
              ButtonSegment(value: p, label: Text(p.etiqueta)),
          ],
          selected: {_periodo},
          onSelectionChanged: (v) => setState(() => _periodo = v.first),
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Evolución del pH',
        trailing: tecnico
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('% HOCl',
                    style: TextStyle(
                        fontSize: 13, color: Palette.textoSecundario)),
                Switch(
                    value: _hocl, onChanged: (v) => setState(() => _hocl = v)),
              ])
            : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PhChart(
            lecturas: ls,
            desde: r.desde,
            hasta: r.hasta,
            umbral: tecnico ? s.ultimo?.umbral : null,
            mostrarHocl: tecnico && _hocl,
            mostrarEventos: tecnico,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 4, children: [
            _Leyenda(
                color: Palette.normal.withValues(alpha: 0.25),
                texto: 'Rango de la norma 6.5–8.5'),
            if (tecnico) ...[
              const _Leyenda(color: Palette.dosificando, texto: 'Umbral / inicio'),
              const _Leyenda(color: Palette.mezclando, texto: 'Pulso'),
              if (_hocl)
                const _Leyenda(color: Color(0xFF7A8794), texto: '% HOCl'),
            ],
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      _Tarjetas(lecturas: ls),
      if (tecnico) ...[
        const SizedBox(height: 16),
        const _Sesiones(),
        const SizedBox(height: 16),
        const _Registro(),
      ],
    ]);
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.texto});
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Palette.pista),
        ),
      ),
      const SizedBox(width: 6),
      Text(texto,
          style: const TextStyle(fontSize: 12, color: Palette.textoSecundario)),
    ]);
  }
}

class _Tarjetas extends StatelessWidget {
  const _Tarjetas({required this.lecturas});
  final List<Lectura> lecturas;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ls = lecturas;
    final prom = ls.isEmpty
        ? null
        : ls.map((l) => l.ph).reduce((a, b) => a + b) / ls.length;
    final enNorma = ls.isEmpty
        ? null
        : 100 *
            ls.where((l) => nomStatus(l.ph) == NomStatus.enRango).length /
            ls.length;

    final tiles = <Widget>[
      MetricTile(
          label: 'pH promedio', value: fmtPh(prom), icon: Icons.show_chart),
      MetricTile(
        label: 'Tiempo dentro de la norma',
        value: fmtNum(enNorma, dec: 0, unidad: '%'),
        icon: Icons.verified_outlined,
      ),
      MetricTile(
        label: 'Última alerta',
        value: s.ultimaAlerta == null
            ? 'Ninguna'
            : haceTiempo(s.ultimaAlerta, s.ahora),
        icon: Icons.notifications_none,
      ),
    ];

    if (s.esTecnico) {
      final t = s.ultimo;
      final temp = s.temperatura;
      final acido = t?.acidoRestanteMl;
      final ini = s.inicioSesion;
      final durSesion = ini == null
          ? null
          : (s.dosificando ? s.ahora : (s.finSesion ?? s.ahora))
              .difference(ini)
              .inSeconds;
      final sensor = t?.sensor;
      tiles.addAll([
        MetricTile(
            label: '% HOCl',
            value: fmtNum(s.hoclActual, dec: 0, unidad: '%'),
            icon: Icons.bubble_chart_outlined),
        MetricTile(
            label: 'ŝ (pH/mL)',
            value: fmtNum(t?.sHat, dec: 3),
            icon: Icons.trending_down),
        MetricTile(
            label: 'mL dosificados',
            value: fmtNum(t?.mlDosificados, unidad: 'mL'),
            icon: Icons.water_drop_outlined),
        MetricTile(
          label: 'Ácido restante',
          value: fmtNum(acido, unidad: 'mL'),
          icon: Icons.science_outlined,
          nota: (acido != null && acido < 20) ? 'Ácido bajo' : null,
          notaColor: Palette.precaucion,
        ),
        MetricTile(
            label: 'Pulsos',
            value: t?.pulsos?.toString() ?? sinValor,
            icon: Icons.more_horiz),
        MetricTile(
            label: 'Error final',
            value: fmtPh(t?.errorFinal),
            icon: Icons.straighten),
        MetricTile(
            label: 'Duración de la sesión',
            value: duracion(durSesion),
            icon: Icons.timer_outlined),
        MetricTile(
          label: 'Temperatura',
          value: fmtNum(temp.tempC, unidad: '°C'),
          icon: Icons.thermostat,
          nota: temp.supuesta ? 'supuesta' : null,
          notaColor: Palette.precaucion,
        ),
        MetricTile(
            label: 'mV crudo', value: fmtNum(t?.mv, dec: 0), icon: Icons.bolt),
        MetricTile(
          label: 'Estado del sensor',
          value: sensor == null
              ? sinValor
              : sensor == SensorEstado.ok
                  ? 'OK'
                  : 'Revisar sensor',
          icon: sensor == null || sensor == SensorEstado.ok
              ? Icons.sensors
              : Icons.sensors_off,
          nota: sensor == null ? null : sensorWire(sensor),
          notaColor: sensor == SensorEstado.ok
              ? Palette.normal
              : Palette.sinDatos,
        ),
      ]);
    }

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }
}

class _Sesiones extends StatelessWidget {
  const _Sesiones();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ses = s.sesiones;
    return SectionCard(
      title: 'Sesiones',
      trailing: TextButton.icon(
        onPressed: ses.isEmpty ? null : () => _exportar(context, s),
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Exportar CSV'),
      ),
      child: ses.isEmpty
          ? const Text('Aún no hay sesiones de dosificación.',
              style: TextStyle(color: Palette.textoSecundario))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Palette.textoSecundario),
                columns: const [
                  DataColumn(label: Text('Hora')),
                  DataColumn(label: Text('Umbral'), numeric: true),
                  DataColumn(label: Text('pH final'), numeric: true),
                  DataColumn(label: Text('Error'), numeric: true),
                  DataColumn(label: Text('Pulsos'), numeric: true),
                  DataColumn(label: Text('mL'), numeric: true),
                  DataColumn(label: Text('Duración'), numeric: true),
                ],
                rows: [
                  for (final r in ses.take(50))
                    DataRow(cells: [
                      DataCell(Text(r.registrado == null
                          ? sinValor
                          : '${ddmm(r.registrado!)} ${hhmm(r.registrado!)}')),
                      DataCell(Text(fmtPh(r.umbral))),
                      DataCell(Text(fmtPh(r.phFinal))),
                      DataCell(Text(fmtPh(r.error))),
                      DataCell(Text(r.pulsos?.toString() ?? sinValor)),
                      DataCell(Text(fmtNum(r.ml))),
                      DataCell(Text(duracion(r.segundos))),
                    ]),
                ],
              ),
            ),
    );
  }

  Future<void> _exportar(BuildContext context, AppState s) async {
    final csv = s.sesionesCsv();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV copiado al portapapeles'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

class _Registro extends StatelessWidget {
  const _Registro();

  static Color _color(String tipo) => switch (tipo) {
        'INICIO' || 'RELE_ON' => Palette.dosificando,
        'FIN' || 'ACK' || 'FALLA RESUELTA' => Palette.normal,
        'RECHAZO' || 'ERROR' || 'SIN RESPUESTA' || 'ERROR ENVÍO' ||
        'FUERA_NORMA' || 'FALLA' =>
          Palette.error,
        'BUZZER' || 'LED' => Palette.mezclando,
        _ => Palette.sinDatos,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final items = s.registro.take(80).toList();
    String hms(DateTime t) =>
        '${hhmm(t)}:${t.second.toString().padLeft(2, '0')}';
    return SectionCard(
      title: 'Registro de eventos',
      child: items.isEmpty
          ? const Text('Sin eventos todavía.',
              style: TextStyle(color: Palette.textoSecundario))
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Palette.pista),
                itemBuilder: (_, i) {
                  final e = items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(hms(e.t),
                                style: const TextStyle(
                                    fontFeatures: [FontFeature.tabularFigures()],
                                    color: Palette.textoSecundario)),
                          ),
                          SizedBox(
                            width: 130,
                            child: StatusDot(
                                color: _color(e.tipo), text: e.tipo, bold: true),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.detalle)),
                        ]),
                  );
                },
              ),
            ),
    );
  }
}
