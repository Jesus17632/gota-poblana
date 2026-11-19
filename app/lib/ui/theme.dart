import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.normal,
    primary: Palette.normal,
    surface: Palette.fondo,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.fondo,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: Palette.texto),
      titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: Palette.texto),
      titleMedium: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: Palette.texto),
      bodyLarge: TextStyle(fontSize: 16, color: Palette.texto),
      bodyMedium: TextStyle(fontSize: 14, color: Palette.texto),
      bodySmall: TextStyle(fontSize: 12, color: Palette.textoSecundario),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.normal,
      thumbColor: Palette.normal,
      inactiveTrackColor: Palette.pista,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Palette.normal : Palette.pista),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.normal,
        minimumSize: const Size(0, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
