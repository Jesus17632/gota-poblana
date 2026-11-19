import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/app_state.dart';
import 'state/settings.dart';
import 'ui/app_scope.dart';
import 'ui/onboarding.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  await state.iniciar();
  runApp(AguaApp(state: state));
}

// Temas creados una sola vez (la app se reconstruye a 2 Hz).
final ThemeData _temaClaro = buildTheme(oscuro: false);
final ThemeData _temaOscuro = buildTheme(oscuro: true);

class AguaApp extends StatelessWidget {
  const AguaApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Cloración Agua',
          debugShowCheckedModeBanner: false,
          theme: _temaClaro,
          darkTheme: _temaOscuro,
          themeMode: switch (state.settings.tema) {
            ModoTema.sistema => ThemeMode.system,
            ModoTema.claro => ThemeMode.light,
            ModoTema.oscuro => ThemeMode.dark,
          },
          home: const _Raiz(),
        ),
      ),
    );
  }
}

/// Muestra la introducción la primera vez (o si se pide desde Ajustes).
class _Raiz extends StatelessWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AnimatedSwitcher(
      duration: animDur(context, 300),
      child: s.settings.onboardingVisto
          ? const Shell(key: ValueKey('shell'))
          : const Onboarding(key: ValueKey('onboarding')),
    );
  }
}
