// ============================================================================
//  main.cpp — Control de pH Adaptativo + Broker MQTT WebSocket + HTTP Server
//  Hardware: XC01-R5 (ESP32-S3) + XN03 (ADC/RGB) + XN13 (Relé) + XN44 (Buzzer)
//  Contrato: agua_contrato.h / CONTRATO.md
//  Nube: Blynk.Cloud (requisito 6 del reto) — pines virtuales V0-V5 y V11
// ============================================================================

// ======================= BLYNK.CLOUD ==================================
// 1) Pega aquí las 3 líneas de Blynk: Devices -> tu dispositivo -> Device Info.
// 2) NO subas este archivo a GitHub con el token pegado (el repo es público).
// 3) USE_BLYNK 0 = corre sin Blynk (solo app MQTT + pantalla).
#define USE_BLYNK 1
#define BLYNK_TEMPLATE_ID   "TMPL27QS6E8yW"
#define BLYNK_TEMPLATE_NAME "AguaHack"
#define BLYNK_AUTH_TOKEN    "4xWmjecOS67NI5t4KJNRVcXp8UVcIOkF"
#define BLYNK_PRINT Serial   // muestra en el Monitor Serie el estado de conexión

#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <PicoMQTT.h>
#include <PicoWebsocket.h>
#include "agua_contrato.h"

#if USE_BLYNK
  #include <BlynkSimpleEsp32.h>
#endif


#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SH1106G display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);
bool pantallaOk = false;

// ======================= 0. CONFIGURACIÓN DE RED =====================
// true  = (POR DEFECTO) el ESP32 crea su propia red al instante: AP_SSID,
//         broker en ws://192.168.4.1:81/. Sin internet (Blynk no aplica).
// false = se conecta al hotspot WIFI_SSID; si no aparece en 20 s, abre su
//         propia red como respaldo.
const bool MODO_AP = true;
bool apActivo = MODO_AP;   // true cuando el ESP32 está sirviendo su propia red

const char* WIFI_SSID = "iPhone de Jesus";
const char* WIFI_PASS = "12345678";

const char* AP_SSID   = "ESP32S3-Sensor";
const char* AP_PASS   = "12345678";

const char* UBICACION_NODO = "Mesa 4";

// Si conectas la sonda directo al pin analógico GPIO 4 (PIN_PH_AN) en lugar
// del módulo I2C XN03 (canal IN1), cambia esto a 1:
#define USAR_ADC_DIRECTO_GPIO4 0

// ======================= 1. SERVIDORES (HTTP :80 + MQTT WS :81) ======
WebServer httpServer(80);
WiFiServer wsUnderlyingServer(MQTT_WS_PUERTO); // Puerto 81
PicoWebsocket::Server<::WiFiServer> wsServer(wsUnderlyingServer);
PicoMQTT::Server mqtt(wsServer);

// ======================= 2. TIPOS DE DATOS ===========================
enum Estado { IDLE, PULSO, AGITA, MEZCLA, RAFAGA, ERROR_ST };
enum Modo   { MODO_CONTROL, MODO_TITULACION, MODO_MANUAL };
struct Nota { uint16_t f, d; };

struct FallaActiva {
  const char* codigo;
  const char* severidad;
  const char* modulo;
  String      detalle;
};

// ======================= 3. REGISTROS I2C X-NODE =====================
const uint8_t REG_XN03_IN1   = 0x21;  // Canal analógico IN1 (sonda pH) 10 bits
const uint8_t LED_INTENSIDAD = 180;   // Brillo global LED RGB del XN03 (0-255)
#define RELAY_ON   HIGH
#define RELAY_OFF  LOW

// ======================= 4. CALIBRACIÓN Y CONVERSIÓN VOLTAJE -> pH ===
// Relación lineal decreciente de la sonda (ADC 10 bits 0-1023, ref 3.3 V):
//   pH 0 -> 2.877 V (892) | pH 7 -> 1.648 V (511) | pH 14 -> 0.419 V (130)
const float V_REF_XN03 = 3.300f;
const float V_PH7      = 1.648f;      // Voltaje nominal en pH 7.00
const float S_V_PH     = 0.175571f;   // Pendiente nominal a 25 °C (V/pH)
float       offsetPH   = 0.0f;        // Offset de calibración de 1 punto ('c')
bool        calibrado  = false;       // Marca si ya se calibró al menos una vez

// ======================= 5. MODELO DE BOMBA Y CONTROL ================
float          q_mL_ms      = ML_POR_SEGUNDO / 1000.0f; // 0.033 mL/ms = 33 mL/s
float          t0_ms        = 0.0f;
const uint32_t PULSO_MIN_MS = 50;

float tolerancia    = TOLERANCIA_FIN; // 0.03 pH (contrato)
// Control conservador (sin calibración fina de la bomba se pasaba del umbral):
//  - gammaCtl: fracción de lo que falta que se intenta bajar en cada pulso
//  - cerca del umbral (< ZONA_APROX pH) se usa gammaCerca, aún más suave
//  - volMaxPaso: tope de mL por pulso
float gammaCtl      = 0.40f;   // antes 0.60
float gammaCerca    = 0.25f;
const float ZONA_APROX = 0.30f;
float volMaxPaso    = 3.0f;    // antes 10.0
float volMaxSesion  = 95.0f;
float volTitulacion = 1.0f;

const float    SIN_RESPUESTA_PH = 0.02f;
const uint32_t MEZCLA_MAX_MS    = 60000;
const float    PKA_HOCL         = 7.5f;

// ======================= 6. ADQUISICIÓN Y ESTABILIDAD ================
const uint8_t  N_SOBREMUESTREO = 8;
const uint32_t T_MUESTREO_MS   = 50;
const float    ALPHA_EMA       = 0.15f;
const uint32_t T_ESTAB_MS      = 250;
const uint8_t  N_ESTAB         = 12;
const float    PENDIENTE_MAX   = 0.005f;
const float    SIGMA_MAX       = 0.02f;

// ======================= 7. ESTADO GLOBAL Y CONTRATO =================
EstadoNodo st; // Estructura oficial de agua_contrato.h
Estado estado = IDLE;
Modo   modo   = MODO_CONTROL;

// Variables de medición y filtrado
float   adcCrudo  = 511.0f;
float   phCrudo   = 7.0f;
float   phFilt    = 7.0f;
float   med5[5]   = {7.0f, 7.0f, 7.0f, 7.0f, 7.0f};
uint8_t iMed      = 0;
bool    i2cPhOk   = false;
bool    busI2cOk  = true;

// Detección de lectura congelada
float    ultimoAdcEstable = -1.0f;
uint32_t tAdcSinCambio    = 0;
bool     phCongelado      = false;

// Ventana de estabilidad
float   bufEstab[N_ESTAB];
uint8_t iEstab    = 0;
uint8_t nEstab    = 0;
float   pendiente = 0.0f;
float   sigma     = 0.0f;

// Variables de dosificación
float    phAntes       = 0.0f;
float    ultimoVol     = 0.0f;
float    sEst          = -1.0f;
uint8_t  sinRespuesta  = 0;
uint32_t tFinPulso     = 0;
uint32_t tInicioMezcla = 0;
uint32_t tBombaOn      = 0;
String   cmdPulsoManual = ""; // Guarda "p <ms>" para responder RELE_OFF con cmd

// Resumen de última sesión completada
bool     tieneResumen  = false;
float    resUmbral     = 6.60f;
float    resPhFinal    = 0.0f;
float    resError      = 0.0f;
uint16_t resPulsos     = 0;
float    resMl         = 0.0f;
uint32_t resSegundos   = 0;

// Ráfagas de calibración por Serial ('r')
uint16_t rafagaN      = 0;
uint16_t rafagaHechos = 0;
uint32_t rafagaMs     = 0;
uint32_t rafagaGap    = 1000;
uint32_t tProxRafaga  = 0;

// Estado de módulos I2C y fallas
bool modXN03Ok = false;
bool modXN13Ok = false;
bool modXN44Ok = false;
bool hayFallaCritica = false;
String descFallaCritica = "";
String ultimaFallaCriticaNotificada = "";

// Override temporal para comando test_led
uint32_t tLedTestHasta = 0;
bool telemetriaSerial = false; // Desactivado por defecto para no saturar mensajes de estado

// ======================= PROTOTIPOS ==================================
void publicarEvento(const char* tipo, const String& detalle, const String& cmd = "");
void publicarTelemetria(bool incluirResumen = false);
void publicarHardware();
void entrarError(const String& motivo, bool publicarEv = true);
void detenerTodo(const String& motivo, const String& cmdOrigen = "");
void iniciarSesion(Modo m, const String& cmdOrigen = "");
void aplicarColorLED(uint8_t r, uint8_t g, uint8_t b, bool forzar = false);
void pulso(float ml, const String& cmdOrigen = "");
void evaluarDiagnosticoHardware(bool forzarPublicacion = false);

// ======================= 8. DRIVERS I2C DE LOS X-NODE ================
bool verificarModuloI2C(uint8_t addr) {
  Wire.beginTransmission(addr);
  uint8_t err = Wire.endTransmission();
  if (err == 4) busI2cOk = false;
  return (err == 0);
}

int16_t readXN03_ADC(uint8_t reg) {
  Wire.beginTransmission(I2C_XN03);
  Wire.write(reg);
  uint8_t err = Wire.endTransmission();
  if (err != 0) {
    if (err == 4) busI2cOk = false;
    return -1;
  }
  if (Wire.requestFrom(I2C_XN03, (uint8_t)2) < 2) return -1;
  uint16_t val = ((uint16_t)Wire.read() << 8) & 0xFF00;
  val |= Wire.read();
  return (int16_t)val;
}

bool setColorXN03(uint8_t r, uint8_t g, uint8_t b, uint8_t intensity) {
  Wire.beginTransmission(I2C_XN03);
  Wire.write(REG_XN03_LED);
  Wire.write(r);
  Wire.write(g);
  Wire.write(b);
  Wire.write(intensity);
  return (Wire.endTransmission() == 0);
}

bool writeXN13(bool stat) {
  Wire.beginTransmission(I2C_XN13);
  Wire.write(stat ? RELAY_ON : RELAY_OFF);
  return (Wire.endTransmission() == 0);
}

int8_t toneXN44(uint16_t freq, uint16_t note_duration) {
  Wire.beginTransmission(I2C_XN44);
  Wire.write(REG_XN44_TONE);
  Wire.write((uint8_t)(freq >> 8));
  Wire.write((uint8_t)(freq & 0xFF));
  Wire.write((uint8_t)(note_duration >> 8));
  Wire.write((uint8_t)(note_duration & 0xFF));
  return Wire.endTransmission();
}

int8_t noToneXN44() {
  Wire.beginTransmission(I2C_XN44);
  Wire.write(REG_XN44_TONE);
  Wire.write((uint8_t)0x00);
  Wire.write((uint8_t)0x00);
  return Wire.endTransmission();
}

// ======================= 9. CONVERSIÓN VOLTAJE -> pH Y CÁLCULOS ======
// Convierte voltaje de la sonda (V) a pH con compensación Nernst por temperatura
float pHdesdeVolt(float v) {
  float S = S_V_PH * (st.temp_c + 273.15f) / 298.15f;
  return 7.0f + (V_PH7 - v) / S + offsetPH;
}

float fraccionHOCl(float ph) {
  return 1.0f / (1.0f + powf(10.0f, ph - PKA_HOCL));
}

float volMinPulso() {
  return max(q_mL_ms * ((float)PULSO_MIN_MS - t0_ms), 0.01f);
}

uint32_t msParaVolumen(float ml) {
  float t = t0_ms + ml / q_mL_ms;
  return (uint32_t)constrain(t, (float)PULSO_MIN_MS, (float)PULSO_MAX_MS);
}

float volumenParaMs(uint32_t ms) {
  return max(q_mL_ms * ((float)ms - t0_ms), 0.0f);
}

float mediana5(const float* a) {
  float b[5];
  memcpy(b, a, sizeof(b));
  for (int i = 1; i < 5; i++) {
    float k = b[i];
    int j = i - 1;
    while (j >= 0 && b[j] > k) { b[j + 1] = b[j]; j--; }
    b[j + 1] = k;
  }
  return b[2];
}

const char* estadoContratoStr() {
  switch (estado) {
    case IDLE:     return ESTADO_IDLE;
    case PULSO:    return ESTADO_PULSO;
    case RAFAGA:   return ESTADO_PULSO;
    case AGITA:    return ESTADO_MEZCLA;
    case MEZCLA:   return ESTADO_MEZCLA;
    case ERROR_ST: return ESTADO_ERROR;
    default:       return ESTADO_IDLE;
  }
}

void msgSerial(const String& s) {
  Serial.print(">> ");
  Serial.println(s);
}

// ======================= 10. BUZZER NO BLOQUEANTE (XN44) =============
// Secuencias definidas en agua_contrato.h sección 8:
const Nota SEC_INICIO[] = {{880, 150}, {0, 60}, {1320, 150}, {0, 0}};
const Nota SEC_FIN[]    = {{1320, 150}, {0, 60}, {1100, 150}, {0, 60}, {880, 150}, {0, 0}};
const Nota SEC_ERROR[]  = {{400, 150}, {0, 60}, {400, 150}, {0, 60}, {400, 150}, {0, 0}};

const Nota* secActual = nullptr;
uint8_t     iNota     = 0;
uint32_t    tNota     = 0;

void reproducir(const Nota* s) {
  secActual = s;
  iNota = 0;
  tNota = 0;
  st.buzzer_sonando = true;
}

void actualizarBuzzer() {
  if (!secActual || millis() < tNota) return;
  const Nota& n = secActual[iNota];
  if (n.d == 0) {
    noToneXN44();
    secActual = nullptr;
    st.buzzer_sonando = false;
    return;
  }
  if (n.f) toneXN44(n.f, n.d);
  else noToneXN44();
  tNota = millis() + n.d;
  iNota++;
}

// ======================= 11. LED RGB (XN03 + LED INTEGRADO XC01) =====
const uint8_t COLOR_PH[15][3] = {
  {170, 0, 0},   {255, 0, 0},   {255, 30, 0},  {255, 70, 0},  {255, 120, 0},
  {255, 180, 0}, {255, 255, 0}, {0, 200, 0},   {0, 180, 120}, {0, 80, 255},
  {0, 0, 170},   {75, 0, 170},  {140, 0, 220}, {120, 0, 180}, {80, 0, 120}
};

void aplicarColorLED(uint8_t r, uint8_t g, uint8_t b, bool forzar) {
  static uint8_t pr = 255, pg = 255, pb = 255;
  if (!forzar && r == pr && g == pg && b == pb) return;
  pr = r; pg = g; pb = b;
  st.led[0] = r;
  st.led[1] = g;
  st.led[2] = b;
  setColorXN03(r, g, b, LED_INTENSIDAD);
  neopixelWrite(PIN_LED_XC01, r / 4, g / 4, b / 4);
}

void actualizarLED(float ph) {
  if (millis() < tLedTestHasta) return; // Respeta test_led de la app por 5 s
  if (hayFallaCritica || estado == ERROR_ST) {
    aplicarColorLED(255, 0, 0); // Rojo si hay error en el sistema
    return;
  }
  ph = constrain(ph, 0.0f, 14.0f);
  int i = min((int)ph, 13);
  float f = ph - i;
  uint8_t c[3];
  for (int k = 0; k < 3; k++) {
    c[k] = COLOR_PH[i][k] + f * (COLOR_PH[i + 1][k] - COLOR_PH[i][k]);
  }
  aplicarColorLED(c[0], c[1], c[2]);
}

// ======================= 12. CONTROL FÍSICO DE LA BOMBA ==============
void bomba(bool on) {
  bool cambio = (st.bomba != on);
  writeXN13(on);
  st.bomba = on;
  if (on) tBombaOn = millis();
  if (cambio) publicarHardware();
}

void detenerTodo(const String& motivo, const String& cmdOrigen) {
  bool estabaEncendida = st.bomba;
  bomba(false);
  rafagaN = 0;
  sinRespuesta = 0;
  cmdPulsoManual = "";

  if (estabaEncendida) {
    publicarEvento(EV_RELE_OFF, "Bomba apagada (" + motivo + ")", cmdOrigen);
  }

  // El contrato indica: detener limpia ERROR solo si la falla crítica ya desapareció
  if (!hayFallaCritica) {
    estado = IDLE;
    st.estado = ESTADO_IDLE;
    st.error_msg = "";
    ultimaFallaCriticaNotificada = "";
  } else {
    estado = ERROR_ST;
    st.estado = ESTADO_ERROR;
    st.error_msg = "Error en el sistema, checar en la aplicacion: " + descFallaCritica;
  }
  msgSerial("Detenido: " + motivo);
}

void entrarError(const String& motivo, bool publicarEv) {
  bomba(false);
  rafagaN = 0;
  cmdPulsoManual = "";
  estado = ERROR_ST;
  st.estado = ESTADO_ERROR;
  st.error_msg = "Error en el sistema, checar en la aplicacion: " + motivo;
  reproducir(SEC_ERROR);
  aplicarColorLED(255, 0, 0);
  Serial.println("======================================================");
  Serial.println("[ALERTA] ERROR EN EL SISTEMA, checar en la aplicacion");
  Serial.println("         Motivo: " + motivo);
  Serial.println("======================================================");
  if (publicarEv) {
    publicarEvento(EV_ERROR, motivo);
  }
  publicarHardware();
}

void pulso(float ml, const String& cmdOrigen) {
  uint32_t ms = msParaVolumen(ml);
  ultimoVol = volumenParaMs(ms);
  phAntes = phFilt;
  bomba(true);
  tFinPulso = millis() + ms;
  st.ml_dosificados += ultimoVol;
  st.acido_restante_ml = max(0.0f, st.acido_restante_ml - ultimoVol);
  st.pulsos++;
  estado = PULSO;
  st.estado = ESTADO_PULSO;

  publicarEvento(EV_RELE_ON, "Pulso #" + String(st.pulsos) + " (" + String(ms) + " ms)", cmdOrigen);
  msgSerial("Pulso #" + String(st.pulsos) + ": " + String(ms) + " ms ≈ " + String(ultimoVol, 2) +
            " mL | Ácido restante: " + String(st.acido_restante_ml, 1) + " mL");
}

// ======================= 13. ADQUISICIÓN Y ESTABILIDAD ===============
void muestrear() {
#if USAR_ADC_DIRECTO_GPIO4
  uint32_t accMv = 0;
  for (uint8_t i = 0; i < N_SOBREMUESTREO; i++) {
    accMv += analogReadMilliVolts(PIN_PH_AN);
  }
  st.mv = accMv / (float)N_SOBREMUESTREO;
  adcCrudo = (st.mv / 3300.0f) * 1023.0f;
  i2cPhOk = true;
#else
  uint32_t acc = 0;
  uint8_t ok = 0;
  for (uint8_t i = 0; i < N_SOBREMUESTREO; i++) {
    int16_t raw = readXN03_ADC(REG_XN03_IN1);
    if (raw >= 0 && raw <= 1023) {
      acc += raw;
      ok++;
    }
  }
  if (ok == 0) {
    i2cPhOk = false;
    st.mv = 0.0f;
    return;
  }
  i2cPhOk = true;
  adcCrudo = acc / (float)ok;
  st.mv = adcCrudo * (V_REF_XN03 * 1000.0f / 1023.0f);
#endif

  // Conversión de voltaje (mV -> V) a pH con compensación de temperatura
  float phInstantaneo = pHdesdeVolt(st.mv / 1000.0f);
  med5[iMed] = phInstantaneo;
  iMed = (iMed + 1) % 5;
  phCrudo = mediana5(med5);
  phFilt  = ALPHA_EMA * phCrudo + (1.0f - ALPHA_EMA) * phFilt;
  st.ph   = phFilt;
}

void actualizarEstabilidad() {
  bufEstab[iEstab] = phFilt;
  iEstab = (iEstab + 1) % N_ESTAB;
  if (nEstab < N_ESTAB) nEstab++;
  if (nEstab < N_ESTAB) return;

  float sx = 0, sy = 0, sxx = 0, sxy = 0, dt = T_ESTAB_MS / 1000.0f;
  for (uint8_t k = 0; k < N_ESTAB; k++) {
    float x = k * dt;
    float y = bufEstab[(iEstab + k) % N_ESTAB];
    sx += x; sy += y; sxx += x * x; sxy += x * y;
  }
  float n = N_ESTAB;
  pendiente = (n * sxy - sx * sy) / (n * sxx - sx * sx);

  float media = sy / n, var = 0;
  for (uint8_t k = 0; k < N_ESTAB; k++) {
    float d = bufEstab[k] - media;
    var += d * d;
  }
  sigma = sqrtf(var / n);
}

bool estable() {
  return nEstab >= N_ESTAB && fabsf(pendiente) < PENDIENTE_MAX && sigma < SIGMA_MAX;
}

// ======================= 14. DIAGNÓSTICO DE HARDWARE (CONTRATO) ======
void evaluarDiagnosticoHardware(bool forzarPublicacion) {
  busI2cOk  = true;
  modXN03Ok = verificarModuloI2C(I2C_XN03);
  modXN13Ok = verificarModuloI2C(I2C_XN13);
  modXN44Ok = verificarModuloI2C(I2C_XN44);

  // Clasificar estado del sensor de pH
  bool phDesconectado = (!i2cPhOk || adcCrudo <= 2.0f || adcCrudo >= 1021.0f ||
                         st.mv < 30.0f || st.mv > 3200.0f);
  bool phFueraRango   = (!phDesconectado && (phFilt < 0.0f || phFilt > 14.0f));
  bool phSinRespuesta = (sinRespuesta >= 3);

  if (phDesconectado || phSinRespuesta) {
    st.sensor = SENSOR_SIN_RESPUESTA;
  } else if (phFueraRango) {
    st.sensor = SENSOR_FUERA_RANGO;
  } else {
    st.sensor = SENSOR_OK;
  }

  // Evaluar si hay fallas críticas activas
  bool nuevaCritica = false;
  String nuevaDescCritica = "";

  if (!busI2cOk) {
    nuevaCritica = true;
    nuevaDescCritica = "Bus I2C bloqueado (XC01)";
  } else if (!modXN13Ok) {
    nuevaCritica = true;
    nuevaDescCritica = "Módulo de relé XN13 no responde (0x0D)";
  } else if (phDesconectado) {
    nuevaCritica = true;
    nuevaDescCritica = "Sensor de pH sin señal o desconectado";
  } else if (phFueraRango) {
    nuevaCritica = true;
    nuevaDescCritica = "Lectura de pH fuera de rango (0-14)";
  } else if (phSinRespuesta) {
    nuevaCritica = true;
    nuevaDescCritica = "Sensor de pH sin respuesta tras dosificar";
  } else if (st.acido_restante_ml < volMinPulso()) {
    nuevaCritica = true;
    nuevaDescCritica = "Ácido agotado para dosificar";
  }

  hayFallaCritica  = nuevaCritica;
  descFallaCritica = nuevaDescCritica;

  // Regla del contrato: si aparece falla crítica, apagar relé, pasar a ERROR y emitir evento
  if (hayFallaCritica) {
    if (estado != ERROR_ST || ultimaFallaCriticaNotificada != descFallaCritica) {
      ultimaFallaCriticaNotificada = descFallaCritica;
      entrarError(descFallaCritica, true);
    }
  } else {
    // Si estábamos en ERROR por una falla que ya se resolvió físicamente
    if (estado == ERROR_ST && ultimaFallaCriticaNotificada.length() > 0) {
      ultimaFallaCriticaNotificada = "";
      estado = IDLE;
      st.estado = ESTADO_IDLE;
      st.error_msg = "";
      Serial.println("[OK] TODO BIEN: Falla resuelta, sistema operando correctamente.");
      forzarPublicacion = true;
    }
  }

  if (forzarPublicacion) {
    publicarHardware();
  }
}

// ======================= 15. PUBLICACIÓN MQTT (CONTRATO) =============
void publicarEvento(const char* tipo, const String& detalle, const String& cmd) {
  JsonDocument d;
  d[K_EV_TS] = millis() / 1000;
  d[K_EV_TIPO] = tipo;
  if (detalle.length()) d[K_EV_DETALLE] = detalle;
  if (cmd.length())     d[K_EV_CMD] = cmd;

  String s;
  serializeJson(d, s);
  // TEMA_EVENTO: QoS 1, retain = false (siempre sin retain según contrato)
  mqtt.publish(TEMA_EVENTO, s.c_str(), 1, false);
}

void publicarTelemetria(bool incluirResumen) {
  st.estado = estadoContratoStr();

  JsonDocument d;
  d[K_TS]                = millis() / 1000;
  d[K_CONECTADO]         = true;
  d[K_NODO]              = AGUA_NODO;
  d[K_UBICACION]         = UBICACION_NODO;
  d[K_PH]                = roundf(st.ph * 100.0f) / 100.0f;
  d[K_MV]                = roundf(st.mv * 10.0f) / 10.0f;
  d[K_SENSOR]            = st.sensor;
  d[K_ESTADO]            = st.estado;
  d[K_ERROR_MSG]         = st.error_msg;
  d[K_BOMBA]             = st.bomba;
  d[K_UMBRAL]            = roundf(st.umbral * 100.0f) / 100.0f;
  d[K_ML_DOSIFICADOS]    = roundf(st.ml_dosificados * 100.0f) / 100.0f;
  d[K_ACIDO_RESTANTE_ML] = roundf(st.acido_restante_ml * 10.0f) / 10.0f;
  d[K_PULSOS]            = st.pulsos;
  d[K_S_HAT]             = roundf(st.s_hat * 10000.0f) / 10000.0f;
  if (isnan(st.error_final)) d[K_ERROR_FINAL] = nullptr;
  else d[K_ERROR_FINAL] = roundf(st.error_final * 1000.0f) / 1000.0f;
  d[K_TEMP_C]            = roundf(st.temp_c * 10.0f) / 10.0f;
  d[K_TEMP_SUPUESTA]     = st.temp_supuesta;
  d[K_HOCL_PCT]          = roundf(1000.0f * fraccionHOCl(st.ph)) / 10.0f;

  JsonObject c = d[K_CALIB].to<JsonObject>();
  c[K_CALIB_OFFSET] = roundf(st.calib_offset * 1000.0f) / 1000.0f;
  c[K_CALIB_FECHA]  = st.calib_fecha;

  if (incluirResumen && tieneResumen) {
    JsonObject r = d[K_RESUMEN].to<JsonObject>();
    r[K_RES_UMBRAL]   = roundf(resUmbral * 100.0f) / 100.0f;
    r[K_RES_PH_FINAL] = roundf(resPhFinal * 100.0f) / 100.0f;
    r[K_RES_ERROR]    = roundf(resError * 1000.0f) / 1000.0f;
    r[K_RES_PULSOS]   = resPulsos;
    r[K_RES_ML]       = roundf(resMl * 100.0f) / 100.0f;
    r[K_RES_SEGUNDOS] = resSegundos;
  }

  String s;
  serializeJson(d, s);
  mqtt.publish(TEMA_TELEMETRIA, s.c_str(), 0, true);
  mqtt.publish(TEMA_PH, String(st.ph, 2).c_str(), 0, false);
  mqtt.publish(TEMA_ESTADO, st.estado, 0, true);
}

void agregarFalla(JsonArray& arr, const char* codigo, const char* sev, const char* mod, const String& det) {
  JsonObject f = arr.add<JsonObject>();
  f[K_FALLA_CODIGO]    = codigo;
  f[K_FALLA_SEVERIDAD] = sev;
  f[K_FALLA_MODULO]    = mod;
  if (det.length()) f[K_FALLA_DETALLE] = det;
}

void publicarHardware() {
  JsonDocument d;
  d[K_HW_RELE]   = st.bomba;
  JsonArray ledArr = d[K_HW_LED].to<JsonArray>();
  ledArr.add(st.led[0]);
  ledArr.add(st.led[1]);
  ledArr.add(st.led[2]);
  d[K_HW_BUZZER] = st.buzzer_sonando ? BUZZER_SONANDO : BUZZER_SILENCIO;
  d[K_HW_SENSOR] = st.sensor;

  JsonObject mods = d[K_HW_MODULOS].to<JsonObject>();
  mods[MOD_XN03] = modXN03Ok;
  mods[MOD_XN13] = modXN13Ok;
  mods[MOD_XN44] = modXN44Ok;

  JsonArray fallas = d[K_HW_FALLAS].to<JsonArray>();

  if (!busI2cOk) {
    agregarFalla(fallas, FALLA_I2C_BUS_ERROR, SEV_CRITICA, MOD_XC01, "Bus I2C sin respuesta");
  }
  if (!modXN13Ok) {
    agregarFalla(fallas, FALLA_RELE_NO_RESPONDE, SEV_CRITICA, MOD_XN13, "Sin ACK I2C en 0x0D");
  }
  if (!modXN44Ok) {
    agregarFalla(fallas, FALLA_BUZZER_NO_RESPONDE, SEV_ADVERTENCIA, MOD_XN44, "Sin ACK I2C en 0x2C");
  }
  if (!modXN03Ok) {
    agregarFalla(fallas, FALLA_LED_NO_RESPONDE, SEV_ADVERTENCIA, MOD_XN03, "Sin ACK I2C en 0x03");
  }

  bool phDesconectado = (!i2cPhOk || adcCrudo <= 2.0f || adcCrudo >= 1021.0f ||
                         st.mv < 30.0f || st.mv > 3200.0f);
  if (phDesconectado) {
    agregarFalla(fallas, FALLA_SENSOR_PH_DESCONECTADO, SEV_CRITICA, MOD_PH, "Lectura AN en 0, saturada o desconectada");
  } else if (phFilt < 0.0f || phFilt > 14.0f) {
    agregarFalla(fallas, FALLA_SENSOR_PH_FUERA_RANGO, SEV_CRITICA, MOD_PH, "pH fuera de rango 0-14");
  }
  if (sinRespuesta >= 3) {
    agregarFalla(fallas, FALLA_SENSOR_PH_SIN_RESPUESTA, SEV_CRITICA, MOD_PH, "Sin cambio de pH tras 3 pulsos");
  }
  if (st.temp_supuesta) {
    agregarFalla(fallas, FALLA_SENSOR_TEMP_DESCONECTADO, SEV_ADVERTENCIA, MOD_TEMP, "Usando temperatura estimada (" + String(st.temp_c, 1) + " °C)");
  }
  if (st.acido_restante_ml < volMinPulso()) {
    agregarFalla(fallas, FALLA_ACIDO_AGOTADO, SEV_CRITICA, "", "Ácido insuficiente para un pulso");
  } else if (st.acido_restante_ml < 20.0f) {
    agregarFalla(fallas, FALLA_ACIDO_BAJO, SEV_ADVERTENCIA, "", "Menos de 20 mL restantes");
  }
  if (!calibrado) {
    agregarFalla(fallas, FALLA_CALIBRACION_PENDIENTE, SEV_ADVERTENCIA, MOD_PH, "Sonda sin calibración de 1 punto");
  }
  if (!apActivo && WiFi.status() == WL_CONNECTED && WiFi.RSSI() < -80) {
    agregarFalla(fallas, FALLA_WIFI_DEBIL, SEV_ADVERTENCIA, MOD_XC01, "RSSI " + String(WiFi.RSSI()) + " dBm");
  }

  String s;
  serializeJson(d, s);
  mqtt.publish(TEMA_HARDWARE, s.c_str(), 0, true);
}

// ======================= 16. ALGORITMO DE CONTROL ADAPTATIVO =========
void iniciarSesion(Modo m, const String& cmdOrigen) {
  if (hayFallaCritica || estado == ERROR_ST) {
    String det = "Falla de hardware: " + (descFallaCritica.length() ? descFallaCritica : st.error_msg);
    if (cmdOrigen.length()) publicarEvento(EV_RECHAZO, det, cmdOrigen);
    msgSerial("Rechazado: " + det);
    return;
  }
  if (strcmp(st.sensor, SENSOR_OK) != 0) {
    if (cmdOrigen.length()) publicarEvento(EV_RECHAZO, MOTIVO_SENSOR, cmdOrigen);
    msgSerial("Rechazado: " + String(MOTIVO_SENSOR));
    return;
  }
  if (estado != IDLE) {
    if (cmdOrigen.length()) publicarEvento(EV_RECHAZO, MOTIVO_OCUPADO, cmdOrigen);
    msgSerial("Rechazado: " + String(MOTIVO_OCUPADO));
    return;
  }
  if (m == MODO_CONTROL && phFilt <= st.umbral + MARGEN_RECHAZO) {
    reproducir(SEC_ERROR);
    if (cmdOrigen.length()) publicarEvento(EV_RECHAZO, MOTIVO_PH_BAJO, cmdOrigen);
    msgSerial("Rechazado: " + String(MOTIVO_PH_BAJO));
    return;
  }
  if (st.acido_restante_ml < volMinPulso()) {
    if (cmdOrigen.length()) publicarEvento(EV_RECHAZO, MOTIVO_SIN_ACIDO, cmdOrigen);
    msgSerial("Rechazado: " + String(MOTIVO_SIN_ACIDO));
    return;
  }

  modo = m;
  st.ml_dosificados = 0.0f;
  st.pulsos = 0;
  st.error_final = NAN;
  sEst = -1.0f;
  st.s_hat = 0.0f;
  sinRespuesta = 0;
  st.inicio_sesion_ms = millis();

  reproducir(SEC_INICIO);
  if (cmdOrigen.length()) {
    publicarEvento(EV_INICIO, "Dosificación iniciada hacia pH " + String(st.umbral, 2), cmdOrigen);
  }
  msgSerial("CONTROL iniciado: pH " + String(phFilt, 2) + " -> umbral " + String(st.umbral, 2));
  pulso(m == MODO_CONTROL ? volMinPulso() : volTitulacion);
}

void finalizarSesion(const String& motivo) {
  bomba(false);
  estado = IDLE;
  st.estado = ESTADO_IDLE;
  reproducir(SEC_FIN);

  uint32_t durSeg = (millis() - st.inicio_sesion_ms) / 1000;
  st.error_final = phFilt - st.umbral;

  // Guardar resumen para publicarlo ANTES del evento FIN (requisito CONTRATO.md)
  tieneResumen = true;
  resUmbral    = st.umbral;
  resPhFinal   = phFilt;
  resError     = st.error_final;
  resPulsos    = st.pulsos;
  resMl        = st.ml_dosificados;
  resSegundos  = durSeg;

  publicarTelemetria(true);
  publicarEvento(EV_FIN, motivo + " (pH final " + String(phFilt, 2) + ")");

  msgSerial("FIN (" + motivo + ") | pH final: " + String(phFilt, 3) +
            " | Pulsos: " + String(st.pulsos) + " | Volumen: " + String(st.ml_dosificados, 2) + " mL");
}

void evaluar(bool porTimeout) {
  float tMezcla = (millis() - tInicioMezcla) / 1000.0f;
  float caida = phAntes - phFilt;
  if (porTimeout) msgSerial("Aviso: tiempo máximo de mezcla alcanzado; evaluando lectura.");

  // Aprendizaje en línea de sensibilidad s = ΔpH / ΔV
  if (caida > SIN_RESPUESTA_PH && ultimoVol > 0) {
    float sMed = caida / ultimoVol;
    sEst = (sEst < 0) ? sMed : 0.5f * sEst + 0.5f * sMed;
    st.s_hat = sEst;
    sinRespuesta = 0;
  } else if (++sinRespuesta >= 3) {
    evaluarDiagnosticoHardware(true);
    return;
  }

  msgSerial("Mezcla " + String(tMezcla, 1) + " s | ΔpH " + String(-caida, 3) +
            " | s≈" + (sEst < 0 ? String("?") : String(sEst, 4) + " pH/mL"));

  if (modo == MODO_TITULACION) {
    if (phFilt <= st.umbral) { finalizarSesion("Titulación llegó al umbral"); return; }
    if (st.ml_dosificados + volTitulacion > volMaxSesion || volTitulacion > st.acido_restante_ml) {
      finalizarSesion("Límite de volumen");
      return;
    }
    pulso(volTitulacion);
    return;
  }

  // Modo control adaptativo (secante amortiguada)
  float err = phFilt - st.umbral;
  if (err <= tolerancia) {
    finalizarSesion("Umbral alcanzado");
    return;
  }

  float vMin = volMinPulso(), vSig;
  if (sEst < 0) {
    vSig = vMin;
  } else {
    if (sEst * vMin > err + tolerancia) {
      finalizarSesion("Objetivo alcanzado dentro de tolerancia mínima");
      return;
    }
    float g = (err < ZONA_APROX) ? gammaCerca : gammaCtl;
    vSig = constrain(g * err / sEst, vMin, volMaxPaso);
  }

  if (st.ml_dosificados + vSig > volMaxSesion) {
    entrarError("Límite máximo de volumen por sesión alcanzado", true);
    return;
  }
  if (vSig > st.acido_restante_ml) {
    // Regla del contrato: si se acaba a mitad de sesión, RECHAZO "Ácido insuficiente" y vuelve a IDLE
    bomba(false);
    estado = IDLE;
    st.estado = ESTADO_IDLE;
    publicarEvento(EV_RECHAZO, MOTIVO_SIN_ACIDO);
    msgSerial("Sesión detenida: " + String(MOTIVO_SIN_ACIDO));
    return;
  }

  pulso(vSig);
}

void actualizarMaquina() {
  uint32_t ahora = millis();

  // Watchdog independiente contra bomba encendida demasiado tiempo
  if (st.bomba && (ahora - tBombaOn > PULSO_MAX_MS + 150)) {
    entrarError("Watchdog: bomba encendida más tiempo del permitido", true);
    return;
  }

  switch (estado) {
    case PULSO:
      if ((int32_t)(ahora - tFinPulso) >= 0) {
        bomba(false);
        if (modo == MODO_MANUAL) {
          estado = IDLE;
          st.estado = ESTADO_IDLE;
          publicarEvento(EV_RELE_OFF, "Pulso manual finalizado", cmdPulsoManual);
          cmdPulsoManual = "";
          msgSerial("Pulso manual terminado.");
        } else {
          estado = MEZCLA;
          st.estado = ESTADO_MEZCLA;
          tInicioMezcla = ahora;
          nEstab = 0;
          publicarEvento(EV_RELE_OFF, "Fin de pulso; iniciando mezcla (" + String(MEZCLA_MS / 1000) + " s)");
        }
      }
      break;

    case MEZCLA:
      if ((ahora - tInicioMezcla >= MEZCLA_MS) && estable()) {
        evaluar(false);
      } else if (ahora - tInicioMezcla >= MEZCLA_MAX_MS) {
        evaluar(true);
      }
      break;

    case RAFAGA:
      if (st.bomba && (int32_t)(ahora - tFinPulso) >= 0) {
        bomba(false);
        rafagaHechos++;
        tProxRafaga = ahora + rafagaGap;
        if (rafagaHechos >= rafagaN) {
          estado = IDLE;
          st.estado = ESTADO_IDLE;
          msgSerial("Ráfaga terminada.");
        }
      } else if (!st.bomba && rafagaHechos < rafagaN && (int32_t)(ahora - tProxRafaga) >= 0) {
        bomba(true);
        tFinPulso = ahora + rafagaMs;
      }
      break;

    default:
      break;
  }
}

// ======================= 17. COMANDOS MQTT (CONTRATO APP) ============
void procesarComandoMqtt(const String& topic, String msg) {
  msg.trim();
  if (!msg.length()) return;

  // 1) Actualización de umbral (agua/nodo1/umbral)
  if (topic == TEMA_UMBRAL) {
    float u = msg.toFloat();
    if (u < UMBRAL_MIN || u > UMBRAL_MAX) {
      publicarEvento(EV_RECHAZO, MOTIVO_UMBRAL_RANGO, "umbral " + msg);
    } else {
      st.umbral = u;
      msgSerial("Umbral actualizado desde app: " + String(st.umbral, 2));
      publicarTelemetria(false);
    }
    return;
  }

  // 2) Órdenes de control y prueba (agua/nodo1/cmd)
  int sp = msg.indexOf(' ');
  String orden = (sp < 0) ? msg : msg.substring(0, sp);
  String arg   = (sp < 0) ? ""  : msg.substring(sp + 1);
  arg.trim();

  if (orden == CMD_DOSIFICAR) {
    iniciarSesion(MODO_CONTROL, msg);

  } else if (orden == CMD_DETENER) {
    detenerTodo("Orden detener desde app", msg);
    publicarEvento(EV_ACK, "Bomba detenida", msg);
    publicarTelemetria(false);
    publicarHardware();

  } else if (orden == CMD_PULSO) {
    if (hayFallaCritica || estado == ERROR_ST) {
      publicarEvento(EV_RECHAZO, "Falla de hardware: " + descFallaCritica, msg);
      return;
    }
    if (strcmp(st.sensor, SENSOR_OK) != 0) {
      publicarEvento(EV_RECHAZO, MOTIVO_SENSOR, msg);
      return;
    }
    if (estado != IDLE) {
      publicarEvento(EV_RECHAZO, MOTIVO_OCUPADO, msg);
      return;
    }
    long ms = arg.toInt();
    if (ms <= 0 || ms > PULSO_MAX_MS) {
      publicarEvento(EV_RECHAZO, MOTIVO_PULSO_MAX, msg);
      return;
    }
    float volEst = volumenParaMs((uint32_t)ms);
    if (st.acido_restante_ml < volEst) {
      publicarEvento(EV_RECHAZO, MOTIVO_SIN_ACIDO, msg);
      return;
    }
    modo = MODO_MANUAL;
    cmdPulsoManual = msg;
    st.acido_restante_ml = max(0.0f, st.acido_restante_ml - volEst);
    bomba(true);
    tFinPulso = millis() + (uint32_t)ms;
    estado = PULSO;
    st.estado = ESTADO_PULSO;
    publicarEvento(EV_RELE_ON, "Pulso manual de " + String(ms) + " ms", msg);

  } else if (orden == CMD_CALIBRAR) {
    float phRef = arg.toFloat();
    if (phRef <= 0.0f || phRef >= 14.0f) {
      publicarEvento(EV_RECHAZO, "Valor de calibración inválido", msg);
      return;
    }
    offsetPH += (phRef - phFilt);
    phFilt = phRef;
    st.ph = phFilt;
    st.calib_offset = offsetPH;
    st.calib_fecha = "t+" + String(millis() / 1000) + "s";
    calibrado = true;
    publicarEvento(EV_ACK, "Calibrado con pH " + String(phRef, 2), msg);
    publicarTelemetria(false);
    publicarHardware();

  } else if (orden == CMD_ACIDO) {
    float nuevoAcido = arg.toFloat();
    if (nuevoAcido < 0.0f) {
      publicarEvento(EV_RECHAZO, "Volumen de ácido inválido", msg);
      return;
    }
    st.acido_restante_ml = nuevoAcido;
    evaluarDiagnosticoHardware(true);
    publicarEvento(EV_ACK, "Ácido: " + String((int)roundf(st.acido_restante_ml)) + " mL", msg);
    publicarTelemetria(false);

  } else if (orden == CMD_TEST_BUZZER) {
    if (arg == "inicio") {
      reproducir(SEC_INICIO);
    } else if (arg == "fin") {
      reproducir(SEC_FIN);
    } else if (arg == "error") {
      reproducir(SEC_ERROR);
    } else {
      publicarEvento(EV_RECHAZO, "Secuencia de buzzer desconocida", msg);
      return;
    }
    publicarHardware();
    publicarEvento(EV_BUZZER, arg, msg);

  } else if (orden == CMD_TEST_LED) {
    int s1 = arg.indexOf(' ');
    int s2 = (s1 > 0) ? arg.indexOf(' ', s1 + 1) : -1;
    if (s1 < 0 || s2 < 0) {
      publicarEvento(EV_RECHAZO, "Formato esperado: test_led r g b", msg);
      return;
    }
    uint8_t r = constrain(arg.substring(0, s1).toInt(), 0, 255);
    uint8_t g = constrain(arg.substring(s1 + 1, s2).toInt(), 0, 255);
    uint8_t b = constrain(arg.substring(s2 + 1).toInt(), 0, 255);
    tLedTestHasta = millis() + 5000;
    aplicarColorLED(r, g, b, true);
    publicarHardware();
    publicarEvento(EV_LED, String(r) + " " + String(g) + " " + String(b), msg);

  } else {
    publicarEvento(EV_RECHAZO, MOTIVO_DESCONOCIDA, msg);
  }
}

// ======================= 18. ENDPOINTS HTTP (PUERTO 80) ==============
void handleDatos() {
  JsonDocument doc;
  doc["temperatura"]       = roundf(st.temp_c * 10.0f) / 10.0f;
  doc["temp_c"]            = roundf(st.temp_c * 10.0f) / 10.0f;
  doc["temp_supuesta"]     = st.temp_supuesta;
  doc["ph"]                = roundf(st.ph * 100.0f) / 100.0f;
  doc["mv"]                = roundf(st.mv * 10.0f) / 10.0f;
  doc["sensor"]            = st.sensor;
  doc["estado"]            = estadoContratoStr();
  doc["bomba"]             = st.bomba;
  doc["umbral"]            = st.umbral;
  doc["acido_restante_ml"] = st.acido_restante_ml;
  doc["error_msg"]         = st.error_msg;
  doc["uptime"]            = millis() / 1000;

  String json;
  serializeJson(doc, json);
  httpServer.send(200, "application/json", json);
}

void handleLed() {
  if (httpServer.hasArg("estado")) {
    tLedTestHasta = millis() + 5000;
    if (httpServer.arg("estado").toInt() == 1) {
      aplicarColorLED(0, 255, 0, true);
    } else {
      aplicarColorLED(0, 0, 0, true);
    }
    publicarHardware();
    httpServer.send(200, "text/plain", "OK");
  } else {
    httpServer.send(400, "text/plain", "Falta parametro");
  }
}

// ======================= 19. COMANDOS RÁPIDOS POR SERIAL =============
void procesarComandoSerial(String l) {
  l.trim();
  if (!l.length()) return;
  char c = l.charAt(0);
  String resto = l.substring(1);
  resto.trim();
  float a1 = resto.toFloat();

  switch (c) {
    case 'd': iniciarSesion(MODO_CONTROL); break;
    case 'x': detenerTodo("Monitor Serie"); break;
    case 'u':
      if (a1 >= UMBRAL_MIN && a1 <= UMBRAL_MAX) {
        st.umbral = a1;
        msgSerial("Umbral = " + String(st.umbral, 2));
      } else {
        msgSerial("El umbral debe estar entre 4.5 y 7.0");
      }
      break;
    case 'c':
      if (a1 > 0 && a1 < 14) {
        offsetPH += (a1 - phFilt);
        phFilt = a1;
        st.ph = phFilt;
        st.calib_offset = offsetPH;
        st.calib_fecha = "t+" + String(millis() / 1000) + "s";
        calibrado = true;
        msgSerial("Calibrado a pH " + String(a1, 2) + " | Offset = " + String(offsetPH, 3));
      }
      break;
    case 'a':
      if (a1 >= 0) {
        st.acido_restante_ml = a1;
        msgSerial("Ácido restante = " + String(st.acido_restante_ml, 1) + " mL");
      }
      break;
    case 'e':
      if (a1 > 0 && a1 < 60) {
        st.temp_c = a1;
        msgSerial("Temperatura compensación = " + String(st.temp_c, 1) + " °C");
      }
      break;
    case 'i':
      Serial.println("--- DIAGNÓSTICO DEL SISTEMA ---");
      Serial.println("pH: " + String(st.ph, 3) + " | Voltaje: " + String(st.mv, 1) + " mV (ADC: " + String(adcCrudo, 1) + ")");
      Serial.println("Temp: " + String(st.temp_c, 1) + " °C | Umbral: " + String(st.umbral, 2) + " | Estado: " + String(estadoContratoStr()));
      Serial.println("Módulos I2C -> XN03: " + String(modXN03Ok ? "OK" : "FALLA") +
                     " | XN13: " + String(modXN13Ok ? "OK" : "FALLA") +
                     " | XN44: " + String(modXN44Ok ? "OK" : "FALLA"));
      break;
    default:
      msgSerial("Comandos: d (dosificar), x (detener), u <pH>, c <pH>, a <mL>, e <°C>, i (info)");
      break;
  }
}

// ======================= 20. BLYNK.CLOUD =============================
// Datastreams del template AguaHack:
//   V0  pH                 (ESP -> Blynk)   Double 0-14
//   V1  Umbral             (Blynk <-> ESP)  Double 4.5-7.0
//   V2  Dosificar          (Blynk <-> ESP)  Integer 0/1
//   V3  Estado             (ESP -> Blynk)   String
//   V4  HOCl %             (ESP -> Blynk)   Double 0-100
//   V5  Ácido restante mL  (ESP -> Blynk)   Double 0-100
//   V11 Latido             (ESP -> Blynk)   Integer 0-255 (widget LED)
// Para no gastar la cuota de mensajes de Blynk, cada dato se envía solo
// cuando cambia (revisión cada 1 s) y el latido cada 5 s.
#if USE_BLYNK
uint32_t tBlynkConexion = 0;   // momento de la última conexión a Blynk

BLYNK_CONNECTED() {
  tBlynkConexion = millis();
  msgSerial("Blynk conectado");
  Blynk.syncVirtual(V1);       // trae el último umbral elegido en el slider
}

// Slider de umbral (4.5 - 7.0)
BLYNK_WRITE(V1) {
  float u = param.asFloat();
  if (u >= UMBRAL_MIN && u <= UMBRAL_MAX) {
    st.umbral = u;
    msgSerial("Umbral desde Blynk: " + String(st.umbral, 2));
  } else {
    msgSerial("Umbral de Blynk fuera de rango (4.5-7.0); se ignora");
    Blynk.virtualWrite(V1, st.umbral);   // regresa el slider al valor válido
  }
}

// Switch de dosificar: 1 = iniciar dosificación inteligente, 0 = detener
BLYNK_WRITE(V2) {
  if (param.asInt() == 1) {
    // Seguridad: un "1" que llega justo al reconectar no arranca la bomba
    if (millis() - tBlynkConexion < 3000) {
      msgSerial("Blynk: orden de dosificar al reconectar ignorada por seguridad");
      Blynk.virtualWrite(V2, 0);
      return;
    }
    iniciarSesion(MODO_CONTROL, String(CMD_DOSIFICAR));
    // Si fue rechazada (pH ya bajo, falla, sin ácido), el switch regresa a 0
    if (estado == IDLE || estado == ERROR_ST) Blynk.virtualWrite(V2, 0);
  } else {
    detenerTodo("Detenido desde Blynk", String(CMD_DETENER));
  }
}

// Texto amigable del estado para el widget Label (V3)
String textoEstadoBlynk() {
  if (hayFallaCritica || estado == ERROR_ST) {
    return "ERROR: " + (descFallaCritica.length() ? descFallaCritica : st.error_msg);
  }
  switch (estado) {
    case PULSO:
    case RAFAGA: return "Dosificando";
    case AGITA:
    case MEZCLA: return "Mezclando";
    default:     return "En espera";
  }
}

void enviarBlynk() {
  static uint32_t tRevision = 0;
  static uint32_t tLatido   = 0;
  static bool     latido    = false;
  static float    phEnv     = -100.0f;
  static float    umbralEnv = -100.0f;
  static float    acidoEnv  = -100.0f;
  static int      v2Env     = -1;
  static String   v3Env     = "";

  if (!Blynk.connected()) {
    // Al reconectar se vuelve a mandar todo
    phEnv = umbralEnv = acidoEnv = -100.0f;
    v2Env = -1;
    v3Env = "";
    return;
  }

  uint32_t ahora = millis();
  if (ahora - tRevision < 1000) return;
  tRevision = ahora;

  if (fabsf(phFilt - phEnv) >= 0.02f) {
    phEnv = phFilt;
    Blynk.virtualWrite(V0, roundf(phFilt * 100.0f) / 100.0f);
    Blynk.virtualWrite(V4, roundf(1000.0f * fraccionHOCl(phFilt)) / 10.0f);
  }
  // Si el umbral cambió desde la app o el Serial, se refleja en el slider.
  // Se espera 2 s tras conectar para no pisar el valor guardado en Blynk.
  if (ahora - tBlynkConexion > 2000 && fabsf(st.umbral - umbralEnv) >= 0.005f) {
    umbralEnv = st.umbral;
    Blynk.virtualWrite(V1, roundf(st.umbral * 100.0f) / 100.0f);
  }
  int v2 = (estado == IDLE || estado == ERROR_ST) ? 0 : 1;
  if (v2 != v2Env) {
    v2Env = v2;
    Blynk.virtualWrite(V2, v2);
  }
  String v3 = textoEstadoBlynk();
  if (v3 != v3Env) {
    v3Env = v3;
    Blynk.virtualWrite(V3, v3);
  }
  if (fabsf(st.acido_restante_ml - acidoEnv) >= 0.1f) {
    acidoEnv = st.acido_restante_ml;
    Blynk.virtualWrite(V5, roundf(st.acido_restante_ml * 10.0f) / 10.0f);
  }
  if (ahora - tLatido >= 5000) {
    tLatido = ahora;
    latido = !latido;
    Blynk.virtualWrite(V11, latido ? 255 : 0);
  }
}
#endif

// ======================= 21. SETUP Y LOOP ============================
void setup() {
  Serial.begin(115200);
  delay(800);

  // Inicializar I2C en pines oficiales XC01-R5 (SDA=12, SCL=13)
  Wire.setPins(PIN_SDA, PIN_SCL);
  Wire.begin();

 // Solo inicializa la pantalla si responde en 0x3C. Sin pantalla conectada,
 // display.begin() manda decenas de escrituras fallidas y llena el monitor
 // serie de "i2cWrite(): ... ESP_ERR_INVALID_STATE".
 Wire.beginTransmission(0x3C);
 bool hayPantalla = (Wire.endTransmission() == 0);
 if (!hayPantalla) Serial.println("[I2C] Pantalla SH1106 (0x3C) no detectada; se omite.");
 if (hayPantalla && display.begin(0x3C, true)) {
  pantallaOk = true;
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SH110X_WHITE);
  display.setCursor(0, 0);
  display.println("Iniciando sistema...");
  display.display();
}

  // Escaneo del bus I2C: muestra qué módulos responden (diagnóstico rápido)
  Serial.print("[I2C] Dispositivos encontrados:");
  uint8_t nI2c = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf(" 0x%02X", a);
      nI2c++;
    }
  }
  Serial.println(nI2c ? "" : " ninguno (revisa cables Qwiic y la fuente de 12 V)");
  Serial.println("[I2C] Esperados: 0x03 XN03, 0x0D XN13, 0x2C XN44, 0x3C pantalla");

  // Estado seguro inicial de actuadores
  bomba(false);
  noToneXN44();
  aplicarColorLED(0, 0, 0, true);

  // Precargar filtro de pH con lecturas reales
  for (int i = 0; i < 10; i++) {
    muestrear();
    delay(20);
  }
  phFilt = phCrudo;
  st.ph  = phFilt;

  // Conexión Wi-Fi (STA o AP)
  IPAddress ipLocal;
  if (MODO_AP) {
    WiFi.mode(WIFI_AP);
    WiFi.softAP(AP_SSID, AP_PASS);
    ipLocal = WiFi.softAPIP();
    Serial.print("IP del AP: ");
    Serial.println(ipLocal);
  } else {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.print("Conectando a WiFi");
    uint32_t tInicioWifi = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - tInicioWifi < 20000) {
      delay(500);
      Serial.print(".");
    }
    if (WiFi.status() == WL_CONNECTED) {
      ipLocal = WiFi.localIP();
      Serial.print("\nIP asignada (poner en Flutter): ");
      Serial.println(ipLocal);
    } else {
      // Sin red tras 20 s: RESPALDO. El ESP32 abre su propia red WiFi con el
      // broker WebSocket, para que la app se conecte sin router ni internet.
      // (Se queda así hasta reiniciar: cambiar de red con clientes conectados
      //  los desconectaría a mitad de una sesión.)
      WiFi.disconnect(true);
      delay(100);
      WiFi.mode(WIFI_AP);
      WiFi.softAP(AP_SSID, AP_PASS);
      apActivo = true;
      ipLocal  = WiFi.softAPIP();
      Serial.println("\n[AVISO] Sin WiFi tras 20 s. Red propia activada.");
      Serial.println("  Conecta el teléfono a la red \"" + String(AP_SSID) + "\" (clave " +
                     String(AP_PASS) + ")");
      Serial.println("  App: host " + ipLocal.toString() + ", puerto " + String(MQTT_WS_PUERTO) +
                     ", ruta /");
    }
  }

  // Levantar servidor HTTP en puerto 80
  httpServer.on("/datos", handleDatos);
  httpServer.on("/led", handleLed);
  httpServer.begin();

  // Levantar Broker MQTT sobre WebSocket en puerto 81
  mqtt.subscribe(TEMA_CMD, [](const char* topic, const char* payload) {
    procesarComandoMqtt(String(TEMA_CMD), String(payload));
  });
  mqtt.subscribe(TEMA_UMBRAL, [](const char* topic, const char* payload) {
    procesarComandoMqtt(String(TEMA_UMBRAL), String(payload));
  });
  mqtt.begin();

#if USE_BLYNK
  // Blynk solo aplica en modo STA (en modo AP no hay internet)
  if (!apActivo) {
    Blynk.config(BLYNK_AUTH_TOKEN);
    if (WiFi.status() == WL_CONNECTED) {
      Blynk.connect(5000);   // espera máximo 5 s; si no, reintenta en loop()
    }
  }
#endif

  Serial.println("Servidor HTTP listo en: http://" + ipLocal.toString() + "/datos");
  Serial.println("Broker MQTT WS listo en: ws://" + ipLocal.toString() + ":" + String(MQTT_WS_PUERTO) + "/");

  // Evaluación inicial del hardware y publicación inicial
  evaluarDiagnosticoHardware(true);
  actualizarLED(phFilt);
  publicarTelemetria(false);
}

void loop() {
  static uint32_t tMuestreo   = 0;
  static uint32_t tEstab      = 0;
  static uint32_t tTelemetria = 0;
  static uint32_t tHardware   = 0;
  static uint32_t tConsola    = 0;
  static String   lineaSerial = "";

  uint32_t ahora = millis();

  // Atender clientes HTTP y Broker MQTT WebSocket
  httpServer.handleClient();
  mqtt.loop();

#if USE_BLYNK
  // Con la bomba encendida no se atiende Blynk: una reconexión lenta
  // nunca debe alargar un pulso (el pulso dura máximo 1.5 s).
  if (!apActivo && WiFi.status() == WL_CONNECTED && !st.bomba) {
    Blynk.run();
  }
  enviarBlynk();
#endif

  // 1) Muestreo de pH y LED cada 50 ms
  if (ahora - tMuestreo >= T_MUESTREO_MS) {
    tMuestreo = ahora;
    muestrear();
    actualizarLED(phFilt);
  }

  // 2) Ventana de estabilidad cada 250 ms
  if (ahora - tEstab >= T_ESTAB_MS) {
    tEstab = ahora;
    actualizarEstabilidad();
  }

  // 3) Publicación de pH + Telemetría cada 1000 ms (requisito CONTRATO.md)
  if (ahora - tTelemetria >= PERIODO_TELEMETRIA_MS) {
    tTelemetria = ahora;
    evaluarDiagnosticoHardware(false);
    publicarTelemetria(false);
  }

  // 4) Publicación de estado de hardware y fallas cada 2000 ms
  if (ahora - tHardware >= PERIODO_HARDWARE_MS) {
    tHardware = ahora;
    publicarHardware();
  }

  // 5) Reporte claro de estado en Monitor Serie cada 3000 ms
  if (ahora - tConsola >= 3000) {
    tConsola = ahora;
    if (hayFallaCritica || estado == ERROR_ST) {
      Serial.println("[ALERTA] ERROR EN EL SISTEMA, checar en la aplicacion -> " + descFallaCritica);
    } else {
      Serial.println("[OK] TODO BIEN: Variables funcionando correctamente | pH: " +
                     String(st.ph, 2) + " (" + String(st.mv, 0) + " mV) | Temp: " +
                     String(st.temp_c, 1) + " °C | Estado: " + String(estadoContratoStr()));
    }

    if (pantallaOk) {
  display.clearDisplay();
  display.setCursor(0, 0);
  if (hayFallaCritica || estado == ERROR_ST) {
    display.setTextSize(1);
    display.println("ERROR EN EL SISTEMA");
    display.println("Checar en la app:");
    display.println(descFallaCritica);
  } else {
    display.setTextSize(1);
    display.println("TODO BIEN");
    display.println("pH: " + String(st.ph, 2));
    display.println("Temp: " + String(st.temp_c, 1) + " C");
    if (apActivo) {
      display.println("Red: " + String(AP_SSID));
      display.println("IP: " + WiFi.softAPIP().toString());
    }
    else if (WiFi.status() == WL_CONNECTED)  display.println("IP: " + WiFi.localIP().toString());
    else                                     display.println("Sin WiFi");
  }
    display.display();
  }

  }

  // 6) Comandos opcionales por Monitor Serie
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') {
      procesarComandoSerial(lineaSerial);
      lineaSerial = "";
    } else {
      lineaSerial += ch;
    }
  }

  actualizarMaquina();
  actualizarBuzzer();
}
