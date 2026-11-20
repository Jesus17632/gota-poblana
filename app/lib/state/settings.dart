import 'package:shared_preferences/shared_preferences.dart';

import '../core/device_constants.dart';

enum FuenteDatos { simulador, mqtt }

enum ModoUmbral { ph, eficacia }

enum ModoTema { sistema, claro, oscuro }

/// Preferencias persistentes (SharedPreferences).
class Settings {
  FuenteDatos fuente =
      DeviceConst.mqttHabilitado ? FuenteDatos.mqtt : FuenteDatos.simulador;
  String mqttHost = DeviceConst.mqttHostPorDefecto;
  int mqttPort = DeviceConst.mqttPuertoPorDefecto;
  String mqttRuta = DeviceConst.mqttRutaPorDefecto;
  String nodo = DeviceConst.nodoPorDefecto;
  String ubicacion = ''; // vacío = usar la que manda el firmware

  double tempAguaC = 22.0;
  bool usarSensorTemp = false;
  double metaHoclPct = 90.0;
  ModoUmbral modoUmbral = ModoUmbral.ph;
  ModoTema tema = ModoTema.sistema;
  bool onboardingVisto = false;
  bool tecnico = false; // rol elegido en el onboarding o en Ajustes

  bool movimientoReducido = false;
  bool sonidos = true;
  bool vibracion = true;
  bool notifSistema = true; // notificaciones fuera de la app
  bool monitoreoFondo = true; // Android: seguir conectado en segundo plano
  bool notifAlertas = true; // ciudadano
  bool notifInicio = true;
  bool notifFin = true;
  bool notifError = true;
  bool notifFueraNorma = true;

  static const _p = 'cfg.';

  /// Sube este número cuando cambien los valores por defecto de conexión,
  /// para que se apliquen aunque ya hubiera ajustes guardados.
  static const _versionConexion = 3; // 3: red propia del ESP32 por defecto

  void load(SharedPreferences prefs) {
    if ((prefs.getInt('${_p}versionConexion') ?? 1) < _versionConexion) {
      // Migración: aplica los nuevos valores por defecto de conexión.
      prefs.remove('${_p}fuente');
      prefs.remove('${_p}mqttHost');
      prefs.remove('${_p}mqttPort');
      prefs.remove('${_p}mqttRuta');
      prefs.setInt('${_p}versionConexion', _versionConexion);
    }
    fuente = FuenteDatos.values.byName(
        prefs.getString('${_p}fuente') ?? fuente.name);
    mqttHost = prefs.getString('${_p}mqttHost') ?? mqttHost;
    mqttPort = prefs.getInt('${_p}mqttPort') ?? mqttPort;
    mqttRuta = prefs.getString('${_p}mqttRuta') ?? mqttRuta;
    sonidos = prefs.getBool('${_p}sonidos') ?? sonidos;
    notifSistema = prefs.getBool('${_p}notifSistema') ?? notifSistema;
    monitoreoFondo = prefs.getBool('${_p}monitoreoFondo') ?? monitoreoFondo;
    vibracion = prefs.getBool('${_p}vibracion') ?? vibracion;
    nodo = prefs.getString('${_p}nodo') ?? nodo;
    ubicacion = prefs.getString('${_p}ubicacion') ?? ubicacion;
    tempAguaC = prefs.getDouble('${_p}tempAguaC') ?? tempAguaC;
    usarSensorTemp = prefs.getBool('${_p}usarSensorTemp') ?? usarSensorTemp;
    metaHoclPct = prefs.getDouble('${_p}metaHoclPct') ?? metaHoclPct;
    modoUmbral = ModoUmbral.values
        .byName(prefs.getString('${_p}modoUmbral') ?? ModoUmbral.ph.name);
    tema = ModoTema.values
        .byName(prefs.getString('${_p}tema') ?? ModoTema.sistema.name);
    onboardingVisto = prefs.getBool('${_p}onboardingVisto') ?? onboardingVisto;
    tecnico = prefs.getBool('${_p}tecnico') ?? tecnico;
    movimientoReducido =
        prefs.getBool('${_p}movimientoReducido') ?? movimientoReducido;
    notifAlertas = prefs.getBool('${_p}notifAlertas') ?? notifAlertas;
    notifInicio = prefs.getBool('${_p}notifInicio') ?? notifInicio;
    notifFin = prefs.getBool('${_p}notifFin') ?? notifFin;
    notifError = prefs.getBool('${_p}notifError') ?? notifError;
    notifFueraNorma = prefs.getBool('${_p}notifFueraNorma') ?? notifFueraNorma;
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('${_p}fuente', fuente.name);
    await prefs.setString('${_p}mqttHost', mqttHost);
    await prefs.setInt('${_p}mqttPort', mqttPort);
    await prefs.setString('${_p}mqttRuta', mqttRuta);
    await prefs.setBool('${_p}sonidos', sonidos);
    await prefs.setBool('${_p}notifSistema', notifSistema);
    await prefs.setBool('${_p}monitoreoFondo', monitoreoFondo);
    await prefs.setBool('${_p}vibracion', vibracion);
    await prefs.setString('${_p}nodo', nodo);
    await prefs.setString('${_p}ubicacion', ubicacion);
    await prefs.setDouble('${_p}tempAguaC', tempAguaC);
    await prefs.setBool('${_p}usarSensorTemp', usarSensorTemp);
    await prefs.setDouble('${_p}metaHoclPct', metaHoclPct);
    await prefs.setString('${_p}modoUmbral', modoUmbral.name);
    await prefs.setString('${_p}tema', tema.name);
    await prefs.setBool('${_p}onboardingVisto', onboardingVisto);
    await prefs.setBool('${_p}tecnico', tecnico);
    await prefs.setBool('${_p}movimientoReducido', movimientoReducido);
    await prefs.setBool('${_p}notifAlertas', notifAlertas);
    await prefs.setBool('${_p}notifInicio', notifInicio);
    await prefs.setBool('${_p}notifFin', notifFin);
    await prefs.setBool('${_p}notifError', notifError);
    await prefs.setBool('${_p}notifFueraNorma', notifFueraNorma);
  }
}
