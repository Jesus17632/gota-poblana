import 'package:material_ui/material_ui.dart';

import '../core/device_constants.dart';
import '../core/palette.dart';
import '../data/data_source.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'app_scope.dart';
import 'devices_panel.dart';
import 'format.dart';
import 'shell.dart';
import 'tokens.dart';
import 'widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final d = Disposicion.of(context);
    final generales = <Widget>[
      const _Perfil(),
      const _Apariencia(),
      const _Avisos(),
      const _Ayuda(),
    ];
    final tecnico = <Widget>[
      const _Conexion(),
      const DevicesPanel(),
      const _Medicion(),
      const _Mantenimiento(),
      const _NotifTecnico(),
    ];

    Widget lista(List<Widget> ws) => Column(children: [
          for (var i = 0; i < ws.length; i++) ...[
            if (i > 0) const SizedBox(height: Esp.m),
            ws[i],
          ],
        ]);

    if (s.esTecnico && d.dosColumnas) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: lista(generales)),
        const SizedBox(width: Esp.l),
        Expanded(flex: 6, child: lista(tecnico)),
      ]);
    }
    return lista([...generales, if (s.esTecnico) ...tecnico]);
  }
}

// ---------------------------------------------------------------- Generales

class _Perfil extends StatelessWidget {
  const _Perfil();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    return SectionCard(
      title: 'Perfil',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<Rol>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: Rol.ciudadano,
                  icon: Icon(Icons.person_outline),
                  label: Text('Ciudadano')),
              ButtonSegment(
                  value: Rol.tecnico,
                  icon: Icon(Icons.engineering_outlined),
                  label: Text('Técnico')),
            ],
            selected: {s.rol},
            onSelectionChanged: (v) => s.cambiarRol(v.first),
          ),
        ),
        const SizedBox(height: Esp.s),
        Text(
          s.esTecnico
              ? 'Ves los controles de la bomba, los dispositivos y los diagnósticos.'
              : 'Solo lectura: ves el estado del agua, la escala y el historial.',
          style: TextStyle(fontSize: 13, color: c.texto2),
        ),
      ]),
    );
  }
}

class _Apariencia extends StatelessWidget {
  const _Apariencia();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    return SectionCard(
      title: 'Apariencia',
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ModoTema>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: ModoTema.sistema,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Sistema')),
              ButtonSegment(
                  value: ModoTema.claro,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Claro')),
              ButtonSegment(
                  value: ModoTema.oscuro,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Oscuro')),
            ],
            selected: {cfg.tema},
            onSelectionChanged: (v) {
              cfg.tema = v.first;
              s.guardarSettings();
            },
          ),
        ),
        const SizedBox(height: Esp.s),
        _Interruptor(
          icon: Icons.motion_photos_off_outlined,
          titulo: 'Movimiento reducido',
          subtitulo: MediaQuery.of(context).disableAnimations
              ? 'Ya activado en el sistema'
              : 'Detiene la animación del agua y las transiciones',
          valor: cfg.movimientoReducido,
          onChanged: (v) {
            cfg.movimientoReducido = v;
            s.guardarSettings();
          },
        ),
      ]),
    );
  }
}

class _Avisos extends StatelessWidget {
  const _Avisos();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    void set(VoidCallback f) {
      f();
      s.guardarSettings();
    }

    return SectionCard(
      title: 'Avisos',
      child: Column(children: [
        _Interruptor(
          icon: Icons.notifications_outlined,
          titulo: 'Alertas fuera de norma',
          valor: cfg.notifAlertas,
          onChanged: (v) => set(() => cfg.notifAlertas = v),
        ),
        _Interruptor(
          icon: Icons.volume_up_outlined,
          titulo: 'Sonidos',
          valor: cfg.sonidos,
          onChanged: (v) => set(() => cfg.sonidos = v),
        ),
        _Interruptor(
          icon: Icons.vibration,
          titulo: 'Vibración',
          valor: cfg.vibracion,
          onChanged: (v) => set(() => cfg.vibracion = v),
        ),
      ]),
    );
  }
}

class _Ayuda extends StatelessWidget {
  const _Ayuda();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    return SectionCard(
      title: 'Nodo y ayuda',
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
            if (v != null) {
              cfg.ubicacion = v.trim();
              s.guardarSettings();
            }
          },
        ),
        _Fila(icon: Icons.memory, titulo: 'Nodo', valor: s.nodo),
        _Fila(
          icon: Icons.play_circle_outline,
          titulo: 'Ver la introducción',
          onTap: s.verOnboardingDeNuevo,
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Técnico

class _Conexion extends StatelessWidget {
  const _Conexion();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    final c = context.ag;
    final con = switch (s.conexion) {
      ConexionEstado.conectado => (Palette.normal, 'Conectado'),
      ConexionEstado.conectando => (Palette.mezclando, 'Conectando…'),
      ConexionEstado.desconectado => (Palette.sinDatos, 'Desconectado'),
      ConexionEstado.error => (Palette.error, 'Sin conexión'),
    };

    return SectionCard(
      title: 'Conexión',
      trailing: StatusDot(color: con.$1, text: con.$2, bold: false, size: 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<FuenteDatos>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: FuenteDatos.mqtt, label: Text('ESP32 (MQTT)')),
              ButtonSegment(value: FuenteDatos.simulador, label: Text('Simulador')),
            ],
            selected: {cfg.fuente},
            onSelectionChanged: (v) {
              cfg.fuente = v.first;
              s.reconectar();
            },
          ),
        ),
        const SizedBox(height: Esp.s),
        if (cfg.fuente == FuenteDatos.mqtt) ...[
          if (!DeviceConst.mqttHabilitado)
            const Padding(
              padding: EdgeInsets.only(bottom: Esp.s),
              child: AvisoLinea(
                color: Palette.precaucion,
                icon: Icons.info_outline,
                text: 'MQTT está desactivado en device_constants.dart.',
              ),
            ),
          _Fila(
            icon: Icons.dns_outlined,
            titulo: 'Host',
            valor: cfg.mqttHost,
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Host del ESP32 / broker',
                  inicial: cfg.mqttHost,
                  ayuda: 'IP o host, o URL completa ws://host/ruta');
              if (v != null && v.trim().isNotEmpty) {
                cfg.mqttHost = v.trim();
                s.reconectar();
              }
            },
          ),
          _Fila(
            icon: Icons.numbers,
            titulo: 'Puerto WebSocket',
            valor: '${cfg.mqttPort}',
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Puerto', inicial: '${cfg.mqttPort}', numerico: true);
              final p = int.tryParse(v ?? '');
              if (p != null && p > 0 && p < 65536) {
                cfg.mqttPort = p;
                s.reconectar();
              }
            },
          ),
          _Fila(
            icon: Icons.route_outlined,
            titulo: 'Ruta',
            valor: cfg.mqttRuta.isEmpty ? '/' : cfg.mqttRuta,
            onTap: () async {
              final v = await _pedirTexto(context,
                  titulo: 'Ruta WebSocket', inicial: cfg.mqttRuta, ayuda: 'Ej. / o /mqtt');
              if (v != null) {
                cfg.mqttRuta = v.trim();
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
            final v = await _pedirTexto(context, titulo: 'Nodo', inicial: cfg.nodo, ayuda: 'Ej. nodo1');
            if (v != null && v.trim().isNotEmpty) {
              cfg.nodo = v.trim();
              s.reconectar();
            }
          },
        ),
        const SizedBox(height: Esp.s),
        Text(
          'Visto por última vez: '
          '${s.recibido == null ? sinValor : '${hhmm(s.recibido!)} (${haceTiempo(s.recibido, s.ahora)})'}',
          style: TextStyle(fontSize: 12, color: c.texto2),
        ),
        if (s.errorConexion != null) ...[
          const SizedBox(height: Esp.s),
          AvisoLinea(color: Palette.error, icon: Icons.error_outline, text: s.errorConexion!),
        ],
      ]),
    );
  }
}

class _Medicion extends StatelessWidget {
  const _Medicion();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    final c = context.ag;
    void set(VoidCallback f) {
      f();
      s.guardarSettings();
    }

    return SectionCard(
      title: 'Medición',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Interruptor(
          icon: Icons.sensors,
          titulo: 'Usar sensor de temperatura',
          subtitulo: s.ultimo?.tempC == null ? 'El equipo no envía temperatura' : null,
          valor: cfg.usarSensorTemp,
          onChanged: (v) => set(() => cfg.usarSensorTemp = v),
        ),
        _Fila(
          icon: Icons.thermostat,
          titulo: 'Temperatura en uso',
          valor: '${s.temperatura.tempC.toStringAsFixed(1)} °C'
              '${s.temperatura.supuesta ? ' · supuesta' : ' · sensor'}',
        ),
        _Fila(
          icon: Icons.edit_outlined,
          titulo: 'Temperatura capturada',
          valor: '${cfg.tempAguaC.toStringAsFixed(1)} °C',
          onTap: () async {
            final v = await _pedirTexto(context,
                titulo: 'Temperatura del agua (°C)',
                inicial: cfg.tempAguaC.toStringAsFixed(1),
                numerico: true);
            final t = double.tryParse((v ?? '').replaceAll(',', '.'));
            if (t != null && t > 0 && t < 60) set(() => cfg.tempAguaC = t);
          },
        ),
        const SizedBox(height: Esp.s),
        Text('Meta de HOCl por defecto: ${cfg.metaHoclPct.round()} %',
            style: TextStyle(fontSize: 14, color: c.texto)),
        Slider(
          min: 50,
          max: 99,
          divisions: 49,
          value: cfg.metaHoclPct.clamp(50, 99).toDouble(),
          onChanged: (v) => set(() => cfg.metaHoclPct = v.roundToDouble()),
        ),
        Row(children: [
          Expanded(
              child: Text('Modo de umbral por defecto',
                  style: TextStyle(fontSize: 14, color: c.texto))),
          SegmentedButton<ModoUmbral>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: ModoUmbral.ph, label: Text('pH')),
              ButtonSegment(value: ModoUmbral.eficacia, label: Text('Eficacia')),
            ],
            selected: {cfg.modoUmbral},
            onSelectionChanged: (v) => set(() => cfg.modoUmbral = v.first),
          ),
        ]),
      ]),
    );
  }
}

class _Mantenimiento extends StatelessWidget {
  const _Mantenimiento();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = context.ag;
    final calib = s.ultimo?.calib;
    return SectionCard(
      title: 'Mantenimiento',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Calibración: offset ${fmtNum(calib?.offset, dec: 2)} · ${calib?.fecha ?? 'sin fecha'}',
          style: TextStyle(fontSize: 13, color: c.texto2),
        ),
        const SizedBox(height: Esp.m),
        Wrap(spacing: Esp.s, runSpacing: Esp.s, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Calibrar'),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('Rellené el ácido (100 mL)'),
            onPressed: () async {
              try {
                await s.rellenarAcido();
              } catch (_) {}
            },
          ),
        ]),
      ]),
    );
  }
}

class _NotifTecnico extends StatelessWidget {
  const _NotifTecnico();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    void set(VoidCallback f) {
      f();
      s.guardarSettings();
    }

    return SectionCard(
      title: 'Avisos del técnico',
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
            titulo: 'Errores y fallas',
            valor: cfg.notifError,
            onChanged: (v) => set(() => cfg.notifError = v)),
        _Interruptor(
            icon: Icons.warning_amber_rounded,
            titulo: 'Fuera de norma',
            valor: cfg.notifFueraNorma,
            onChanged: (v) => set(() => cfg.notifFueraNorma = v)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Piezas

class _Fila extends StatelessWidget {
  const _Fila({required this.icon, required this.titulo, this.valor, this.onTap});
  final IconData icon;
  final String titulo;
  final String? valor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ag;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 21),
      title: Text(titulo, style: TextStyle(fontSize: 15, color: c.texto)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (valor != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(valor!,
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.texto2)),
          ),
        if (onTap != null) Icon(Icons.chevron_right, color: c.texto2),
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
    final c = context.ag;
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, size: 21, color: c.texto2),
      title: Text(titulo, style: TextStyle(fontSize: 15, color: c.texto)),
      subtitle: subtitulo == null
          ? null
          : Text(subtitulo!, style: TextStyle(fontSize: 12, color: c.texto2)),
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
        keyboardType: numerico
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(helperText: ayuda),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Aceptar')),
      ],
    ),
  );
}
