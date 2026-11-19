import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'state/app_state.dart';
import 'ui/app_scope.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  await state.iniciar(); // simulador por defecto: la demo corre sin hardware
  runApp(AguaApp(state: state));
}

class AguaApp extends StatelessWidget {
  const AguaApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Cloración Agua',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      ),
    );
  }
}
