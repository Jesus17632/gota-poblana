# CloracionAgua

Sistema IoT de control de pH para agua: un ESP32-S3 lee una sonda de pH y
dosifica una solución ácida para **bajar** el pH hasta un umbral (4.5–7.0).
La app solo lee datos y envía órdenes; **el firmware tiene la última palabra
en seguridad** y puede rechazarlas.

```
app/        App Flutter (Android, Linux, web)
firmware/   Firmware del ESP32
```

## Correr la app

```fish
cd app
flutter pub get
flutter test                    # pruebas de los cálculos y del modelo
flutter run -d linux            # escritorio
flutter run -d <id-telefono>    # Android (ver `flutter devices`)
flutter run -d web-server --web-port 8080
```

Arranca conectándose por **MQTT** al broker WebSocket del ESP32
(`ws://172.20.10.9:81/`), con reintento cada 5 s. Sin hardware, entra como
técnico y cambia a **Simulador** en Ajustes → Fuente de datos.

### Primer uso
Una introducción interactiva de menos de 50 s (con **Omitir**) explica la
pecera, qué pH es seguro y qué pasa si el equipo falla, y al final se elige el rol:

- **Ciudadano**: solo lectura.
- **Técnico**: controles de la bomba, dispositivos y diagnósticos.

El rol se cambia en Ajustes → Perfil (sin PIN). La introducción se puede volver
a ver en Ajustes → Nodo y ayuda. Tema claro, oscuro o del sistema en Ajustes → Apariencia.

## Conectar el firmware real (MQTT)

MQTT está **activo por defecto**. El ESP32 hace de broker MQTT sobre WebSocket
en la misma red. El contrato para el firmware está en
[`firmware/CONTRATO.md`](firmware/CONTRATO.md) y los nombres listos para el `.ino`
en [`firmware/agua_contrato.h`](firmware/agua_contrato.h).

- Valores por defecto: host `172.20.10.9`, puerto `81`, ruta `/`, nodo `nodo1`
  (en `app/lib/core/device_constants.dart`).
- Se cambian desde la app: técnico → Ajustes → Fuente de datos (Host, Puerto, Ruta, Nodo).
- `mqttHabilitado = false` apaga MQTT por completo.

> La app **nunca** toca pines ni I2C. Solo manda órdenes de alto nivel; el ESP32
> valida los límites de seguridad, actúa y responde con eventos. La UI muestra
> "Enviando…" hasta recibir el evento y, si no llega en 3 s, "Sin respuesta del dispositivo".

### Contrato de mensajes (nodo por defecto `nodo1`)

**App → ESP32**

| Tema | Contenido |
|---|---|
| `agua/<nodo>/umbral` | número 4.5–7.0 |
| `agua/<nodo>/cmd` | `dosificar` · `detener` · `p <ms>` · `c <pH>` · `a 100` · `test_buzzer <inicio\|fin\|error>` · `test_led <r> <g> <b>` |

**ESP32 → App**

| Tema | Contenido |
|---|---|
| `agua/<nodo>/ph` | número (pH filtrado) |
| `agua/<nodo>/estado` | `IDLE` \| `PULSO` \| `MEZCLA` \| `ERROR` |
| `agua/<nodo>/telemetria` | JSON del modelo unificado (`ts`, `ph`, `estado`, `bomba`, `umbral`, `acido_restante_ml`, `resumen`, …) |
| `agua/<nodo>/evento` | `{"ts", "tipo", "detalle", "cmd"}` con `tipo` = `INICIO` `FIN` `RECHAZO` `ERROR` `RELE_ON` `RELE_OFF` `BUZZER` `LED` `ACK` |
| `agua/<nodo>/hardware` | `{"rele", "led":[r,g,b], "buzzer":"silencio"\|"sonando", "sensor", "modulos":{"XN03","XN13","XN44"}}`, "fallas":[{"codigo","severidad","modulo","detalle"}]}` |

**Importante para el firmware:** incluye en cada evento de respuesta el campo
`"cmd"` con la orden original (p. ej. `"cmd":"p 100"`). Así la app sabe a qué
orden responde. Si falta, la app asocia el evento con la orden pendiente más antigua.

### Comportamiento esperado (lo implementa el simulador; el firmware debe hacer lo mismo)

| Orden | Respuesta |
|---|---|
| `dosificar` con pH ≤ umbral + 0.05 | `RECHAZO` "El pH ya está por debajo del objetivo" |
| `dosificar` sin ácido para un pulso | `RECHAZO` "Ácido insuficiente" |
| `dosificar` válido | `INICIO` → ciclos `RELE_ON` → pulso → `RELE_OFF` → estado `MEZCLA` (~3 s) → … → `FIN` con `resumen` en la telemetría |
| `detener` (en cualquier momento) | `RELE_OFF` inmediato, estado `IDLE`, limpia el error, `ACK` |
| `p <ms>` con ms > 1500 | `RECHAZO` "Pulso mayor al máximo permitido (1500 ms)" |
| `p <ms>` válido | `RELE_ON` y `RELE_OFF` tras `<ms>` |
| `c <pH>` / `a 100` | `ACK` |
| `test_buzzer <x>` / `test_led r g b` | `BUZZER` / `LED` |
| Falla de sonda | estado `ERROR`, `sensor: SIN_RESPUESTA`, relé apagado, evento `ERROR` |

Inventario de ácido: ~33 mL por segundo de bomba. El código de referencia está en
`app/lib/data/simulador_esp32.dart` y las pruebas en `app/test/simulador_test.dart`.

### Alertas en la app

| Evento | Aviso | Sonido |
|---|---|---|
| `INICIO` | "Dosificación iniciada" | 880 → 1320 Hz |
| `FIN` | "Objetivo alcanzado: pH X.XX (error ±Y.YY)" | tres tonos descendentes |
| `RECHAZO` / `ERROR` / sin respuesta | motivo | tres pitidos de 400 Hz |
| `RELE_ON` / `RELE_OFF` | indicador "Bomba encendida/apagada" | — |

Sonidos y vibración se desactivan en Ajustes. Todo queda en Datos → **Registro de eventos** (técnico).

## Dónde editar

| Qué | Archivo |
|---|---|
| **Temas MQTT, nodo, comandos, tonos, pulso máximo, interruptor de MQTT** | `app/lib/core/device_constants.dart` |
| Tabla de colores del indicador universal (15 colores, pH 0–14) | `app/lib/core/ph_colors.dart` |
| Paleta de estados | `app/lib/core/palette.dart` |
| Colores claro/oscuro, espaciados | `app/lib/ui/tokens.dart` |
| Cálculos (pKa, % HOCl, pH recomendado, NOM-127) | `app/lib/core/chem.dart` |
| Campos del modelo unificado | `app/lib/data/models.dart` |
| Simulador del ESP32 | `app/lib/data/simulador_esp32.dart` |

## Estructura de la app

```
lib/
├── core/    cálculos puros y constantes (sin Flutter)
├── data/    servicio de dispositivos: interfaz + SimuladorESP32 + MQTT + modelos
├── services/ sonidos y vibración
├── state/   AppState (roles, historial, sesiones, avisos) y Settings
└── ui/      Inicio, Datos, Ajustes y widgets
```
