// ============================================================================
//  agua_contrato.h — Contrato entre el firmware (ESP32-S3 / XC01) y la app.
//
//  Copia este archivo junto a tu .ino e inclúyelo:   #include "agua_contrato.h"
//  TODOS los nombres de temas, comandos, estados y campos JSON salen de aquí.
//  Si cambias algo, avisa al equipo de la app: deben coincidir con
//  app/lib/core/device_constants.dart y app/lib/data/models.dart.
// ============================================================================
#pragma once
#include <Arduino.h>

// ---------------------------------------------------------------------------
// 1. Nodo y temas MQTT   (tema completo = "agua/" + NODO + "/" + sufijo)
// ---------------------------------------------------------------------------
#define AGUA_NODO            "nodo1"

#define TEMA_PH              "agua/" AGUA_NODO "/ph"          // ESP→app  número "6.84"
#define TEMA_ESTADO          "agua/" AGUA_NODO "/estado"      // ESP→app  "IDLE"|"PULSO"|"MEZCLA"|"ERROR"
#define TEMA_TELEMETRIA      "agua/" AGUA_NODO "/telemetria"  // ESP→app  JSON (sección 4)
#define TEMA_EVENTO          "agua/" AGUA_NODO "/evento"      // ESP→app  JSON (sección 5)
#define TEMA_HARDWARE        "agua/" AGUA_NODO "/hardware"    // ESP→app  JSON (sección 6)
#define TEMA_UMBRAL          "agua/" AGUA_NODO "/umbral"      // app→ESP  número "6.60"
#define TEMA_CMD             "agua/" AGUA_NODO "/cmd"         // app→ESP  texto (sección 3)

// ---------------------------------------------------------------------------
// 2. Estados del controlador (tema estado y campo "estado")
// ---------------------------------------------------------------------------
#define ESTADO_IDLE          "IDLE"
#define ESTADO_PULSO         "PULSO"
#define ESTADO_MEZCLA        "MEZCLA"
#define ESTADO_ERROR         "ERROR"

// Estado de la sonda (campo "sensor")
#define SENSOR_OK            "OK"
#define SENSOR_FUERA_RANGO   "FUERA_RANGO"
#define SENSOR_SIN_RESPUESTA "SIN_RESPUESTA"

// ---------------------------------------------------------------------------
// 3. Comandos que llegan por TEMA_CMD (texto plano, separados por espacio)
// ---------------------------------------------------------------------------
#define CMD_DOSIFICAR        "dosificar"     // inicia la dosificación hasta el umbral
#define CMD_DETENER          "detener"       // paro inmediato + limpia el error
#define CMD_PULSO            "p"             // "p <ms>"   pulso manual (máx. PULSO_MAX_MS)
#define CMD_CALIBRAR         "c"             // "c <pH>"   calibración con solución conocida
#define CMD_ACIDO            "a"             // "a 100"    reinicia inventario de ácido (mL)
#define CMD_TEST_BUZZER      "test_buzzer"   // "test_buzzer inicio|fin|error"
#define CMD_TEST_LED         "test_led"      // "test_led <r> <g> <b>"  (0–255)

// ---------------------------------------------------------------------------
// 4. Campos JSON de TEMA_TELEMETRIA
//    Obligatorios: ts y ph. Los demás son opcionales (la app muestra "—").
// ---------------------------------------------------------------------------
#define K_TS                 "ts"                 // int    epoch en segundos (o uptime si no hay NTP)
#define K_CONECTADO          "conectado"          // bool
#define K_NODO               "nodo"               // string "nodo1"
#define K_UBICACION          "ubicacion"          // string "Mesa 4"
#define K_PH                 "ph"                 // float  pH filtrado, 2 decimales
#define K_MV                 "mv"                 // float  lectura cruda en mV
#define K_SENSOR             "sensor"             // string SENSOR_*
#define K_ESTADO             "estado"             // string ESTADO_*
#define K_ERROR_MSG          "error_msg"          // string motivo del error
#define K_BOMBA              "bomba"              // bool   relé encendido
#define K_UMBRAL             "umbral"             // float  umbral activo
#define K_ML_DOSIFICADOS     "ml_dosificados"     // float  mL en la sesión actual
#define K_ACIDO_RESTANTE_ML  "acido_restante_ml"  // float  inventario
#define K_PULSOS             "pulsos"             // int    pulsos en la sesión
#define K_S_HAT              "s_hat"              // float  pH que baja por mL (estimado)
#define K_ERROR_FINAL        "error_final"        // float  pH final − umbral (null si no aplica)
#define K_TEMP_C             "temp_c"             // float  temperatura del agua
#define K_TEMP_SUPUESTA      "temp_supuesta"      // bool   true si no hay sensor de temperatura
#define K_HOCL_PCT           "hocl_pct"           // float  % HOCl (opcional: la app lo calcula)
#define K_CALIB              "calib"              // objeto { offset, fecha }
#define K_CALIB_OFFSET       "offset"             //   float
#define K_CALIB_FECHA        "fecha"              //   string "2026-11-19T10:20"
#define K_RESUMEN            "resumen"            // objeto, solo al terminar una sesión
#define K_RES_UMBRAL         "umbral"             //   float
#define K_RES_PH_FINAL       "ph_final"           //   float
#define K_RES_ERROR          "error"              //   float
#define K_RES_PULSOS         "pulsos"             //   int
#define K_RES_ML             "ml"                 //   float
#define K_RES_SEGUNDOS       "segundos"           //   int

// ---------------------------------------------------------------------------
// 5. TEMA_EVENTO  {"ts":..., "tipo":"...", "detalle":"...", "cmd":"..."}
//    "cmd" = la orden original (p. ej. "p 100"). INCLÚYELO SIEMPRE que el
//    evento responda a una orden: así la app quita su "Enviando…".
// ---------------------------------------------------------------------------
#define K_EV_TS              "ts"
#define K_EV_TIPO            "tipo"
#define K_EV_DETALLE         "detalle"
#define K_EV_CMD             "cmd"

#define EV_INICIO            "INICIO"     // arrancó la dosificación
#define EV_FIN               "FIN"        // llegó al umbral (publica antes la telemetría con "resumen")
#define EV_RECHAZO           "RECHAZO"    // orden rechazada; "detalle" = motivo
#define EV_ERROR             "ERROR"      // falla; "detalle" = motivo
#define EV_RELE_ON           "RELE_ON"
#define EV_RELE_OFF          "RELE_OFF"
#define EV_BUZZER            "BUZZER"     // "detalle" = inicio|fin|error
#define EV_LED               "LED"        // "detalle" = "r g b"
#define EV_ACK               "ACK"        // orden aceptada (detener, c, a, …)

// Motivos de rechazo (texto exacto que muestra la app)
#define MOTIVO_PH_BAJO       "El pH ya está por debajo del objetivo"
#define MOTIVO_SIN_ACIDO     "Ácido insuficiente"
#define MOTIVO_PULSO_MAX     "Pulso mayor al máximo permitido (1500 ms)"
#define MOTIVO_OCUPADO       "Ya hay una dosificación en curso"
#define MOTIVO_SENSOR        "Sensor sin respuesta"
#define MOTIVO_UMBRAL_RANGO  "Umbral fuera de rango (4.5–7.0)"
#define MOTIVO_DESCONOCIDA   "Orden desconocida"

// ---------------------------------------------------------------------------
// 6. TEMA_HARDWARE
//    {"rele":false, "led":[0,255,0], "buzzer":"silencio", "sensor":"OK",
//     "modulos":{"XN03":true,"XN13":true,"XN44":true}}
// ---------------------------------------------------------------------------
#define K_HW_RELE            "rele"       // bool
#define K_HW_LED             "led"        // array [r, g, b]
#define K_HW_BUZZER          "buzzer"     // "silencio" | "sonando"
#define K_HW_SENSOR          "sensor"     // SENSOR_*
#define K_HW_MODULOS         "modulos"    // objeto { "XN03": bool, "XN13": bool, "XN44": bool }
#define BUZZER_SILENCIO      "silencio"
#define BUZZER_SONANDO       "sonando"
#define MOD_XN03             "XN03"
#define MOD_XN13             "XN13"
#define MOD_XN44             "XN44"

// ---------------------------------------------------------------------------
// 7. Límites de seguridad (los aplica el FIRMWARE; la app solo los muestra)
// ---------------------------------------------------------------------------
constexpr float    UMBRAL_MIN          = 4.5f;
constexpr float    UMBRAL_MAX          = 7.0f;
constexpr float    MARGEN_RECHAZO      = 0.05f;   // dosificar con pH <= umbral + esto → RECHAZO
constexpr float    TOLERANCIA_FIN      = 0.03f;   // FIN cuando pH <= umbral + esto
constexpr uint16_t PULSO_MAX_MS        = 1500;
constexpr float    ML_POR_SEGUNDO      = 33.0f;   // caudal de la bomba
constexpr float    ACIDO_INICIAL_ML    = 100.0f;
constexpr uint16_t MEZCLA_MS           = 3000;

// Frecuencia de publicación sugerida
constexpr uint16_t PERIODO_TELEMETRIA_MS = 1000;  // ph + telemetria
constexpr uint16_t PERIODO_HARDWARE_MS   = 2000;  // y también en cada cambio
// La app marca "Sin datos recientes" si pasan más de 10 s sin lecturas.

// ---------------------------------------------------------------------------
// 8. Tonos del buzzer (Hz, ms) — los mismos que reproduce la app
// ---------------------------------------------------------------------------
// inicio: 880 → 1320          fin: 1320 → 1100 → 880          error: 400 ×3
// Pausa entre tonos: 60 ms. Duración de cada tono: 150 ms.

// ---------------------------------------------------------------------------
// 9. Hardware (referencia; la app NO lo usa)
// ---------------------------------------------------------------------------
constexpr uint8_t PIN_SDA        = 12;
constexpr uint8_t PIN_SCL        = 13;
constexpr uint8_t PIN_PH_AN      = 4;    // entrada analógica de la sonda
constexpr uint8_t PIN_LED_XC01   = 16;
constexpr uint8_t I2C_XN03       = 0x03; // E/S analógicas: pot 0x10, LED RGB 0x01 + R,G,B,intensidad
constexpr uint8_t I2C_XN13       = 0x0D; // relé: reg 0x01 → 0x01 ON / 0x00 OFF
constexpr uint8_t I2C_XN44       = 0x2C; // buzzer: reg 0x01 → freq(16b) + ms(16b), MSB primero
constexpr uint8_t REG_XN03_LED   = 0x01;
constexpr uint8_t REG_XN03_POT   = 0x10;
constexpr uint8_t REG_XN13_RELE  = 0x01;
constexpr uint8_t REG_XN44_TONE  = 0x01;

// ---------------------------------------------------------------------------
// 10. Variables de estado sugeridas (mismos nombres que el JSON)
// ---------------------------------------------------------------------------
struct EstadoNodo {
  // lectura
  float    ph              = 7.0f;
  float    mv              = 0.0f;
  const char* sensor       = SENSOR_OK;
  float    temp_c          = 22.0f;
  bool     temp_supuesta   = true;
  // control
  const char* estado       = ESTADO_IDLE;
  String   error_msg       = "";
  bool     bomba           = false;   // = relé
  float    umbral          = 6.60f;
  // sesión
  float    ml_dosificados  = 0.0f;
  float    acido_restante_ml = ACIDO_INICIAL_ML;
  uint16_t pulsos          = 0;
  float    s_hat           = 0.0f;
  float    error_final     = NAN;     // NAN → publicar null
  uint32_t inicio_sesion_ms = 0;
  // calibración
  float    calib_offset    = 0.0f;
  String   calib_fecha     = "";
  // salidas
  uint8_t  led[3]          = {0, 255, 0};
  bool     buzzer_sonando  = false;
};
