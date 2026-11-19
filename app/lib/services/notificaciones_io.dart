import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notificaciones.dart';

Notificaciones crear() =>
    (Platform.isAndroid || Platform.isLinux) ? _NotifPlugin() : Notificaciones();

class _NotifPlugin extends Notificaciones {
  final _p = FlutterLocalNotificationsPlugin();
  bool _listo = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  bool get disponible => _listo;

  @override
  bool get soportaMonitoreo => Platform.isAndroid;

  @override
  Future<void> iniciar() async {
    try {
      await _p.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
        ),
      );
      _listo = true;
    } catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }
  }

  @override
  Future<bool> pedirPermiso() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('No se pudo pedir permiso de notificaciones: $e');
      return false;
    }
  }

  @override
  Future<void> mostrar({
    required int id,
    required String titulo,
    required String cuerpo,
    bool critica = false,
  }) async {
    if (!_listo) return;
    try {
      await _p.show(
        id: id,
        title: titulo,
        body: cuerpo,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            critica ? 'agua_alertas' : 'agua_avisos',
            critica ? 'Alertas del equipo' : 'Avisos de dosificación',
            channelDescription: critica
                ? 'Fallas, errores y agua fuera de norma'
                : 'Inicio y fin de la dosificación',
            importance: critica ? Importance.max : Importance.high,
            priority: Priority.high,
            color: critica ? const Color(0xFFE5484D) : const Color(0xFF218DAE),
            category: critica
                ? AndroidNotificationCategory.alarm
                : AndroidNotificationCategory.status,
          ),
          linux: const LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }

  @override
  Future<void> monitoreo(bool activo, {String? texto}) async {
    if (!Platform.isAndroid || !_listo) return;
    try {
      if (activo) {
        await _android?.startForegroundService(
          id: 1,
          title: 'Monitoreando el agua',
          body: texto ?? 'La app sigue conectada al equipo',
          notificationDetails: const AndroidNotificationDetails(
            'agua_monitoreo',
            'Monitoreo en segundo plano',
            channelDescription: 'Mantiene la conexión con el equipo',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
          ),
          foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
        );
      } else {
        await _android?.stopForegroundService();
      }
    } catch (e) {
      debugPrint('No se pudo cambiar el monitoreo: $e');
    }
  }
}
