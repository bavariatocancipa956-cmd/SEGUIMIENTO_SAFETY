import 'package:flutter/material.dart';
import 'pantalla_principal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OperacionTocancipaApp());
}

class OperacionTocancipaApp extends StatelessWidget {
  const OperacionTocancipaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Operación Tocancipá',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
      ),
      home: const PantallaPrincipal(),
    );
  }
}