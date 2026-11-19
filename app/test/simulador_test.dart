// Reglas del firmware que el simulador debe reproducir (referencia para el
// equipo de firmware). Usan timers reales; cada prueba tarda < 2 s.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agua/core/device_constants.dart';
import 'package:agua/core/wav.dart';
import 'package:agua/data/data_source.dart';
import 'package:agua/data/models.dart';
import 'package:agua/data/simulador_esp32.dart';

Future<EventoDispositivo> primerEvento(SimuladorESP32 sim,
        {bool Function(EventoDispositivo)? donde}) =>
    sim.eventos
        .firstWhere(donde ?? (_) => true)
        .timeout(const Duration(seconds: 2));

void main() {
  late SimuladorESP32 sim;

  setUp(() async {
    sim = SimuladorESP32();
    await sim.start();
  });

  tearDown(() => sim.stop());

  test('pulso mayor a 1500 ms → RECHAZO', () async {
    final f = primerEvento(sim);
    await sim.enviarCmd(Cmd.pulso(2000));
    final e = await f;
    expect(e.tipo, TipoEvento.rechazo);
    expect(e.detalle, contains('1500'));
    expect(e.cmd, 'p 2000');
  });

  test('pulso válido → RELE_ON y luego RELE_OFF', () async {
    final on = primerEvento(sim);
    final off = primerEvento(sim, donde: (e) => e.tipo == TipoEvento.releOff);
    unawaited(sim.enviarCmd(Cmd.pulso(100)));
    expect((await on).tipo, TipoEvento.releOn);
    expect((await off).tipo, TipoEvento.releOff);
  });

  test('dosificar con pH ≤ umbral + 0.05 → RECHAZO', () async {
    // Calibra para que el pH lea ~6.0 y fija umbral 6.5
    await sim.enviarCmd(Cmd.calibrar(6.0));
    await sim.enviarUmbral(6.5);
    final f = primerEvento(sim);
    await sim.enviarCmd(Cmd.dosificar);
    final e = await f;
    expect(e.tipo, TipoEvento.rechazo);
    expect(e.detalle, 'El pH ya está por debajo del objetivo');
  });

  test('dosificar válido → INICIO; detener → RELE_OFF/ACK', () async {
    await sim.enviarUmbral(6.5);
    final ini = primerEvento(sim);
    await sim.enviarCmd(Cmd.dosificar);
    expect((await ini).tipo, TipoEvento.inicio);

    final ack = primerEvento(sim, donde: (e) => e.tipo == TipoEvento.ack);
    await sim.enviarCmd(Cmd.detener);
    final e = await ack;
    expect(e.cmd, 'detener');
  });

  test('orden desconocida → RECHAZO', () async {
    final f = primerEvento(sim);
    await sim.enviarCmd('hola');
    expect((await f).tipo, TipoEvento.rechazo);
  });

  test('responde con retardo de red (≥ 150 ms)', () async {
    final sw = Stopwatch()..start();
    await sim.enviarCmd(Cmd.testBuzzer('inicio'));
    expect(sw.elapsedMilliseconds,
        greaterThanOrEqualTo(DeviceConst.retardoRedMinMs - 5));
  });

  test('falla de sensor → ERROR y relé apagado', () async {
    final f = primerEvento(sim, donde: (e) => e.tipo == TipoEvento.error);
    final hw = sim.hardware
        .firstWhere((h) => h.sensor == SensorEstado.sinRespuesta)
        .timeout(const Duration(seconds: 2));
    sim.simularFallaSensor();
    expect((await f).tipo, TipoEvento.error);
    expect((await hw).rele, isFalse);
  });

  test('WAV: cabecera RIFF y tamaño esperado', () {
    final b = generarWav(const [(880, 100)], sampleRate: 8000);
    expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');
    expect(b.length, 44 + 800 * 2);
  });
}
