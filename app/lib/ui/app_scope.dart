import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

/// Expone el AppState a todo el árbol y reconstruye cuando notifica (2 Hz).
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Movimiento reducido: preferencia de la app O del sistema.
bool reducirMovimiento(BuildContext context) =>
    AppScope.of(context).settings.movimientoReducido ||
    MediaQuery.of(context).disableAnimations;

Duration animDur(BuildContext context, [int ms = 400]) =>
    reducirMovimiento(context) ? Duration.zero : Duration(milliseconds: ms);
