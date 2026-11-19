import 'package:shared_preferences/shared_preferences.dart';

enum FuenteDatos { simulador, mqtt }

enum ModoUmbral { ph, eficacia }

/// Preferencias persistentes (SharedPreferences).
class Settings {
  FuenteDatos fuente = FuenteDatos.simulador;
  String mqttHost = 'broker.hivemq.com';
  int mqttPort = 8000;
  String nodo = 'nodo1';
  String ubicacion = ''; // vacío = usar la que manda el firmware

  double tempAguaC = 22.0;
  bool usarSensorTemp = false;
  double metaHoclPct = 90.0;
  ModoUmbral modoUmbral = ModoUmbral.ph;
  String pin = '1234';

  bool movimientoReducido = false;
  bool notifAlertas = true; // ciudadano
  bool notifInicio = true;
  bool notifFin = true;
  bool notifError = true;
  bool notifFueraNorma = true;

  static const _p = 'cfg.';

  void load(SharedPreferences prefs) {
    fuente = FuenteDatos.values.byName(
        prefs.getString('${_p}fuente') ?? FuenteDatos.simulador.name);
    mqttHost = prefs.getString('${_p}mqttHost') ?? mqttHost;
    mqttPort = prefs.getInt('${_p}mqttPort') ?? mqttPort;
    nodo = prefs.getString('${_p}nodo') ?? nodo;
    ubicacion = prefs.getString('${_p}ubicacion') ?? ubicacion;
    tempAguaC = prefs.getDouble('${_p}tempAguaC') ?? tempAguaC;
    usarSensorTemp = prefs.getBool('${_p}usarSensorTemp') ?? usarSensorTemp;
    metaHoclPct = prefs.getDouble('${_p}metaHoclPct') ?? metaHoclPct;
    modoUmbral = ModoUmbral.values
        .byName(prefs.getString('${_p}modoUmbral') ?? ModoUmbral.ph.name);
    pin = prefs.getString('${_p}pin') ?? pin;
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
    await prefs.setString('${_p}nodo', nodo);
    await prefs.setString('${_p}ubicacion', ubicacion);
    await prefs.setDouble('${_p}tempAguaC', tempAguaC);
    await prefs.setBool('${_p}usarSensorTemp', usarSensorTemp);
    await prefs.setDouble('${_p}metaHoclPct', metaHoclPct);
    await prefs.setString('${_p}modoUmbral', modoUmbral.name);
    await prefs.setString('${_p}pin', pin);
    await prefs.setBool('${_p}movimientoReducido', movimientoReducido);
    await prefs.setBool('${_p}notifAlertas', notifAlertas);
    await prefs.setBool('${_p}notifInicio', notifInicio);
    await prefs.setBool('${_p}notifFin', notifFin);
    await prefs.setBool('${_p}notifError', notifError);
    await prefs.setBool('${_p}notifFueraNorma', notifFueraNorma);
  }
}
