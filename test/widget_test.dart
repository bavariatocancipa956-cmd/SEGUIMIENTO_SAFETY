import 'package:flutter_test/flutter_test.dart';
import 'package:operacion_tocancipa/main.dart';

void main() {
  testWidgets('Prueba de carga de Operación Tocancipá', (WidgetTester tester) async {
    // Renderiza la aplicación con la clase principal correcta
    await tester.pumpWidget(const OperacionTocancipaApp());

    // Confirma que el widget principal carga correctamente
    expect(find.byType(OperacionTocancipaApp), findsOneWidget);
  });
}