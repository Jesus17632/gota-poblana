import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import 'tokens.dart';

ThemeData buildTheme({required bool oscuro}) {
  final c = oscuro ? AguaColors.oscuroTema : AguaColors.claro;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.normal,
    brightness: oscuro ? Brightness.dark : Brightness.light,
    primary: oscuro ? Palette.dosificando : Palette.normal,
    surface: c.superficie,
  );
  final texto = TextTheme(
    headlineLarge: TextStyle(
        fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: c.texto),
    headlineSmall: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.texto),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.texto),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.texto),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.texto2),
    bodyLarge: TextStyle(fontSize: 16, color: c.texto, height: 1.35),
    bodyMedium: TextStyle(fontSize: 14, color: c.texto, height: 1.35),
    bodySmall: TextStyle(fontSize: 12, color: c.texto2, height: 1.3),
    labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
  final primario = scheme.primary;
  return ThemeData(
    useMaterial3: true,
    brightness: oscuro ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.fondo,
    textTheme: texto,
    extensions: [c],
    dividerColor: c.linea,
    iconTheme: IconThemeData(color: c.texto2),
    listTileTheme: ListTileThemeData(
      iconColor: c.texto2,
      textColor: c.texto,
      contentPadding: EdgeInsets.zero,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primario,
      thumbColor: primario,
      inactiveTrackColor: c.linea,
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Palette.blanco),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primario : c.linea),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.all(BorderSide(color: c.linea)),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.seleccion : c.superficie),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primario : c.texto2),
        textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primario,
        foregroundColor: Palette.textoSobre(primario),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.texto,
        side: BorderSide(color: c.linea, width: 1.2),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primario,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primario),
  );
}
