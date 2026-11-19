// Panel "Dispositivos" (rol técnico): estado de cada módulo y botones de
// prueba. Todo pasa por órdenes al ESP32; la app nunca toca el hardware.
import 'package:material_ui/material_ui.dart';

import '../core/device_constants.dart';
import '../core/palette.dart';
import '../data/data_source.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'app_scope.dart';
import 'widgets/bomba_indicador.dart';
import 'widgets/common.dart';

class DevicesPanel extends StatelessWidget {
  const DevicesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final hw = s.hw;
    final mods = hw?.modulos;
    bool? detectado(String m) => mods == null ? null : (mods[m] ?? false);
    final led = hw?.led;
    final sensor = hw?.sensor ?? s.ultimo?.sensor;

    return SectionCard(
      title: 'Dispositivos',
      trailing: s.simulado
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Palette.precaucion,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('MODO SIMULADO',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Palette.texto)),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 640 ? 3 : 2;
          const gap = 10.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          final tarjetas = [
            _Modulo(
              nombre: 'XC01 controlador',
              valor: s.xc01EnLinea ? 'En línea' : 'Fuera de línea',
              color: s.xc01EnLinea ? Palette.normal : Palette.sinDatos,
              icon: Icons.memory,
            ),
            _Modulo(
              nombre: 'XN13 relé (bomba)',
              valor: detectado('XN13') == false
                  ? 'No detectado'
                  : (s.rele ? 'ON' : 'OFF'),
              color: detectado('XN13') == false
                  ? Palette.error
                  : (s.rele ? Palette.dosificando : Palette.sinDatos),
              icon: s.rele ? Icons.power : Icons.power_off,
            ),
            _Modulo(
              nombre: 'XN44 buzzer',
              valor: detectado('XN44') == false
                  ? 'No detectado'
                  : (hw == null
                      ? '—'
                      : (hw.buzzerSonando ? 'Sonando' : 'Silencio')),
              color: detectado('XN44') == false
                  ? Palette.error
                  : ((hw?.buzzerSonando ?? false)
                      ? Palette.dosificando
                      : Palette.sinDatos),
              icon: Icons.volume_up_outlined,
            ),
            _Modulo(
              nombre: 'XN03 LED RGB',
              valor: detectado('XN03') == false
                  ? 'No detectado'
                  : (led == null ? '—' : led.join(', ')),
              color: detectado('XN03') == false
                  ? Palette.error
                  : Palette.sinDatos,
              icon: Icons.lightbulb_outline,
              muestra: led == null
                  ? null
                  : Color.fromARGB(255, led[0], led[1], led[2]),
            ),
            _Modulo(
              nombre: 'Sonda de pH',
              valor: switch (sensor) {
                null => '—',
                SensorEstado.ok => 'OK',
                SensorEstado.fueraRango => 'Fuera de rango',
                SensorEstado.sinRespuesta => 'Sin respuesta',
              },
              color: sensor == null || sensor == SensorEstado.ok
                  ? Palette.normal
                  : Palette.error,
              icon: Icons.sensors,
            ),
          ];
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final t in tarjetas) SizedBox(width: w, child: t),
          ]);
        }),
        const SizedBox(height: 16),
        BombaIndicador(encendida: s.rele),
        const SizedBox(height: 16),
        const Text('Pruebas',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Palette.textoSecundario)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _BotonOrden(
            cmd: Cmd.pulso(DeviceConst.pulsoPruebaMs),
            icon: Icons.water_drop_outlined,
            texto: 'Probar bomba ${DeviceConst.pulsoPruebaMs} ms',
            onPressed: () => _probarBomba(context, s),
          ),
          for (final t in const ['inicio', 'fin', 'error'])
            _BotonOrden(
              cmd: Cmd.testBuzzer(t),
              icon: Icons.volume_up_outlined,
              texto: 'Buzzer: $t',
              onPressed: () => _intentar(() => s.probarBuzzer(t)),
            ),
          _BotonOrden(
            cmd: null,
            icon: Icons.palette_outlined,
            texto: 'Probar LED',
            onPressed: () => _elegirColor(context, s),
          ),
        ]),
        if (s.simulado) ...[
          const SizedBox(height: 20),
          const Text('Desarrollo (solo simulador)',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Palette.textoSecundario)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.thermostat, color: Palette.textoSecundario),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Temperatura simulada del agua: '
                  '${(s.temperaturaSimulada ?? 22).toStringAsFixed(1)} °C'),
            ),
          ]),
          Slider(
            min: 5,
            max: 40,
            divisions: 70,
            value: (s.temperaturaSimulada ?? 22).clamp(5, 40).toDouble(),
            onChanged: (v) => s.temperaturaSimulada = v,
          ),
          if (!s.settings.usarSensorTemp)
            const AvisoLinea(
              color: Palette.precaucion,
              icon: Icons.info_outline,
              text: 'Activa "Usar sensor de temperatura" para que los '
                  'cálculos usen esta temperatura.',
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Palette.error),
            icon: const Icon(Icons.sensors_off),
            label: const Text('Simular falla de sensor'),
            onPressed: () => s.simularFallaSensor(),
          ),
          const SizedBox(height: 4),
          const Text('"Detener" restablece la sonda en el simulador.',
              style: TextStyle(fontSize: 12, color: Palette.textoSecundario)),
        ],
      ]),
    );
  }

  static Future<void> _intentar(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      // El aviso con el motivo ya lo muestra el shell.
    }
  }

  Future<void> _probarBomba(BuildContext context, AppState s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Probar la bomba?'),
        content: Text(
            'Se enviará "p ${DeviceConst.pulsoPruebaMs}": la bomba se '
            'encenderá ${DeviceConst.pulsoPruebaMs} ms y agregará '
            '~${(DeviceConst.mlPorSegundoBomba * DeviceConst.pulsoPruebaMs / 1000).toStringAsFixed(1)} mL de ácido.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Probar')),
        ],
      ),
    );
    if (ok == true) await _intentar(() => s.probarBomba());
  }

  Future<void> _elegirColor(BuildContext context, AppState s) async {
    const colores = <(String, int, int, int)>[
      ('Rojo', 255, 0, 0),
      ('Verde', 0, 255, 0),
      ('Azul', 0, 0, 255),
      ('Amarillo', 255, 200, 0),
      ('Blanco', 255, 255, 255),
      ('Apagado', 0, 0, 0),
    ];
    final elegido = await showDialog<(String, int, int, int)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Color de prueba del LED'),
        children: [
          for (final c in colores)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, c.$2, c.$3, c.$4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.pista),
                  ),
                ),
                const SizedBox(width: 12),
                Text(c.$1),
              ]),
            ),
        ],
      ),
    );
    if (elegido != null) {
      await _intentar(() => s.probarLed(elegido.$2, elegido.$3, elegido.$4));
    }
  }
}

class _Modulo extends StatelessWidget {
  const _Modulo({
    required this.nombre,
    required this.valor,
    required this.color,
    required this.icon,
    this.muestra,
  });
  final String nombre;
  final String valor;
  final Color color;
  final IconData icon;
  final Color? muestra;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.fondo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: Palette.textoSecundario),
          const SizedBox(width: 6),
          Expanded(
            child: Text(nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Palette.textoSecundario)),
          ),
          if (muestra != null)
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: muestra,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.pista),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        StatusDot(color: color, text: valor),
      ]),
    );
  }
}

/// Botón que muestra "Enviando…" mientras su orden no tenga respuesta.
class _BotonOrden extends StatelessWidget {
  const _BotonOrden({
    required this.cmd,
    required this.icon,
    required this.texto,
    required this.onPressed,
  });
  final String? cmd;
  final IconData icon;
  final String texto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final enviando = cmd != null && s.enviando(cmd!);
    final ocupado = s.dosificando || s.rele;
    final esBomba = cmd != null && cmd!.startsWith('${DeviceConst.cmdPulso} ');
    return OutlinedButton.icon(
      onPressed: enviando || (esBomba && ocupado) ? null : onPressed,
      icon: enviando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(enviando ? 'Enviando…' : texto),
    );
  }
}
