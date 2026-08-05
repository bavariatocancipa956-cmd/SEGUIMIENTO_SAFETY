import 'dart:convert';
import 'dart:math';
import 'dart:html' as html; // Necesario para la descarga en Flutter Web
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';

class EstibasEntregadasScreen extends StatefulWidget {
  final Map<String, dynamic>? datosEmpleado;
  const EstibasEntregadasScreen({super.key, this.datosEmpleado});

  @override
  State<EstibasEntregadasScreen> createState() => _EstibasEntregadasScreenState();
}

class _EstibasEntregadasScreenState extends State<EstibasEntregadasScreen> {
  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todosLosRegistros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  DateTime _fechaDesde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _fechaHasta = DateTime.now();

  String _turnoSel = 'Todos';
  String _areaSel = 'Todos';

  final List<String> _listaTurnos = ['Todos', 'T1', 'T2', 'T3'];
  List<String> _listaAreas = ['Todos'];

  // KPIs
  int _totalEntregadas = 0;
  int _totalEntregas = 0;

  int _pInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  Future<void> _cargarDatosBD() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final List<dynamic> dataCompleta = await ApiService.consultar('roturas', 'estibas_reporte_linea');

      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> areasTemp = {'Todos'};

      for (var fila in dataCompleta) {
        if (fila is Map) {
          final Map<String, dynamic> mapa = {};
          fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
          datosProcesados.add(mapa);

          String area = (mapa['area_entregada']?.toString().trim() ?? '');
          if (area.isNotEmpty && area != 'null' && area != 'N/A') {
            areasTemp.add(area);
          }
        }
      }

      setState(() {
        _todosLosRegistros = datosProcesados;
        _listaAreas = areasTemp.toList()..sort();
        _aplicarFiltros();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error de conexión en Dashboard Entregas: $e');
      setState(() {
        _mensajeError = 'Error de conexión: $e';
        _cargando = false;
      });
    }
  }

  void _aplicarFiltros() {
    setState(() {
      _registrosFiltrados = _todosLosRegistros.where((row) {
        DateTime? fechaFila;
        String? rawFecha = row['fecha']?.toString();
        if (rawFecha != null && rawFecha.length >= 10) {
          fechaFila = DateTime.tryParse(rawFecha.substring(0, 10));
        }

        if (fechaFila != null) {
          final fSin = DateTime(fechaFila.year, fechaFila.month, fechaFila.day);
          final dSin = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
          final hSin = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day);
          if (fSin.isBefore(dSin) || fSin.isAfter(hSin)) return false;
        }

        if (_turnoSel != 'Todos') {
          String turnoFila = row['turno']?.toString().trim().toUpperCase() ?? '';
          if (turnoFila != _turnoSel) return false;
        }

        if (_areaSel != 'Todos') {
          String areaFila = row['area_entregada']?.toString().trim() ?? '';
          if (areaFila != _areaSel) return false;
        }

        return true;
      }).toList();

      _calcularKpis();
    });
  }

  void _calcularKpis() {
    _totalEntregadas = 0;
    _totalEntregas = _registrosFiltrados.length;

    for (var row in _registrosFiltrados) {
      int cant = _pInt(row['cantidad_esntregada']);
      _totalEntregadas += cant;
    }
  }

  // 📥 FUNCIÓN PARA DESCARGAR EXCEL / CSV
  void _descargarExcel() {
    if (_registrosFiltrados.isEmpty) {
      _mostrarMensaje('No hay registros para exportar', esError: true);
      return;
    }

    try {
      final StringBuffer csvBuilder = StringBuffer();

      // BOM UTF-8 para garantizar que Excel abra correctamente tildes y caracteres especiales
      csvBuilder.write('\uFEFF');

      // Encabezados de la tabla
      csvBuilder.writeln('FECHA;TURNO;ÁREA ENTREGADA;QUIEN RECIBE;CANTIDAD');

      // Filas de datos
      for (var r in _registrosFiltrados) {
        String fecha = (r['fecha']?.toString() ?? '').split('T')[0];
        String turno = r['turno']?.toString().toUpperCase() ?? 'T1';
        String area = (r['area_entregada']?.toString() ?? 'Desconocida').replaceAll(';', ',');
        String quienRecibe = (r['nombre_quien recibe'] ?? r['nombre_quien_recibe'] ?? 'No registrado').toString().replaceAll(';', ',');
        int cant = _pInt(r['cantidad_esntregada']);

        csvBuilder.writeln('$fecha;$turno;$area;$quienRecibe;$cant');
      }

      // Descarga directa mediante Blob en navegador web
      if (kIsWeb) {
        final bytes = utf8.encode(csvBuilder.toString());
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);

        final fechaStr = DateTime.now().toString().substring(0, 10);

        html.AnchorElement(href: url)
          ..setAttribute("download", "Entregas_Estibas_$fechaStr.csv")
          ..click();

        html.Url.revokeObjectUrl(url);
        _mostrarMensaje('Archivo Excel descargado con éxito');
      } else {
        _mostrarMensaje('Descarga habilitada para entorno Web');
      }
    } catch (e) {
      _mostrarMensaje('Error al generar archivo: $e', esError: true);
    }
  }

  void _mostrarMensaje(String texto, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
          backgroundColor: Color(0xFFF4F6F9),
          body: Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mensajeError != null) _buildBannerError(),

            _buildBarraFiltros(),
            const SizedBox(height: 20),

            _buildTarjetasKPI(),
            const SizedBox(height: 20),

            // 📈 GRÁFICAS
            Row(
              children: [
                Expanded(
                  child: _buildCardGrafico(
                    titulo: 'Evolución Diaria de Estibas Entregadas',
                    child: EvolucionLineChartEntregas(
                      reportes: _registrosFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                      colorLinea: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildCardGrafico(
                    titulo: 'Distribución de Entregas por Área',
                    child: _buildGraficoBarrasArea(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 📊 RESUMEN POR ÁREA Y TURNO
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildResumenPorArea()),
                const SizedBox(width: 20),
                Expanded(child: _buildResumenPorTurno()),
              ],
            ),
            const SizedBox(height: 20),

            // 📋 DETALLE COMPLETO (CON BOTÓN DESCARGAR EXCEL)
            _buildDetalleCompleto(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 1️⃣ BARRA DE FILTROS
  Widget _buildBarraFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _buildFiltroFecha('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d))),
          const SizedBox(width: 15),
          Expanded(child: _buildFiltroFecha('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d))),
          const SizedBox(width: 15),
          Expanded(child: _buildFiltroDropdown('TURNO', _turnoSel, _listaTurnos, (v) => setState(() => _turnoSel = v!))),
          const SizedBox(width: 15),
          Expanded(child: _buildFiltroDropdown('ÁREA ENTREGADA', _areaSel, _listaAreas, (v) => setState(() => _areaSel = v!))),
          const SizedBox(width: 20),

          // Botones
          ElevatedButton.icon(
            onPressed: _aplicarFiltros,
            icon: const Icon(Icons.filter_alt_rounded, size: 16),
            label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('FOTO', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF546E7A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.tv, size: 16),
            label: const Text('TV', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF263238),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroFecha(String label, DateTime fecha, Function(DateTime) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF78909C))),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) onSelect(p);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black87),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildFiltroDropdown(String label, String valor, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF78909C))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(valor) ? valor : items.first,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black87, size: 20),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: onChanged,
            ),
          ),
        )
      ],
    );
  }

  // 2️⃣ TARJETAS KPI
  Widget _buildTarjetasKPI() {
    return Row(
      children: [
        Expanded(child: _buildKPICard('CANTIDAD ENTREGADA', '$_totalEntregadas', const Color(0xFF3B82F6), Colors.black87)),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICard('VECES ENTREGADA', '$_totalEntregas', const Color(0xFF10B981), Colors.black87)),
      ],
    );
  }

  Widget _buildKPICard(String titulo, String valor, Color colorBorde, Color colorTexto) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(width: 5, height: 50, decoration: BoxDecoration(color: colorBorde, borderRadius: BorderRadius.circular(10))),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              children: [
                Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF78909C), letterSpacing: 0.5), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(valor, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: colorTexto)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3️⃣ ESTRUCTURAS BASE DE TARJETAS
  Widget _buildCardGrafico({required String titulo, required Widget child}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildCardTabla({
    required String titulo,
    required Widget child,
    double height = 340,
    Widget? accionHeader,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                if (accionHeader != null) accionHeader,
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // 4️⃣ BARRAS DE ÁREAS
  Widget _buildGraficoBarrasArea() {
    Map<String, int> conteoArea = {};
    for (var r in _registrosFiltrados) {
      String area = r['area_entregada']?.toString().trim() ?? 'Sin Área';
      conteoArea[area] = (conteoArea[area] ?? 0) + _pInt(r['cantidad_esntregada']);
    }

    List<MapEntry<String, int>> lista = conteoArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (lista.isEmpty) {
      return const SizedBox(height: 240, child: Center(child: Text('Sin datos en el rango', style: TextStyle(fontSize: 13, color: Colors.grey))));
    }

    return SizedBox(
      height: 240,
      child: CustomPaint(
        painter: _BarChartAreaPainter(datos: lista.take(8).toList()),
        child: Container(),
      ),
    );
  }

  // 5️⃣ RESUMEN POR ÁREA
  Widget _buildResumenPorArea() {
    Map<String, Map<String, int>> resumen = {};

    for (var r in _registrosFiltrados) {
      String area = r['area_entregada']?.toString().trim() ?? 'Sin Área';
      int cant = _pInt(r['cantidad_esntregada']);

      if (!resumen.containsKey(area)) {
        resumen[area] = {'entregas': 0, 'total': 0};
      }
      resumen[area]!['entregas'] = resumen[area]!['entregas']! + 1;
      resumen[area]!['total'] = resumen[area]!['total']! + cant;
    }

    var ordenados = resumen.entries.toList()..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));

    return _buildCardTabla(
      titulo: 'Resumen por Área Entregada',
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.0),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
            children: [
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('ÁREA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('ENTREGAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('ESTIBAS', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            ],
          ),
          ...ordenados.map((e) {
            return TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${e.value['entregas']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${e.value['total']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
              ],
            );
          }),
        ],
      ),
    );
  }

  // 6️⃣ RESUMEN POR TURNO
  Widget _buildResumenPorTurno() {
    Map<String, Map<String, int>> resumen = {};

    for (var r in _registrosFiltrados) {
      String turno = r['turno']?.toString().toUpperCase().trim() ?? 'N/A';
      if (turno.isEmpty) turno = 'N/A';
      int cant = _pInt(r['cantidad_esntregada']);

      if (!resumen.containsKey(turno)) {
        resumen[turno] = {'entregas': 0, 'total': 0};
      }
      resumen[turno]!['entregas'] = resumen[turno]!['entregas']! + 1;
      resumen[turno]!['total'] = resumen[turno]!['total']! + cant;
    }

    var ordenados = resumen.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return _buildCardTabla(
      titulo: 'Resumen por Turno',
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1.2),
          2: FlexColumnWidth(1.2),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
            children: [
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TURNO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('ENTREGAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('ESTIBAS', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            ],
          ),
          ...ordenados.map((e) {
            return TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
                      child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${e.value['entregas']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${e.value['total']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)))),
              ],
            );
          }),
        ],
      ),
    );
  }

  // 7️⃣ DETALLE COMPLETO (INCLUYE BOTÓN DE DESCARGA EN EXCEL)
  Widget _buildDetalleCompleto() {
    return _buildCardTabla(
      titulo: 'Detalle Completo de Entregas',
      height: 420,
      accionHeader: ElevatedButton.icon(
        onPressed: _descargarExcel,
        icon: const Icon(Icons.download_rounded, size: 16),
        label: const Text('Descargar Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981), // Verde Excel
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.1), // FECHA
          1: FlexColumnWidth(0.8), // TURNO
          2: FlexColumnWidth(1.5), // ÁREA
          3: FlexColumnWidth(2.2), // QUIEN RECIBE
          4: FlexColumnWidth(1.0), // CANTIDAD
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
            children: [
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('FECHA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TURNO', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('ÁREA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('QUIEN RECIBE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('CANTIDAD', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            ],
          ),
          ..._registrosFiltrados.take(150).map((r) {
            String fecha = (r['fecha']?.toString() ?? '').split('T')[0];
            String turno = r['turno']?.toString().toUpperCase() ?? 'T1';
            String area = r['area_entregada']?.toString() ?? 'Desconocida';
            String quienRecibe = r['nombre_quien recibe'] ?? r['nombre_quien_recibe'] ?? 'No registrado';
            int cant = _pInt(r['cantidad_esntregada']);

            return TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(fecha, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
                      child: Text(turno, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(area, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(quienRecibe, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$cant', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}

// 📈 PAINTER LÍNEA EVOLUCIÓN
class EvolucionLineChartEntregas extends StatelessWidget {
  final List<Map<String, dynamic>> reportes;
  final DateTime fechaDesde;
  final DateTime fechaHasta;
  final Color colorLinea;

  const EvolucionLineChartEntregas({super.key, required this.reportes, required this.fechaDesde, required this.fechaHasta, required this.colorLinea});

  @override
  Widget build(BuildContext context) {
    Map<int, double> conteoReal = {};

    for (var r in reportes) {
      String? rawFecha = r['fecha']?.toString();
      if (rawFecha != null && rawFecha.length >= 10) {
        DateTime? dt = DateTime.tryParse(rawFecha.substring(0, 10));
        if (dt != null) {
          int cant = int.tryParse(r['cantidad_esntregada']?.toString() ?? '0') ?? 0;
          conteoReal[dt.day] = (conteoReal[dt.day] ?? 0) + cant;
        }
      }
    }

    List<String> labelsX = [];
    List<double> valores = [];

    int totalDias = fechaHasta.difference(fechaDesde).inDays + 1;
    if (totalDias < 1) totalDias = 7;

    for (int i = 0; i < totalDias; i++) {
      DateTime curr = fechaDesde.add(Duration(days: i));
      labelsX.add(curr.day.toString().padLeft(2, '0'));
      valores.add(conteoReal[curr.day] ?? 0);
    }

    if (valores.isEmpty || valores.every((v) => v == 0)) {
      return const SizedBox(height: 240, child: Center(child: Text('Sin datos en el rango', style: TextStyle(fontSize: 13, color: Colors.grey))));
    }

    return SizedBox(
      height: 240,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartEntregasPainter(labelsX: labelsX, valores: valores, colorLinea: colorLinea),
      ),
    );
  }
}

class _LineChartEntregasPainter extends CustomPainter {
  final List<String> labelsX;
  final List<double> valores;
  final Color colorLinea;

  _LineChartEntregasPainter({required this.labelsX, required this.valores, required this.colorLinea});

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;

    double maxVal = valores.reduce(max);
    if (maxVal == 0) maxVal = 50;
    maxVal = maxVal * 1.15;

    double paddingLeft = 40;
    double paddingBottom = 30;
    double paddingTop = 25;
    double height = size.height - paddingBottom - paddingTop;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1.0;

    for (int i = 0; i <= 5; i++) {
      double y = paddingTop + height - (i * (height / 5));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      String label = '${(maxVal / 5 * i).toInt()}';
      TextPainter tp = TextPainter(text: TextSpan(text: label, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(paddingLeft - tp.width - 8, y - 6));
    }

    double stepX = (size.width - paddingLeft) / (valores.length > 1 ? valores.length - 1 : 1);
    List<Offset> points = [];

    for (int i = 0; i < valores.length; i++) {
      double x = paddingLeft + (i * stepX);
      double y = paddingTop + height - ((valores[i] / maxVal) * height);
      points.add(Offset(x, y));

      if (i == 0 || i == valores.length - 1 || i == valores.length ~/ 2) {
        TextPainter tp = TextPainter(text: TextSpan(text: labelsX[i], style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(x - (tp.width / 2), paddingTop + height + 10));
      }
    }

    Path path = Path();
    Path fillPath = Path();

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(points[0].dx, paddingTop + height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      double p0x = points[i].dx, p0y = points[i].dy, p1x = points[i + 1].dx, p1y = points[i + 1].dy;
      double cX1 = p0x + (p1x - p0x) / 2, cY1 = p0y, cX2 = p0x + (p1x - p0x) / 2, cY2 = p1y;
      path.cubicTo(cX1, cY1, cX2, cY2, p1x, p1y);
      fillPath.cubicTo(cX1, cY1, cX2, cY2, p1x, p1y);
    }

    fillPath.lineTo(points.last.dx, paddingTop + height);
    fillPath.close();

    final fillPaint = Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [colorLinea.withOpacity(0.15), colorLinea.withOpacity(0.00)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()..color = colorLinea..strokeWidth = 3.0..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = Colors.white;
    final dotBorder = Paint()..color = colorLinea..style = PaintingStyle.stroke..strokeWidth = 2.0;

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 5, dotPaint);
      canvas.drawCircle(points[i], 5, dotBorder);

      String vTxt = '${valores[i].toInt()}';
      TextPainter tp = TextPainter(text: TextSpan(text: vTxt, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87)), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(points[i].dx - (tp.width / 2), points[i].dy - 18));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 📊 PAINTER BARRAS POR ÁREA
class _BarChartAreaPainter extends CustomPainter {
  final List<MapEntry<String, int>> datos;
  _BarChartAreaPainter({required this.datos});

  @override
  void paint(Canvas canvas, Size size) {
    if (datos.isEmpty) return;

    double maxVal = datos.map((e) => e.value.toDouble()).reduce(max);
    if (maxVal == 0) maxVal = 10;
    maxVal = maxVal * 1.2;

    double paddingLeft = 30;
    double paddingBottom = 65;
    double paddingTop = 25;
    double height = size.height - paddingBottom - paddingTop;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1.0;

    for (int i = 0; i <= 5; i++) {
      double y = paddingTop + height - (i * (height / 5));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      TextPainter tp = TextPainter(text: TextSpan(text: '${(maxVal / 5 * i).toInt()}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))), textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(5, y - 6));
    }

    double stepX = (size.width - paddingLeft) / datos.length;
    double barWidth = stepX * 0.5;
    if (barWidth > 45) barWidth = 45;

    final barPaint = Paint()..color = const Color(0xFF3B82F6);

    for (int i = 0; i < datos.length; i++) {
      double x = paddingLeft + (i * stepX) + (stepX / 2) - (barWidth / 2);
      double barH = (datos[i].value / maxVal) * height;
      double y = paddingTop + height - barH;

      canvas.drawRect(Rect.fromLTWH(x, y, barWidth, barH), barPaint);

      TextPainter tpVal = TextPainter(text: TextSpan(text: '${datos[i].value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)), textDirection: TextDirection.ltr);
      tpVal.layout();
      tpVal.paint(canvas, Offset(x + (barWidth / 2) - (tpVal.width / 2), y - 18));

      canvas.save();
      canvas.translate(x + (barWidth / 2), paddingTop + height + 8);
      canvas.rotate(-pi / 4);

      String shortName = datos[i].key;
      if (shortName.length > 15) shortName = '${shortName.substring(0, 13)}...';

      TextPainter tpName = TextPainter(text: TextSpan(text: shortName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))), textDirection: TextDirection.ltr, maxLines: 1);
      tpName.layout();
      tpName.paint(canvas, Offset(-tpName.width, 0));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}