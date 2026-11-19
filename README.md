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

Arranca con el **simulador** activado, así que la demo corre sin hardware.

### Roles
- **Ciudadano** (por defecto): solo lectura.
- **Técnico**: Ajustes → Modo técnico → PIN `1234` (se cambia en Ajustes).
  Solo el técnico ve los controles de la bomba.

## Cambiar a MQTT

1. Entra como técnico.
2. Ajustes → Fuente de datos → **MQTT**.
3. Configura **Host**, **Puerto** (el del listener WebSocket del broker) y **Nodo**.
   - Si escribes solo el host, la app usa `ws://<host>/mqtt`.
   - Si tu broker usa otra ruta, escribe la URL completa, p. ej. `ws://192.168.1.10/`.

### Temas (contrato con el firmware)

| Tema | Dirección | Contenido |
|---|---|---|
| `agua/<nodo>/ph` | ESP → app | número (pH filtrado) |
| `agua/<nodo>/estado` | ESP → app | `IDLE` \| `PULSO` \| `MEZCLA` \| `ERROR` |
| `agua/<nodo>/telemetria` | ESP → app | JSON del modelo unificado |
| `agua/<nodo>/umbral` | app → ESP | número 4.5–7.0 |
| `agua/<nodo>/cmd` | app → ESP | `dosificar` \| `detener` \| `c <pH>` \| `a 100` |

Los temas se definen en `app/lib/data/mqtt_source.dart` (clase `MqttTopics`) y
los comandos en `app/lib/data/data_source.dart` (clase `Cmd`).

## Dónde editar

| Qué | Archivo |
|---|---|
| Tabla de colores del indicador universal (15 colores, pH 0–14) | `app/lib/core/ph_colors.dart` |
| Paleta de estados | `app/lib/core/palette.dart` |
| Cálculos (pKa, % HOCl, pH recomendado, NOM-127) | `app/lib/core/chem.dart` |
| Campos del modelo unificado | `app/lib/data/models.dart` |
| Simulador | `app/lib/data/simulator_source.dart` |

## Estructura de la app

```
lib/
├── core/    cálculos puros y constantes (sin Flutter)
├── data/    interfaz DataSource + Simulador + MQTT + modelos
├── state/   AppState (roles, historial, sesiones, avisos) y Settings
└── ui/      Inicio, Datos, Ajustes y widgets
```
