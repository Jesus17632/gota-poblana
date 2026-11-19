// Elige el cliente MQTT correcto: dart:io (Android/Linux) o navegador (web).
export 'mqtt_factory_io.dart'
    if (dart.library.js_interop) 'mqtt_factory_web.dart';
