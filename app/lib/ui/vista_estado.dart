// Traduce el estado de la app a lo que se muestra: color, textos, íconos.
// Centralizado para que todas las vistas resuelvan igual los casos
// sin conexión / datos viejos / falla de sensor.
import 'package:material_ui/material_ui.dart';

import '../core/chem.dart';
import '../core/palette.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'format.dart';

class VistaEstado {
  const VistaEstado({
    required this.relleno,
    required this.punto,
    required this.indicador,
    required this.atenuado,
    required this.titulo,
    this.detalle,
    this.queHacer,
    this.icono,
  });

  final Color relleno; // color del círculo (paleta)
  final Color punto; // color del punto de estado
  final bool indicador; // mostrar color del indicador universal
  final bool atenuado;
  final String titulo;
  final String? detalle;
  final String? queHacer; // una línea si hay alerta
  final IconData? icono;
}

VistaEstado vistaDe(AppState s) {
  final t = s.ultimo;

  if (t == null) {
    return VistaEstado(
      relleno: Palette.sinDatos,
      punto: Palette.sinDatos,
      indicador: false,
      atenuado: false,
      titulo: 'Sin datos recientes',
      detalle: s.sinConexion
          ? 'Sin conexión. El control local sigue protegido'
          : 'Esperando la primera lectura…',
      icono: Icons.hourglass_empty,
    );
  }

  if (s.sinConexion) {
    return VistaEstado(
      relleno: Palette.sinDatos,
      punto: Palette.sinDatos,
      indicador: false,
      atenuado: true,
      titulo: 'Sin conexión',
      detalle: 'Sin conexión. El control local sigue protegido\n'
          'Último valor a las ${hhmm(s.recibido!)}',
      queHacer: 'Consulta de nuevo en unos minutos.',
      icono: Icons.cloud_off,
    );
  }

  if (!s.sensorOk) {
    return const VistaEstado(
      relleno: Palette.sinDatos,
      punto: Palette.sinDatos,
      indicador: false,
      atenuado: false,
      titulo: 'Revisar sensor',
      detalle: 'La sonda no está dando lecturas confiables.',
      queHacer: 'El operador debe revisar la sonda de pH.',
      icono: Icons.sensors_off,
    );
  }

  final enNorma = nomStatus(t.ph) == NomStatus.enRango;
  final cerca = enNorma && (t.ph < nomMin + 0.1 || t.ph > nomMax - 0.1);
  final est = t.estado ?? CtrlEstado.idle;

  final relleno = !enNorma
      ? Palette.error
      : est == CtrlEstado.pulso
          ? Palette.dosificando
          : est == CtrlEstado.mezcla
              ? Palette.mezclando
              : cerca
                  ? Palette.precaucion
                  : Palette.normal;

  if (s.datosViejos) {
    return VistaEstado(
      relleno: relleno,
      punto: Palette.sinDatos,
      indicador: true,
      atenuado: true,
      titulo: 'Sin datos recientes',
      detalle: 'La última lectura tiene más de 10 s.',
      icono: Icons.schedule,
    );
  }

  if (!enNorma) {
    return VistaEstado(
      relleno: relleno,
      punto: Palette.error,
      indicador: true,
      atenuado: false,
      titulo: 'Fuera de rango — el operador fue notificado',
      detalle: 'La norma (NOM-127) pide pH entre 6.5 y 8.5.',
      queHacer: 'Evita usarla para beber hasta que el operador la revise.',
      icono: Icons.warning_amber_rounded,
    );
  }

  return VistaEstado(
    relleno: relleno,
    punto: cerca ? Palette.precaucion : Palette.normal,
    indicador: true,
    atenuado: false,
    titulo: 'Dentro del rango de la norma',
    detalle: cerca
        ? 'Cerca del límite de la norma (6.5–8.5).'
        : 'La norma (NOM-127) pide pH entre 6.5 y 8.5.',
  );
}

/// Estado del controlador en lenguaje claro (solo técnico).
({String texto, Color color, IconData icono}) textoControlador(Telemetria? t) {
  switch (t?.estado ?? CtrlEstado.idle) {
    case CtrlEstado.idle:
      return (texto: 'Listo', color: Palette.normal, icono: Icons.check_circle);
    case CtrlEstado.pulso:
      return (
        texto: 'Dosificando',
        color: Palette.dosificando,
        icono: Icons.water_drop
      );
    case CtrlEstado.mezcla:
      return (
        texto: 'Mezclando, esperando lectura estable',
        color: Palette.mezclando,
        icono: Icons.autorenew
      );
    case CtrlEstado.error:
      return (
        texto: 'Error: ${t?.errorMsg ?? 'sin detalle'}',
        color: Palette.error,
        icono: Icons.error
      );
  }
}
