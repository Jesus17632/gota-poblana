import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient crearClienteMqtt(String url, String clientId, int port) =>
    MqttBrowserClient.withPort(url, clientId, port);
