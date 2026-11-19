// Los avisos (visual + sonido) salen de los eventos del equipo.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agua/services/notificaciones.dart';
import 'package:agua/services/sonidos.dart';
import 'package:agua/state/app_state.dart';

/// Registra los tonos en lugar de sonar.
class _SonidosEspia extends Sonidos {
  final tonos = <Tono>[];
  @override
  Future<void> tocar(Tono t) async => tonos.add(t);
  @override
  Future<void> vibrar(Tono t) async {}
}

Future<(AppState, _SonidosEspia, List<Aviso>)> _app({bool sonidos = true}) async {
  SharedPreferences.setMockInitialValues({
    'cfg.versionConexion': 2,
    'cfg.fuente': 'simulador',
    'cfg.sonidos': sonidos,
    'cfg.vibracion': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final espia = _SonidosEspia();
  final s = AppState(prefs, sonidos: espia, notificaciones: Notificaciones());
  final avisos = <Aviso>[];
  s.avisos.listen(avisos.add);
  await s.iniciar();
  await s.cambiarRol(Rol.tecnico);
  await Future.delayed(const Duration(milliseconds: 500));
  return (s, espia, avisos);
}

Future<void> _esperar(bool Function() c) async {
  for (var i = 0; i < 40 && !c(); i++) {
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dosificar → aviso "Dosificación iniciada" + tono de inicio', () async {
    final (s, espia, avisos) = await _app();
    await s.dosificar(6.5);
    await _esperar(() => avisos.any((a) => a.tipo == TipoAviso.inicio));
    expect(avisos.any((a) => a.tipo == TipoAviso.inicio), isTrue);
    expect(espia.tonos, contains(Tono.inicio));
    await s.detener();
    s.dispose();
  });

  test('orden rechazada → aviso con el motivo + tono de error', () async {
    final (s, espia, avisos) = await _app();
    await s.probarBomba(2000); // > 1500 ms
    await _esperar(() => avisos.any((a) => a.tipo == TipoAviso.rechazo));
    final a = avisos.firstWhere((a) => a.tipo == TipoAviso.rechazo);
    expect(a.mensaje, contains('1500'));
    expect(espia.tonos, contains(Tono.error));
    s.dispose();
  });

  test('con "Sonidos" apagado hay aviso visual pero no tono', () async {
    final (s, espia, avisos) = await _app(sonidos: false);
    await s.probarBomba(2000);
    await _esperar(() => avisos.isNotEmpty);
    expect(avisos, isNotEmpty);
    expect(espia.tonos, isEmpty);
    s.dispose();
  });

  test('Probar avisos: inicio, fin y error en orden', () async {
    final (s, espia, avisos) = await _app();
    await s.probarAvisos();
    expect(avisos.map((a) => a.tipo).toList(),
        containsAllInOrder([TipoAviso.inicio, TipoAviso.fin, TipoAviso.error]));
    expect(espia.tonos, containsAllInOrder([Tono.inicio, Tono.fin, Tono.error]));
    s.dispose();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
