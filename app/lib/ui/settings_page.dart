import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import '../data/data_source.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'app_scope.dart';
import 'format.dart';
import 'widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    void set(VoidCallback f) {
      f();
      s.guardarSettings();
    }

    return Column(children: [
      SectionCard(
        title: 'Nodo',
        child: Column(children: [
          _Fila(
            icon: Icons.place_outlined,
            titulo: 'Ubicación',
            valor: s.ubicacion,
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Ubicación',
                  inicial: cfg.ubicacion,
                  ayuda: 'Vacío = usar la que envía el equipo');
              if (v != null) set(() => cfg.ubicacion = v.trim());
            },
          ),
          _Fila(icon: Icons.memory, titulo: 'Nodo', valor: s.nodo),
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Preferencias',
        child: Column(children: [
          _Interruptor(
            icon: Icons.notifications_outlined,
            titulo: 'Notificaciones de alerta',
            valor: cfg.notifAlertas,
            onChanged: (v) => set(() => cfg.notifAlertas = v),
          ),
          _Interruptor(
            icon: Icons.motion_photos_off_outlined,
            titulo: 'Movimiento reducido',
            subtitulo: MediaQuery.of(context).disableAnimations
                ? 'El sistema ya lo tiene activado'
                : null,
            valor: cfg.movimientoReducido,
            onChanged: (v) => set(() => cfg.movimientoReducido = v),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (!s.esTecnico)
        SectionCard(
          child: _Fila(
            icon: Icons.engineering_outlined,
            titulo: 'Modo técnico',
            valor: 'Requiere PIN',
            onTap: () => _pedirPin(context, s),
          ),
        )
      else
        const _Tecnico(),
      const SizedBox(height: 24),
    ]);
  }

  Future<void> _pedirPin(BuildContext context, AppState s) async {
    final pin = await _pedirTexto(context,
        titulo: 'PIN de técnico', oculto: true, numerico: true);
    if (pin == null || !context.mounted) return;
    final ok = s.entrarTecnico(pin);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Modo técnico activado' : 'PIN incorrecto'),
    ));
  }
}

class _Tecnico extends StatelessWidget {
  const _Tecnico();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    void set(VoidCallback f) {
      f();
      s.guardarSettings();
    }

    final con = switch (s.conexion) {
      ConexionEstado.conectado => (Palette.normal, 'Conectado'),
      ConexionEstado.conectando => (Palette.mezclando, 'Conectando…'),
      ConexionEstado.desconectado => (Palette.sinDatos, 'Desconectado'),
      ConexionEstado.error => (Palette.error, 'Error de conexión'),
    };
    final calib = s.ultimo?.calib;

    return Column(children: [
      SectionCard(
        title: 'Fuente de datos',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<FuenteDatos>(
              segments: const [
                ButtonSegment(
                    value: FuenteDatos.simulador, label: Text('Simulador')),
                ButtonSegment(value: FuenteDatos.mqtt, label: Text('MQTT')),
              ],
              selected: {cfg.fuente},
              onSelectionChanged: (v) {
                cfg.fuente = v.first;
                s.reconectar();
              },
            ),
          ),
          const SizedBox(height: 12),
          if (cfg.fuente == FuenteDatos.mqtt) ...[
            _Fila(
              icon: Icons.dns_outlined,
              titulo: 'Host',
              valor: cfg.mqttHost,
              onTap: () async {
                final v = await _pedirTexto(context,
                    titulo: 'Host del broker',
                    inicial: cfg.mqttHost,
                    ayuda: 'IP/host, o URL completa ws://host/ruta');
                if (v != null && v.trim().isNotEmpty) {
                  cfg.mqttHost = v.trim();
                  s.reconectar();
                }
              },
            ),
            _Fila(
              icon: Icons.numbers,
              titulo: 'Puerto (WebSocket)',
              valor: '${cfg.mqttPort}',
              onTap: () async {
                final v = await _pedirTexto(context,
                    titulo: 'Puerto',
                    inicial: '${cfg.mqttPort}',
                    numerico: true);
                final p = int.tryParse(v ?? '');
                if (p != null && p > 0 && p < 65536) {
                  cfg.mqttPort = p;
                  s.reconectar();
                }
              },
            ),
          ],
          _Fila(
            icon: Icons.memory,
            titulo: 'Nodo',
            valor: cfg.nodo,
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Nodo', inicial: cfg.nodo, ayuda: 'Ej. nodo1');
              if (v != null && v.trim().isNotEmpty) {
                cfg.nodo = v.trim();
                s.reconectar();
              }
            },
          ),
          const SizedBox(height: 8),
          StatusDot(color: con.$1, text: con.$2, bold: false),
          const SizedBox(height: 4),
          Text(
            '${s.fuenteDescripcion} · visto por última vez '
            '${s.recibido == null ? sinValor : '${hhmm(s.recibido!)} (${haceTiempo(s.recibido, s.ahora)})'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (s.errorConexion != null) ...[
            const SizedBox(height: 8),
            AvisoLinea(
                color: Palette.error,
                icon: Icons.error_outline,
                text: s.errorConexion!),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Temperatura y objetivo',
        child: Column(children: [
          _Interruptor(
            icon: Icons.sensors,
            titulo: 'Usar sensor de temperatura',
            subtitulo: s.ultimo?.tempC == null
                ? 'El equipo no está enviando temperatura'
                : null,
            valor: cfg.usarSensorTemp,
            onChanged: (v) => set(() => cfg.usarSensorTemp = v),
          ),
          _Fila(
            icon: Icons.thermostat,
            titulo: 'Temperatura del agua',
            valor: '${cfg.tempAguaC.toStringAsFixed(1)} °C',
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Temperatura del agua (°C)',
                  inicial: cfg.tempAguaC.toStringAsFixed(1),
                  numerico: true);
              final t = double.tryParse((v ?? '').replaceAll(',', '.'));
              if (t != null && t > 0 && t < 60) {
                set(() => cfg.tempAguaC = t);
              }
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.bubble_chart_outlined,
                color: Palette.textoSecundario),
            const SizedBox(width: 12),
            Expanded(
                child:
                    Text('Meta de HOCl: ${cfg.metaHoclPct.round()} %')),
          ]),
          Slider(
            min: 50,
            max: 99,
            divisions: 49,
            value: cfg.metaHoclPct.clamp(50, 99).toDouble(),
            onChanged: (v) => set(() => cfg.metaHoclPct = v.roundToDouble()),
          ),
          Row(children: [
            const Expanded(child: Text('Modo de umbral por defecto')),
            SegmentedButton<ModoUmbral>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ModoUmbral.ph, label: Text('pH')),
                ButtonSegment(
                    value: ModoUmbral.eficacia, label: Text('Eficacia')),
              ],
              selected: {cfg.modoUmbral},
              onSelectionChanged: (v) => set(() => cfg.modoUmbral = v.first),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Mantenimiento',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Calibración: offset ${fmtNum(calib?.offset, dec: 2)} · '
            'fecha ${calib?.fecha ?? sinValor}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Calibrar con solución conocida'),
              onPressed: () async {
                final v = await _pedirTexto(context,
                    titulo: 'pH de la solución de referencia',
                    ayuda: 'Ej. 4.00 o 7.00',
                    numerico: true);
                final ph = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (ph != null && ph > 0 && ph < 14) {
                  try {
                    await s.calibrar(ph);
                  } catch (_) {}
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.science_outlined),
              label: const Text('Rellené el ácido (100 mL)'),
              onPressed: () async {
                try {
                  await s.rellenarAcido();
                } catch (_) {}
              },
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Notificaciones del técnico',
        child: Column(children: [
          _Interruptor(
              icon: Icons.play_circle_outline,
              titulo: 'Inicio de dosificación',
              valor: cfg.notifInicio,
              onChanged: (v) => set(() => cfg.notifInicio = v)),
          _Interruptor(
              icon: Icons.check_circle_outline,
              titulo: 'Fin de dosificación',
              valor: cfg.notifFin,
              onChanged: (v) => set(() => cfg.notifFin = v)),
          _Interruptor(
              icon: Icons.error_outline,
              titulo: 'Error',
              valor: cfg.notifError,
              onChanged: (v) => set(() => cfg.notifError = v)),
          _Interruptor(
              icon: Icons.warning_amber_rounded,
              titulo: 'Fuera de norma',
              valor: cfg.notifFueraNorma,
              onChanged: (v) => set(() => cfg.notifFueraNorma = v)),
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(
        child: Column(children: [
          _Fila(
            icon: Icons.pin_outlined,
            titulo: 'Cambiar PIN',
            valor: '••••',
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Nuevo PIN', oculto: true, numerico: true);
              if (v != null && v.trim().length >= 4) {
                set(() => cfg.pin = v.trim());
              }
            },
          ),
          _Fila(
            icon: Icons.logout,
            titulo: 'Salir del modo técnico',
            onTap: s.salirTecnico,
          ),
        ]),
      ),
    ]);
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.icon, required this.titulo, this.valor, this.onTap});
  final IconData icon;
  final String titulo;
  final String? valor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Palette.textoSecundario),
      title: Text(titulo),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (valor != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(valor!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Palette.textoSecundario)),
          ),
        if (onTap != null)
          const Icon(Icons.chevron_right, color: Palette.textoSecundario),
      ]),
      onTap: onTap,
    );
  }
}

class _Interruptor extends StatelessWidget {
  const _Interruptor({
    required this.icon,
    required this.titulo,
    required this.valor,
    required this.onChanged,
    this.subtitulo,
  });
  final IconData icon;
  final String titulo;
  final String? subtitulo;
  final bool valor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: Palette.textoSecundario),
      title: Text(titulo),
      subtitle: subtitulo == null ? null : Text(subtitulo!),
      value: valor,
      onChanged: onChanged,
    );
  }
}

Future<String?> _pedirTexto(
  BuildContext context, {
  required String titulo,
  String inicial = '',
  String? ayuda,
  bool oculto = false,
  bool numerico = false,
}) {
  final ctrl = TextEditingController(text: inicial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        obscureText: oculto,
        keyboardType: numerico
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(helperText: ayuda),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Aceptar')),
      ],
    ),
  );
}
