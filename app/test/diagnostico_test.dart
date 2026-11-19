// El test completo corre de punta a punta contra el simulador.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agua/core/fallas.dart';
import 'package:agua/services/sonidos.dart';
import 'package:agua/state/app_state.dart';
import 'package:agua/state/diagnostico.dart';

/// Sin audio en pruebas.
class _SonidosMudos extends Sonidos {
  @override
  Future<void> tocar(Tono t) async {}
  @override
  Future<void> vibrar(Tono t) async {}
}

Future<AppState> _app() async {
  SharedPreferences.setMockInitialValues({
    'cfg.versionConexion': 2,
    'cfg.fuente': 'simulador',
    'cfg.sonidos': false,
    'cfg.vibracion': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final s = AppState(prefs, sonidos: _SonidosMudos());
  await s.iniciar();
  expect(s.entrarTecnico('1234'), isTrue);
  // Deja llegar las primeras lecturas
  await Future.delayed(const Duration(milliseconds: 600));
  return s;
}

ResultadoPaso _r(Diagnostico d, String id) =>
    d.pasos.firstWhere((p) => p.id == id).resultado;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sin fallas: conexión, sonda, módulos y respuesta OK', () async {
    final s = await _app();
    await s.iniciarDiagnostico();
    final d = s.diagnostico;
    expect(d.terminado, isTrue);
    expect(_r(d, 'conexion'), ResultadoPaso.ok);
    expect(_r(d, 'datos'), ResultadoPaso.ok);
    expect(_r(d, 'sonda'), ResultadoPaso.ok);
    expect(_r(d, 'xn13'), ResultadoPaso.ok);
    expect(_r(d, 'respuesta'), ResultadoPaso.ok);
    expect(_r(d, 'buzzer'), ResultadoPaso.ok);
    expect(_r(d, 'bomba'), ResultadoPaso.omitido); // nunca se enciende
    expect(d.contar(ResultadoPaso.falla), 0);
    expect(s.hayErrorEquipo, isFalse);
    s.dispose();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('bomba desconectada: círculo en error y el test la detecta', () async {
    final s = await _app();
    s.simularFalla(Fallas.bombaDesconectada);
    await Future.delayed(const Duration(milliseconds: 600));
    expect(s.hayErrorEquipo, isTrue);
    expect(s.errorEquipoTexto, 'Bomba desconectada');
    await s.iniciarDiagnostico();
    expect(_r(s.diagnostico, 'xn13'), ResultadoPaso.falla);
    expect(_r(s.diagnostico, 'controlador'), ResultadoPaso.falla);
    s.dispose();
  }, timeout: const Timeout(Duration(seconds: 40)));
}
