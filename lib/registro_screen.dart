import 'package:flutter/material.dart';
import 'api_service.dart';

class RegistroEstibaScreen extends StatefulWidget {
  final Map<String, dynamic>? datosEmpleado;
  const RegistroEstibaScreen({super.key, this.datosEmpleado});

  @override
  State<RegistroEstibaScreen> createState() => _RegistroEstibaScreenState();
}

class _RegistroEstibaScreenState extends State<RegistroEstibaScreen> {
  bool _isLoading = true;
  List<dynamic> _registros = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.consultar('estibas', 'reparacion_estibas');
      if (mounted) setState(() => _registros = data);
    } catch (e) {
      debugPrint('Error al cargar: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1)))
          : _registros.isEmpty
          ? const Center(
        child: Text(
          'Sin registros encontrados',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _registros.length,
        itemBuilder: (context, index) {
          final item = _registros[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF0D47A1),
                child: Icon(Icons.build, color: Colors.white),
              ),
              title: Text(
                'Fecha: ${item['fecha'] ?? 'N/A'} | Turno: ${item['turno'] ?? 'N/A'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'Operario: ${item['operario'] ?? 'N/A'}\nReparadas: ${item['reparadas'] ?? '0'} | Clasificadas: ${item['clasificadas'] ?? '0'}',
                  style: TextStyle(color: Colors.grey[800]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}