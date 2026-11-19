import 'package:material_ui/material_ui.dart';
import 'screens/home_screen.dart';

void main() => runApp(const Esp32BlinkApp());

class Esp32BlinkApp extends StatelessWidget {
  const Esp32BlinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Blink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
