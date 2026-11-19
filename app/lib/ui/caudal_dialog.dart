// Asistente para calibrar el caudal de la bomba en dos puntos:
// pulso de 500 ms y de 1500 ms, midiendo los mL de cada uno en una probeta.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/caudal.dart';
import '../core/device_constants.dart';
import '../core/palette.dart';
import '../data/models.dart';
import 'app_scope.dart';
import 'tokens.dart';
import 'widgets/common.dart';

Future<void> mostrarCalibrarCaudal(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _CalibrarCaudal());

class _CalibrarCaudal extends StatefulWidget {
  const _CalibrarCaudal();

  @override
  State<_CalibrarCaudal> createState() => _CalibrarCaudalState();
}

class _CalibrarCaudalState extends State<_CalibrarCaudal> {
  static const _t1 = DeviceConst.calibPulsoCortoMs;
  static const _t2 = DeviceConst.calibPulsoLargoMs;

  int _paso = 0; // 0 intro · 1 corto · 2 largo · 3 resultado
  final _v1 = TextEditingController();
  final _v2 = TextEditingController();
  bool _bombeando = false;
  bool _hecho1 = false;
  bool _hecho2 = false;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _v1.dispose();
    _v2.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim());

  Future<void> _pulso(int ms, VoidCallback alTerminar) async {
    final s = AppScope.of(context);
    setState(() {
      _bombeando = true;
      _error = null;
    });
    final fin = s.eventosDispositivo
        .firstWhere((e) => e.tipo == TipoEvento.releOff || e.tipo == TipoEvento.rechazo)
        .timeout(Duration(milliseconds: ms + 4000));
    try {
      await s.probarBomba(ms);
      final e = await fin;
      if (e.tipo == TipoEvento.rechazo) {
        _error = 'Rechazado: ${e.detalle ?? 'sin motivo'}';
      } else {
        alTerminar();
      }
    } on TimeoutException {
      _error = 'Sin respuesta del equipo';
    } catch (e) {
      _error = 'No se pudo enviar: $e';
      unawaited(fin.then((_) {}, onError: (_) {}));
    }
    if (mounted) setState(() => _bombeando = false);
  }

  CalibracionCaudal? get _resultado {
    final v1 = _num(_v1), v2 = _num(_v2);
    if (v1 == null || v2 == null) return null;
    try {
      return calibrarCaudal(t1Ms: _t1, v1Ml: v1, t2Ms: _t2, v2Ml: v2);
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardar(CalibracionCaudal r) async {
    final s = AppScope.of(context);
    setState(() => _guardando = true);
    try {
      await s.calibrarCaudal(r.mlPorSegundo, r.t0Ms);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    final r = _resultado;
    final puedeSeguir = switch (_paso) {
      0 => true,
      1 => _hecho1 && _num(_v1) != null,
      2 => _hecho2 && _num(_v2) != null,
      _ => false,
    };

    Widget medicion(int ms, bool hecho, TextEditingController ctrl, VoidCallback marcar,
            String aviso) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(aviso, style: TextStyle(color: c.texto2, height: 1.4)),
          const SizedBox(height: Esp.m),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _bombeando ? null : () => _pulso(ms, marcar),
              icon: _bombeando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Palette.blanco))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_bombeando
                  ? 'Bombeando…'
                  : (hecho ? 'Repetir pulso de $ms ms' : 'Encender bomba $ms ms')),
            ),
          ),
          if (hecho) ...[
            const SizedBox(height: Esp.m),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'mL medidos en la probeta',
                suffixText: 'mL',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ]);

    final contenido = switch (_paso) {
      0 => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se miden dos pulsos para conocer el caudal y el tiempo que tarda '
              'el motor en arrancar.',
              style: TextStyle(color: c.texto, height: 1.4)),
          const SizedBox(height: Esp.m),
          for (final t in const [
            'Pon la salida de la manguera en una probeta o jeringa graduada vacía.',
            'Si puedes, mete la entrada en un vaso con agua para no gastar ácido.',
            'Ten a mano papel para limpiar. Tarda menos de un minuto.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Esp.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle_outline, size: 18, color: c.texto2),
                const SizedBox(width: Esp.s),
                Expanded(child: Text(t, style: TextStyle(color: c.texto2))),
              ]),
            ),
        ]),
      1 => medicion(_t1, _hecho1, _v1, () => _hecho1 = true,
          'Medición 1 de 2: pulso corto de $_t1 ms. Después escribe cuántos mL salieron.'),
      2 => medicion(_t2, _hecho2, _v2, () => _hecho2 = true,
          'Medición 2 de 2: vacía la probeta. Pulso largo de $_t2 ms.'),
      _ => r == null
          ? const AvisoLinea(
              color: Palette.error,
              icon: Icons.error_outline,
              text: 'Las mediciones no tienen sentido: el pulso largo debe sacar más mL '
                  'que el corto. Repite las mediciones.',
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r.mlPorSegundo.toStringAsFixed(1)} mL/s',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: c.texto)),
              Text('Arranque del motor: ${r.t0Ms.round()} ms',
                  style: TextStyle(color: c.texto2)),
              const SizedBox(height: Esp.m),
              Text(
                'Con esto, "Probar bomba" (${DeviceConst.pulsoPruebaMs} ms) saca '
                '≈ ${r.volumen(DeviceConst.pulsoPruebaMs).toStringAsFixed(1)} mL.',
                style: TextStyle(color: c.texto2),
              ),
              if ((r.mlPorSegundo - DeviceConst.mlPorSegundoBomba).abs() >
                  DeviceConst.mlPorSegundoBomba * 0.5) ...[
                const SizedBox(height: Esp.m),
                const AvisoLinea(
                  color: Palette.precaucion,
                  icon: Icons.info_outline,
                  text: 'Muy distinto del valor de fábrica (33 mL/s). Revisa la medición '
                      'si no cambiaste de bomba.',
                ),
              ],
            ]),
    };

    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Calibrar caudal')),
        Text('${_paso + 1}/4', style: TextStyle(fontSize: 14, color: c.texto2)),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            contenido,
            if (_error != null) ...[
              const SizedBox(height: Esp.m),
              AvisoLinea(color: Palette.error, icon: Icons.error_outline, text: _error!),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _bombeando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (_paso > 0 && _paso < 3 || (_paso == 3 && r == null))
          TextButton(
            onPressed: _bombeando ? null : () => setState(() => _paso = _paso == 3 ? 1 : _paso - 1),
            child: Text(_paso == 3 ? 'Repetir' : 'Atrás'),
          ),
        if (_paso < 3)
          FilledButton(
            onPressed: puedeSeguir && !_bombeando ? () => setState(() => _paso++) : null,
            child: Text(_paso == 0 ? 'Empezar' : 'Siguiente'),
          )
        else if (r != null)
          FilledButton(
            onPressed: _guardando ? null : () => _guardar(r),
            child: Text(_guardando ? 'Enviando…' : 'Guardar en el equipo'),
          ),
      ],
    );
  }
}
