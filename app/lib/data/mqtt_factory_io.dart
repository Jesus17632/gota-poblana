import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient crearClienteMqtt(String url, String clientId, int port) {
  final c = MqttServerClient.withPort(url, clientId, port);
  c.useWebSocket = true;
  return c;
}
