// Catálogo de fallas de hardware (campo "fallas" del tema hardware).
// Los CÓDIGOS son parte del contrato con el firmware (agua_contrato.h).
// Los textos son de la app y se pueden cambiar libremente.

enum Severidad { critica, advertencia }

class InfoFalla {
  final String titulo;
  final String queHacer;
  final String? modulo; // XC01, XN03, XN13, XN44, PH, TEMP
  final Severidad severidad; // por defecto, si el firmware no la manda
  const InfoFalla(this.titulo, this.queHacer, this.modulo, this.severidad);
}

class Fallas {
  Fallas._();

  static const sensorPhDesconectado = 'SENSOR_PH_DESCONECTADO';
  static const sensorPhFueraRango = 'SENSOR_PH_FUERA_RANGO';
  static const sensorPhSinRespuesta = 'SENSOR_PH_SIN_RESPUESTA';
  static const sensorTempDesconectado = 'SENSOR_TEMP_DESCONECTADO';
  static const bombaDesconectada = 'BOMBA_DESCONECTADA';
  static const releNoResponde = 'RELE_NO_RESPONDE';
  static const buzzerNoResponde = 'BUZZER_NO_RESPONDE';
  static const ledNoResponde = 'LED_NO_RESPONDE';
  static const busI2c = 'I2C_BUS_ERROR';
  static const acidoAgotado = 'ACIDO_AGOTADO';
  static const acidoBajo = 'ACIDO_BAJO';
  static const calibracionPendiente = 'CALIBRACION_PENDIENTE';
  static const wifiDebil = 'WIFI_DEBIL';

  static const Map<String, InfoFalla> catalogo = {
    sensorPhDesconectado: InfoFalla('Sonda de pH desconectada',
        'Revisa el cable de la sonda en la entrada AN.', 'PH', Severidad.critica),
    sensorPhFueraRango: InfoFalla('Lectura de pH fuera de rango',
        'Revisa la sonda o recalibra con solución conocida.', 'PH',
        Severidad.critica),
    sensorPhSinRespuesta: InfoFalla('Sonda de pH sin respuesta',
        'Revisa la sonda y su conexión.', 'PH', Severidad.critica),
    sensorTempDesconectado: InfoFalla('Sensor de temperatura desconectado',
        'Se usará la temperatura capturada en Ajustes.', 'TEMP',
        Severidad.advertencia),
    bombaDesconectada: InfoFalla('Bomba desconectada',
        'Revisa la bomba de 12 V y la clema del relé.', 'XN13',
        Severidad.critica),
    releNoResponde: InfoFalla('El relé no responde',
        'Revisa el módulo XN13 en el bus I2C (0x0D).', 'XN13',
        Severidad.critica),
    buzzerNoResponde: InfoFalla('El buzzer no responde',
        'Revisa el módulo XN44 (0x2C). Las alertas siguen en la app.', 'XN44',
        Severidad.advertencia),
    ledNoResponde: InfoFalla('El LED no responde',
        'Revisa el módulo XN03 (0x03).', 'XN03', Severidad.advertencia),
    busI2c: InfoFalla('Error en el bus I2C',
        'Revisa los cables Qwiic y la alimentación de los módulos.', 'XC01',
        Severidad.critica),
    acidoAgotado: InfoFalla('Ácido agotado',
        'Rellena el depósito y pulsa "Rellené el ácido".', null,
        Severidad.critica),
    acidoBajo: InfoFalla('Queda poco ácido',
        'Prepara la recarga del depósito.', null, Severidad.advertencia),
    calibracionPendiente: InfoFalla('Calibración pendiente',
        'Calibra con una solución de pH conocido.', 'PH',
        Severidad.advertencia),
    wifiDebil: InfoFalla('Señal Wi-Fi débil',
        'Acerca el equipo al punto de acceso.', 'XC01', Severidad.advertencia),
  };

  static InfoFalla info(String codigo) =>
      catalogo[codigo] ??
      InfoFalla('Falla: $codigo', 'Consulta el registro del equipo.', null,
          Severidad.critica);
}
