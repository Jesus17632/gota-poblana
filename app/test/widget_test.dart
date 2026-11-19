import 'package:flutter_test/flutter_test.dart';
import 'package:agua/main.dart';

void main() {
  testWidgets('La app arranca desconectada', (tester) async {
    await tester.pumpWidget(const Esp32BlinkApp());
    expect(find.text('Desconectado'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
  });
}
