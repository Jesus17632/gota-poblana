# Contrato firmware ↔ app (para el encargado del firmware)

Todo lo que necesitas para que la app funcione con el ESP32-S3 (XC01).
Los nombres están en **`agua_contrato.h`**: cópialo junto a tu `.ino` y usa sus
constantes en lugar de escribir los textos a mano. La app ya está programada
con estos nombres; si cambias uno, deja de funcionar.

## La regla

- **El firmware decide y protege**: mide pH, filtra, dosifica, maneja relé, buzzer y LED, y aplica los límites.
- **La app solo envía órdenes y muestra lo que publicas.** No supone nada: muestra "Enviando…" hasta recibir tu evento y, si no llega en 3 s, "Sin respuesta del dispositivo".
- **Toda orden se responde con un evento** (`ACK`, `RECHAZO`, `INICIO`, `RELE_ON`, …) que incluya `"cmd"` con la orden original.

## Conexión

- Librería sugerida: **PubSubClient** (MQTT por TCP) + **ArduinoJson**.
- El ESP32 se conecta al broker por **TCP (puerto 1883)**. La app se conecta al **mismo broker** por **WebSocket**. El broker reenvía entre ambos; no necesitas WebSocket en el ESP32.
- Usa `client.setBufferSize(1024)`: la telemetría pasa de los 256 bytes por defecto.
- Suscríbete a `TEMA_CMD` y `TEMA_UMBRAL`.

| Tema | Dirección | Formato | QoS | retain |
|---|---|---|---|---|
| `agua/nodo1/ph` | ESP → app | texto `"6.84"` | 0 | no |
| `agua/nodo1/estado` | ESP → app | texto `"IDLE"` | 0 | sí |
| `agua/nodo1/telemetria` | ESP → app | JSON | 0 | sí |
| `agua/nodo1/evento` | ESP → app | JSON | 1 | **NO** (si es retenido, la app repite la alerta al reconectar) |
| `agua/nodo1/hardware` | ESP → app | JSON | 0 | sí |
| `agua/nodo1/umbral` | app → ESP | texto `"6.60"` | 1 | — |
| `agua/nodo1/cmd` | app → ESP | texto | 1 | — |

Publica `ph` y `telemetria` cada **1 s**, `hardware` cada 2 s y en cada cambio, y `evento` en el momento en que ocurre algo.
Si pasan más de 10 s sin lecturas, la app muestra "Sin datos recientes".

## Órdenes que recibes y qué debes responder

| Orden (`TEMA_CMD`) | Condición | Respuesta (`TEMA_EVENTO`) |
|---|---|---|
| `dosificar` | sensor ≠ OK | `RECHAZO` "Sensor sin respuesta" |
| | ya dosificando | `RECHAZO` "Ya hay una dosificación en curso" |
| | pH ≤ umbral + 0.05 | `RECHAZO` "El pH ya está por debajo del objetivo" |
| | ácido insuficiente | `RECHAZO` "Ácido insuficiente" |
| | válida | `INICIO`, luego ciclos (ver abajo), al final `FIN` |
| `detener` | siempre | `RELE_OFF` (si estaba encendido) + estado `IDLE` + limpia error + `ACK` |
| `p <ms>` | ms > 1500 | `RECHAZO` "Pulso mayor al máximo permitido (1500 ms)" |
| | válida | `RELE_ON`, a los `<ms>` → `RELE_OFF` |
| `c <pH>` | — | `ACK` "Calibrado con pH 7.00" |
| `a 100` | — | `ACK` "Ácido: 100 mL" |
| `test_buzzer inicio\|fin\|error` | — | `BUZZER` con `detalle` = la secuencia |
| `test_led r g b` | — | `LED` con `detalle` = `"r g b"` |
| otra | — | `RECHAZO` "Orden desconocida" |
| `TEMA_UMBRAL` "x.xx" | fuera de 4.5–7.0 | `RECHAZO` "Umbral fuera de rango (4.5–7.0)" con `"cmd":"umbral x.xx"` |
| | válido | actualiza `umbral` (sin evento) |

**Ciclo de dosificación:** `RELE_ON` → pulso → `RELE_OFF` → estado `MEZCLA` (~3 s) → nueva lectura → repite.
Cuando pH ≤ umbral + 0.03, publica **primero la telemetría con `resumen`** y después el evento `FIN`.
El ácido se descuenta a ~33 mL por segundo de bomba. Si se acaba a mitad de la sesión: `RECHAZO` "Ácido insuficiente" y vuelve a `IDLE`.
Si falla la sonda: relé apagado, estado `ERROR`, `sensor: "SIN_RESPUESTA"` y evento `ERROR`.

## Ejemplos exactos

**telemetria** (obligatorios `ts` y `ph`; lo demás es opcional):
```json
{"ts":1763571240,"conectado":true,"nodo":"nodo1","ubicacion":"Mesa 4",
 "ph":6.84,"mv":1784,"sensor":"OK","estado":"MEZCLA","error_msg":"",
 "bomba":false,"umbral":6.60,"ml_dosificados":7.4,"acido_restante_ml":88.2,
 "pulsos":4,"s_hat":0.18,"error_final":null,"temp_c":22.0,"temp_supuesta":true,
 "calib":{"offset":0.05,"fecha":"2026-11-19T10:20"},
 "resumen":{"umbral":6.5,"ph_final":6.53,"error":0.03,"pulsos":6,"ml":9.1,"segundos":74}}
```
- `ts` en segundos. Sin NTP puedes mandar `millis()/1000`: la app usa su propio reloj para saber si el dato es viejo.
- `resumen` solo cambia al terminar una sesión; la app guarda uno nuevo cada vez que cambia.
- `hocl_pct` es opcional: si no lo mandas, la app lo calcula con el pH y la temperatura.

**evento:**
```json
{"ts":1763571250,"tipo":"RECHAZO","detalle":"Pulso mayor al máximo permitido (1500 ms)","cmd":"p 2000"}
```

**hardware:**
```json
{"rele":false,"led":[0,255,0],"buzzer":"silencio","sensor":"OK",
 "modulos":{"XN03":true,"XN13":true,"XN44":true}}
```
`modulos`: pon `false` si un módulo I2C no responde. La app lo muestra como "No detectado".

## Código de ejemplo (ArduinoJson 7 + PubSubClient)

```cpp
#include "agua_contrato.h"
EstadoNodo st;

void publicarEvento(const char* tipo, const String& detalle, const String& cmd = "") {
  JsonDocument d;
  d[K_EV_TS] = millis() / 1000;
  d[K_EV_TIPO] = tipo;
  if (detalle.length()) d[K_EV_DETALLE] = detalle;
  if (cmd.length())     d[K_EV_CMD] = cmd;
  String s; serializeJson(d, s);
  mqtt.publish(TEMA_EVENTO, s.c_str(), false);           // sin retain
}

void publicarTelemetria() {
  JsonDocument d;
  d[K_TS] = millis() / 1000;
  d[K_NODO] = AGUA_NODO;
  d[K_PH] = roundf(st.ph * 100) / 100.0f;
  d[K_MV] = st.mv;
  d[K_SENSOR] = st.sensor;
  d[K_ESTADO] = st.estado;
  d[K_ERROR_MSG] = st.error_msg;
  d[K_BOMBA] = st.bomba;
  d[K_UMBRAL] = st.umbral;
  d[K_ML_DOSIFICADOS] = st.ml_dosificados;
  d[K_ACIDO_RESTANTE_ML] = st.acido_restante_ml;
  d[K_PULSOS] = st.pulsos;
  d[K_S_HAT] = st.s_hat;
  if (isnan(st.error_final)) d[K_ERROR_FINAL] = nullptr; else d[K_ERROR_FINAL] = st.error_final;
  d[K_TEMP_C] = st.temp_c;
  d[K_TEMP_SUPUESTA] = st.temp_supuesta;
  JsonObject c = d[K_CALIB].to<JsonObject>();
  c[K_CALIB_OFFSET] = st.calib_offset;
  c[K_CALIB_FECHA] = st.calib_fecha;
  String s; serializeJson(d, s);
  mqtt.publish(TEMA_TELEMETRIA, s.c_str(), true);
  mqtt.publish(TEMA_PH, String(st.ph, 2).c_str());
  mqtt.publish(TEMA_ESTADO, st.estado, true);
}

void onMensaje(char* topic, byte* payload, unsigned int len) {
  String msg; for (unsigned i = 0; i < len; i++) msg += (char)payload[i];
  msg.trim();
  if (strcmp(topic, TEMA_UMBRAL) == 0) {
    float u = msg.toFloat();
    if (u < UMBRAL_MIN || u > UMBRAL_MAX)
      publicarEvento(EV_RECHAZO, MOTIVO_UMBRAL_RANGO, "umbral " + msg);
    else st.umbral = u;
    return;
  }
  // TEMA_CMD
  int sp = msg.indexOf(' ');
  String orden = sp < 0 ? msg : msg.substring(0, sp);
  String arg   = sp < 0 ? ""  : msg.substring(sp + 1);
  if (orden == CMD_PULSO) {
    long ms = arg.toInt();
    if (ms > PULSO_MAX_MS) { publicarEvento(EV_RECHAZO, MOTIVO_PULSO_MAX, msg); return; }
    // encender relé, publicarEvento(EV_RELE_ON, "Pulso manual", msg); ...
  } else if (orden == CMD_DETENER) {
    // apagar relé YA, st.estado = ESTADO_IDLE; st.error_msg = "";
    publicarEvento(EV_ACK, "Bomba detenida", msg);
  } // ... dosificar, c, a, test_buzzer, test_led
  else publicarEvento(EV_RECHAZO, MOTIVO_DESCONOCIDA, msg);
}
```

## Cómo probar sin la app

```bash
mosquitto_sub -h <broker> -t 'agua/nodo1/#' -v           # ver todo lo que publicas
mosquitto_pub -h <broker> -t agua/nodo1/cmd -m 'p 2000'   # debe llegar RECHAZO
mosquitto_pub -h <broker> -t agua/nodo1/umbral -m '6.60'
mosquitto_pub -h <broker> -t agua/nodo1/cmd -m 'dosificar'
```

La referencia de comportamiento es el simulador de la app (`app/lib/data/simulador_esp32.dart`).
Sus pruebas (`app/test/simulador_test.dart`) son la especificación: el firmware debe responder igual.
