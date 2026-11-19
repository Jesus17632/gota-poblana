// Firmware ESP32: crea su propia red WiFi y expone una API HTTP mínima.
//   GET /status                          -> {"blinking":false,"interval":500}
//   GET /blink?state=on|off&interval=ms  -> mismo JSON con el nuevo estado
#include <WiFi.h>
#include <WebServer.h>

const char* AP_SSID = "ESP32-Blink";
const char* AP_PASS = "12345678";   // mínimo 8 caracteres

// Ajusta al LED de tu placa. Muchas DevKit ESP32 usan GPIO 2.
// En ESP32-S3 DevKitC el LED es RGB (GPIO 48 o 38): ver nota abajo.
const int LED_PIN = 2;

WebServer server(80);
bool blinking = false;
unsigned long intervalMs = 500;
unsigned long lastToggle = 0;
bool ledState = false;

void setLed(bool on) {
  ledState = on;
  digitalWrite(LED_PIN, on ? HIGH : LOW);
  // Para el LED RGB de un ESP32-S3, comenta la línea de arriba y usa:
  // rgbLedWrite(RGB_BUILTIN, 0, on ? 40 : 0, 0);   // core Arduino 3.x
  // neopixelWrite(RGB_BUILTIN, 0, on ? 40 : 0, 0); // core Arduino 2.x
}

void sendStatus() {
  String json = String("{\"blinking\":") + (blinking ? "true" : "false") +
                ",\"interval\":" + intervalMs + "}";
  // CORS: necesario para que la app corriendo en el navegador (flutter web) pueda leer la respuesta
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.send(200, "application/json", json);
}

void handleBlink() {
  if (server.hasArg("interval")) {
    long v = server.arg("interval").toInt();
    if (v >= 50 && v <= 5000) intervalMs = v;
  }
  if (server.hasArg("state")) {
    blinking = server.arg("state") == "on";
    if (!blinking) setLed(false);
  }
  sendStatus();
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  setLed(false);

  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.print("AP listo. IP: ");
  Serial.println(WiFi.softAPIP());   // normalmente 192.168.4.1

  server.on("/status", sendStatus);
  server.on("/blink", handleBlink);
  server.begin();
}

void loop() {
  server.handleClient();
  // Blink sin delay() para no bloquear el servidor
  if (blinking && millis() - lastToggle >= intervalMs) {
    lastToggle = millis();
    setLed(!ledState);
  }
}
