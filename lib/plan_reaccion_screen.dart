import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PlanReaccionScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const PlanReaccionScreen({super.key, this.onToggleSidebar});

  @override
  State<PlanReaccionScreen> createState() => _PlanReaccionScreenState();
}

class _PlanReaccionScreenState extends State<PlanReaccionScreen> {
  static const String _apiConsultar = 'https://plantatocancipa.site/api/v1/db_logistica/consultar/roturas/plan_reaccion_visual';
  static const String _apiInsertar = 'https://plantatocancipa.site/api/v1/db_logistica/insertar/roturas/plan_reaccion_visual';
  static const String _apiKey = 'PlantaLogistica2026*';

  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todosLosPlanes = [];
  List<Map<String, dynamic>> _planesFiltrados = [];

  List<String> _listaPI = ['Todos los PI'];
  List<String> _listaProblemas = ['Todos los Problemas'];

  String _piSeleccionado = 'Todos los PI';
  String _problemaSeleccionado = 'Todos los Problemas';
  String _filtroTexto = '';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final urlSinCache = '$_apiConsultar?_t=${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.get(
        Uri.parse(urlSinCache),
        headers: {'Content-Type': 'application/json', 'x-api-key': _apiKey},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> datosRaw = body['data'] ?? [];

        final List<Map<String, dynamic>> datosProcesados = [];
        final Set<String> pis = {'Todos los PI'};
        final Set<String> problemas = {'Todos los Problemas'};

        for (var fila in datosRaw) {
          if (fila is Map) {
            final Map<String, dynamic> mapa = {};
            fila.forEach((key, val) => mapa[key.toString().toLowerCase().trim()] = val);
            datosProcesados.add(mapa);

            String pi = mapa['itens']?.toString() ?? '';
            String prob = mapa['causal']?.toString() ?? '';

            if (pi.isNotEmpty && pi.toLowerCase() != 'null') pis.add(pi.trim());
            if (prob.isNotEmpty && prob.toLowerCase() != 'null') problemas.add(prob.trim());
          }
        }

        setState(() {
          _todosLosPlanes = datosProcesados;
          _listaPI = pis.toList()..sort();
          _listaProblemas = problemas.toList()..sort();
          _aplicarFiltros();
          _cargando = false;
        });
      } else {
        setState(() {
          _mensajeError = 'Error de servidor (${response.statusCode}): ${response.body}';
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensajeError = 'Error de conexión. Verifica la API: $e';
        _cargando = false;
      });
    }
  }

  void _aplicarFiltros() {
    setState(() {
      _planesFiltrados = _todosLosPlanes.where((plan) {
        String pi = plan['itens']?.toString() ?? '';
        String prob = plan['causal']?.toString() ?? '';
        String accion = plan['plan_reaccion']?.toString() ?? '';
        String tips = plan['preventiva']?.toString() ?? '';

        if (_piSeleccionado != 'Todos los PI' && pi.trim() != _piSeleccionado) return false;
        if (_problemaSeleccionado != 'Todos los Problemas' && prob.trim() != _problemaSeleccionado) return false;

        if (_filtroTexto.isNotEmpty) {
          String t = _filtroTexto.toLowerCase();
          if (!pi.toLowerCase().contains(t) &&
              !prob.toLowerCase().contains(t) &&
              !accion.toLowerCase().contains(t) &&
              !tips.toLowerCase().contains(t)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  Future<void> _guardarNuevoPlan(String pi, String problema, String accion, String tips) async {
    Navigator.of(context).pop();
    setState(() => _cargando = true);

    try {
      final bodyData = jsonEncode({
        "data": {
          "itens": pi,
          "causal": problema,
          "plan_reaccion": accion,
          "preventiva": tips,
        }
      });

      final response = await http.post(
        Uri.parse(_apiInsertar),
        headers: {'Content-Type': 'application/json', 'x-api-key': _apiKey},
        body: bodyData,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan guardado exitosamente'), backgroundColor: Colors.green));
        _cargarDatos();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al guardar el plan'), backgroundColor: Colors.red));
        setState(() => _cargando = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de conexión al guardar'), backgroundColor: Colors.red));
      setState(() => _cargando = false);
    }
  }

  void _mostrarDialogoAgregar() {
    final TextEditingController piCtrl = TextEditingController();
    final TextEditingController probCtrl = TextEditingController();
    final TextEditingController accionCtrl = TextEditingController();
    final TextEditingController tipsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Agregar Nuevo Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 20),
                _buildInputDialog('PI (Ítem)', piCtrl, maxLines: 1),
                const SizedBox(height: 12),
                _buildInputDialog('Problema (Causal)', probCtrl, maxLines: 2),
                const SizedBox(height: 12),
                _buildInputDialog('Acción Correctiva (Plan de reacción)', accionCtrl, maxLines: 3),
                const SizedBox(height: 12),
                _buildInputDialog('TIPS (Verificar/Actuar)', tipsCtrl, maxLines: 2),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (piCtrl.text.isNotEmpty && probCtrl.text.isNotEmpty) {
                          _guardarNuevoPlan(piCtrl.text, probCtrl.text, accionCtrl.text, tipsCtrl.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB300),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('Guardar Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputDialog(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade600)),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade900, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.w600))),
          ElevatedButton(
            onPressed: _cargarDatos,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, elevation: 0),
            child: const Text('REINTENTAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // Celdas para la tabla
  Widget _buildHeaderCell(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Text(texto, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
    );
  }

  Widget _buildDataCell(String texto, {bool isBlue = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          color: isBlue ? Colors.blue.shade700 : const Color(0xFF334155),
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(backgroundColor: Color(0xFFF8FAFC), body: Center(child: CircularProgressIndicator(color: Color(0xFFFFB300))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            if (_mensajeError != null) _buildBannerError(),

            // HEADER ESTILO WEB
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ESTÁNDARES DE PLANES DE REACCIÓN',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                ),
                ElevatedButton.icon(
                  onPressed: _mostrarDialogoAgregar,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Agregar Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB300),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // BARRA DE FILTROS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildDropdownFiltro('FILTRAR POR PI', _listaPI, _piSeleccionado, (val) {
                      setState(() { _piSeleccionado = val!; _aplicarFiltros(); });
                    }),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDropdownFiltro('FILTRAR POR PROBLEMA', _listaProblemas, _problemaSeleccionado, (val) {
                      setState(() { _problemaSeleccionado = val!; _aplicarFiltros(); });
                    }),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('BUSCAR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 35,
                          child: TextField(
                            onChanged: (val) {
                              _filtroTexto = val;
                              _aplicarFiltros();
                            },
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Buscar en todo...',
                              prefixIcon: const Icon(Icons.search, size: 16),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // TABLA DE DATOS (CON DISEÑO FORMAL DE TABLA Y ENCABEZADO FIJO)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    children: [
                      // HEADER TABLA FIJO
                      Container(
                        color: const Color(0xFFF8FAFC),
                        child: Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2),
                            1: FlexColumnWidth(3),
                            2: FlexColumnWidth(4),
                            3: FlexColumnWidth(3),
                          },
                          border: TableBorder(
                            bottom: BorderSide(color: Colors.grey.shade300),
                            verticalInside: BorderSide(color: Colors.grey.shade200),
                          ),
                          children: [
                            TableRow(
                              children: [
                                _buildHeaderCell('PI'),
                                _buildHeaderCell('Problema'),
                                _buildHeaderCell('Acción Correctiva'),
                                _buildHeaderCell('TIPS (Verificar/Actuar)'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // BODY TABLA SCROLLABLE
                      Expanded(
                        child: _planesFiltrados.isEmpty
                            ? const Center(child: Text('No se encontraron planes', style: TextStyle(color: Colors.grey)))
                            : SingleChildScrollView(
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(2),
                              1: FlexColumnWidth(3),
                              2: FlexColumnWidth(4),
                              3: FlexColumnWidth(3),
                            },
                            border: TableBorder(
                              horizontalInside: BorderSide(color: Colors.grey.shade200),
                              verticalInside: BorderSide(color: Colors.grey.shade200),
                            ),
                            children: _planesFiltrados.map((plan) {
                              return TableRow(
                                children: [
                                  _buildDataCell(plan['itens']?.toString() ?? '', isBlue: true),
                                  _buildDataCell(plan['causal']?.toString() ?? '', isBold: true),
                                  _buildDataCell(plan['plan_reaccion']?.toString() ?? ''),
                                  _buildDataCell(plan['preventiva']?.toString() ?? ''),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      // FOOTER INDICADOR FIJO
                      Container(
                        padding: const EdgeInsets.all(12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          border: Border(top: BorderSide(color: Colors.grey.shade300)),
                        ),
                        child: Text('Mostrar ${_planesFiltrados.length} registros', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownFiltro(String label, List<String> opciones, String valorActual, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: opciones.contains(valorActual) ? valorActual : opciones.first,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
              style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
              onChanged: onChanged,
              items: opciones.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}