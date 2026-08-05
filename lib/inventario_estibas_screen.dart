import 'dart:convert';
import 'dart:math';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';

class InventarioEstibasScreen extends StatefulWidget {
  final Map<String, dynamic>? datosEmpleado;
  const InventarioEstibasScreen({super.key, this.datosEmpleado});

  @override
  State<InventarioEstibasScreen> createState() => _InventarioEstibasScreenState();
}

class _InventarioEstibasScreenState extends State<InventarioEstibasScreen> {
  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todosLosRegistros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  DateTime _fechaDesde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _fechaHasta = DateTime.now();

  String _turnoSel = 'Todos';
  String _responsableSel = 'Todos';

  final List<String> _listaTurnos = ['Todos', 'T1', 'T2', 'T3'];
  List<String> _listaResponsables = ['Todos'];

  // KPIs
  int _totalTipoA = 0;
  int _totalTipoB = 0;
  int _totalTipoC = 0;
  int _totalGuacales = 0;

  int _capTipoA = 0;
  int _capTipoB = 0;
  int _capTipoC = 0;

  // 📌 INFORMACIÓN DEL ÚLTIMO REPORTE
  String _ultimaFechaReporte = 'N/A';
  String _ultimoTurnoReporte = 'N/A';
  String _ultimoResponsableReporte = 'N/A';

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
      final List<dynamic> dataCompleta = await ApiService.consultar('estibas', 'inventario_estibas');

      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> respTemp = {'Todos'};

      for (var fila in dataCompleta) {
        if (fila is Map) {
          final Map<String, dynamic> mapa = {};
          fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
          datosProcesados.add(mapa);

          String resp = (mapa['responsable']?.toString().trim() ?? '');
          if (resp.isNotEmpty && resp != 'null' && resp != 'N/A') {
            respTemp.add(resp);
          }
        }
      }

      // Ordenar por ID descendente (el más reciente primero)
      datosProcesados.sort((a, b) => _pInt(b['id']).compareTo(_pInt(a['id'])));

      setState(() {
        _todosLosRegistros = datosProcesados;
        _listaResponsables = respTemp.toList()..sort();
        _aplicarFiltros();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error de conexión en Inventario Estibas: $e');
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
        String? rawFecha = row['fecha']?.toString() ?? row['fecha_de_reporte']?.toString();
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

        if (_responsableSel != 'Todos') {
          String respFila = row['responsable']?.toString().trim() ?? '';
          if (respFila != _responsableSel) return false;
        }

        return true;
      }).toList();

      _calcularKpis();
    });
  }

  // ⏱️ OBTENER DATOS Y METADATOS DEL ÚLTIMO REPORTE VÁLIDO
  void _calcularKpis() {
    if (_registrosFiltrados.isEmpty) {
      _totalTipoA = 0; _totalTipoB = 0; _totalTipoC = 0; _totalGuacales = 0;
      _capTipoA = 0; _capTipoB = 0; _capTipoC = 0;
      _ultimaFechaReporte = 'N/A';
      _ultimoTurnoReporte = 'N/A';
      _ultimoResponsableReporte = 'N/A';
      return;
    }

    Map<String, dynamic> ultimoValido = _registrosFiltrados.firstWhere(
          (r) => (_pInt(r['total_tipo_a']) + _pInt(r['total_tipo_b']) + _pInt(r['total_tipo_c']) + _pInt(r['guacales'])) > 0,
      orElse: () => _registrosFiltrados.first,
    );

    _totalTipoA = _pInt(ultimoValido['total_tipo_a']);
    _capTipoA = _pInt(ultimoValido['capacidad_tipoa']);

    _totalTipoB = _pInt(ultimoValido['total_tipo_b']);
    _capTipoB = _pInt(ultimoValido['capacidad_tipo_b']);

    _totalTipoC = _pInt(ultimoValido['total_tipo_c']);
    _capTipoC = _pInt(ultimoValido['capacidad_tipo_c']);

    _totalGuacales = _pInt(ultimoValido['guacales']);

    // Extraer metadata del reporte cargado
    String rawF = (ultimoValido['fecha']?.toString() ?? ultimoValido['fecha_de_reporte']?.toString() ?? '').split('T')[0];
    _ultimaFechaReporte = rawF.isNotEmpty ? rawF : 'N/A';
    _ultimoTurnoReporte = ultimoValido['turno']?.toString().toUpperCase().trim() ?? 'N/A';
    _ultimoResponsableReporte = ultimoValido['responsable']?.toString().trim() ?? 'N/A';
  }

  void _descargarExcel() {
    if (_registrosFiltrados.isEmpty) {
      _mostrarMensaje('No hay registros para exportar', esError: true);
      return;
    }

    try {
      final StringBuffer csvBuilder = StringBuffer();
      csvBuilder.write('\uFEFF'); // BOM UTF-8

      csvBuilder.writeln('FECHA;TURNO;RESPONSABLE;TIPO A;CAPACIDAD A;TIPO B;CAPACIDAD B;TIPO C;CAPACIDAD C;GUACALES');

      for (var r in _registrosFiltrados) {
        String fecha = (r['fecha']?.toString() ?? r['fecha_de_reporte']?.toString() ?? '').split('T')[0];
        String turno = r['turno']?.toString().toUpperCase() ?? 'T1';
        String resp = (r['responsable']?.toString() ?? 'Sin responsable').replaceAll(';', ',');

        int tA = _pInt(r['total_tipo_a']);
        int cA = _pInt(r['capacidad_tipoa']);
        int tB = _pInt(r['total_tipo_b']);
        int cB = _pInt(r['capacidad_tipo_b']);
        int tC = _pInt(r['total_tipo_c']);
        int cC = _pInt(r['capacidad_tipo_c']);
        int gua = _pInt(r['guacales']);

        csvBuilder.writeln('$fecha;$turno;$resp;$tA;$cA;$tB;$cB;$tC;$cC;$gua');
      }

      if (kIsWeb) {
        final bytes = utf8.encode(csvBuilder.toString());
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final fechaStr = DateTime.now().toString().substring(0, 10);

        html.AnchorElement(href: url)
          ..setAttribute("download", "Inventario_Estibas_$fechaStr.csv")
          ..click();

        html.Url.revokeObjectUrl(url);
        _mostrarMensaje('Archivo Excel descargado con éxito');
      } else {
        _mostrarMensaje('Descarga disponible en versión Web');
      }
    } catch (e) {
      _mostrarMensaje('Error al exportar: $e', esError: true);
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
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1))),
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
            const SizedBox(height: 15),

            // 📌 INFORMACIÓN DEL ÚLTIMO REPORTE AUTOMÁTICO
            _buildInfoUltimoReporte(),
            const SizedBox(height: 15),

            _buildTarjetasKPI(),
            const SizedBox(height: 20),

            // 📈 3 GRÁFICAS DE LÍNEA DE % DE OCUPACIÓN
            Row(
              children: [
                Expanded(
                  child: _buildCardGrafico(
                    titulo: '% Ocupación - Tipo A',
                    child: EvolucionLineChartPorcentaje(
                      reportes: _registrosFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                      campoTotal: 'total_tipo_a',
                      campoCap: 'capacidad_tipoa',
                      colorLinea: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildCardGrafico(
                    titulo: '% Ocupación - Tipo B',
                    child: EvolucionLineChartPorcentaje(
                      reportes: _registrosFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                      campoTotal: 'total_tipo_b',
                      campoCap: 'capacidad_tipo_b',
                      colorLinea: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildCardGrafico(
                    titulo: '% Ocupación - Tipo C',
                    child: EvolucionLineChartPorcentaje(
                      reportes: _registrosFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                      campoTotal: 'total_tipo_c',
                      campoCap: 'capacidad_tipo_c',
                      colorLinea: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 📊 GRÁFICO DE BARRAS CON EL TOTAL DE CADA TIPO
            _buildCardGrafico(
              titulo: 'Total Registrado por Tipo de Estiba',
              child: _buildGraficoBarrasTotales(),
            ),
            const SizedBox(height: 20),

            // 📋 DETALLE COMPLETO
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
          Expanded(child: _buildFiltroDropdown('RESPONSABLE', _responsableSel, _listaResponsables, (v) => setState(() => _responsableSel = v!))),
          const SizedBox(width: 20),

          ElevatedButton.icon(
            onPressed: _aplicarFiltros,
            icon: const Icon(Icons.filter_alt_rounded, size: 16),
            label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
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

  // 📌 WIDGET CON LA FECHA Y TURNO AUTOMÁTICOS DEL ÚLTIMO REPORTE
  Widget _buildInfoUltimoReporte() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1).withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF0D47A1).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 18, color: Color(0xFF0D47A1)),
          const SizedBox(width: 8),
          const Text('ÚLTIMO REPORTE REGISTRADO:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF0D47A1), letterSpacing: 0.5)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
            child: Text('Fecha: $_ultimaFechaReporte', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFF0D47A1), borderRadius: BorderRadius.circular(4)),
            child: Text('Turno: $_ultimoTurnoReporte', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          if (_ultimoResponsableReporte != 'N/A') ...[
            const SizedBox(width: 8),
            Text('Resp: $_ultimoResponsableReporte', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
          ]
        ],
      ),
    );
  }

  // 2️⃣ TARJETAS KPI
  Widget _buildTarjetasKPI() {
    return Row(
      children: [
        Expanded(child: _buildKPICardConCapacidad('TIPO A', _totalTipoA, _capTipoA, const Color(0xFF2563EB))),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICardConCapacidad('TIPO B', _totalTipoB, _capTipoB, const Color(0xFF10B981))),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICardConCapacidad('TIPO C', _totalTipoC, _capTipoC, const Color(0xFFF59E0B))),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICardSimple('GUACALES', '$_totalGuacales', const Color(0xFF8B5CF6))),
      ],
    );
  }

  Widget _buildKPICardConCapacidad(String titulo, int total, int capacidad, Color colorBorde) {
    bool esMenor = total <= capacidad;
    Color colorValor = esMenor ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(width: 5, height: 50, decoration: BoxDecoration(color: colorBorde, borderRadius: BorderRadius.circular(10))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF78909C), letterSpacing: 0.5)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                      children: [
                        TextSpan(text: '$capacidad / ', style: const TextStyle(color: Colors.black87)),
                        TextSpan(text: '$total', style: TextStyle(color: colorValor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICardSimple(String titulo, String valor, Color colorBorde) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(width: 5, height: 50, decoration: BoxDecoration(color: colorBorde, borderRadius: BorderRadius.circular(10))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF78909C), letterSpacing: 0.5)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(valor, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3️⃣ CONTENEDOR BASE DE GRÁFICAS
  Widget _buildCardGrafico({required String titulo, required Widget child}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
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

  // 4️⃣ GRÁFICO DE BARRAS DE TOTALES
  Widget _buildGraficoBarrasTotales() {
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarChartTotalesPainter(
          totalA: _totalTipoA,
          totalB: _totalTipoB,
          totalC: _totalTipoC,
          guacales: _totalGuacales,
        ),
        child: Container(),
      ),
    );
  }

  // 5️⃣ TABLA DETALLE COMPLETO
  Widget _buildDetalleCompleto() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Detalle del Inventario de Estibas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                ElevatedButton.icon(
                  onPressed: _descargarExcel,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Descargar Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          SizedBox(
            height: 380,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.0), // FECHA
                  1: FlexColumnWidth(0.7), // TURNO
                  2: FlexColumnWidth(1.8), // RESPONSABLE
                  3: FlexColumnWidth(1.0), // TIPO A
                  4: FlexColumnWidth(1.0), // TIPO B
                  5: FlexColumnWidth(1.0), // TIPO C
                  6: FlexColumnWidth(1.0), // GUACALES
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
                    children: [
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('FECHA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TURNO', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('RESPONSABLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TIPO A', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TIPO B', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TIPO C', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.only(bottom: 12), child: Text('GUACALES', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
                    ],
                  ),
                  ..._registrosFiltrados.take(150).map((r) {
                    String fecha = (r['fecha']?.toString() ?? r['fecha_de_reporte']?.toString() ?? '').split('T')[0];
                    String turno = r['turno']?.toString().toUpperCase() ?? 'T1';
                    String resp = r['responsable']?.toString() ?? 'N/A';

                    return TableRow(
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(fecha, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87))),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Align(
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
                              child: Text(turno, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
                            ),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(resp, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${_pInt(r['total_tipo_a'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${_pInt(r['total_tipo_b'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${_pInt(r['total_tipo_c'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${_pInt(r['guacales'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)))),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
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

// 📈 WIDGET DE LÍNEA PARA % DE OCUPACIÓN (LÍNEA NEGRA, ETIQUETA VERDE/ROJA)
class EvolucionLineChartPorcentaje extends StatelessWidget {
  final List<Map<String, dynamic>> reportes;
  final DateTime fechaDesde;
  final DateTime fechaHasta;
  final String campoTotal;
  final String campoCap;
  final Color colorLinea;

  const EvolucionLineChartPorcentaje({
    super.key,
    required this.reportes,
    required this.fechaDesde,
    required this.fechaHasta,
    required this.campoTotal,
    required this.campoCap,
    required this.colorLinea,
  });

  @override
  Widget build(BuildContext context) {
    Map<int, double> porcentajePorDia = {};

    for (var r in reportes) {
      String? rawFecha = r['fecha']?.toString() ?? r['fecha_de_reporte']?.toString();
      if (rawFecha != null && rawFecha.length >= 10) {
        DateTime? dt = DateTime.tryParse(rawFecha.substring(0, 10));
        if (dt != null) {
          double total = double.tryParse(r[campoTotal]?.toString() ?? '0') ?? 0;
          double cap = double.tryParse(r[campoCap]?.toString() ?? '0') ?? 0;
          double pct = cap > 0 ? ((total / cap) * 100) : 0;

          if (!porcentajePorDia.containsKey(dt.day) || total > 0) {
            porcentajePorDia[dt.day] = pct;
          }
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
      valores.add(porcentajePorDia[curr.day] ?? 0);
    }

    return SizedBox(
      height: 200,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartPorcentajePainter(labelsX: labelsX, valores: valores, colorLinea: colorLinea),
      ),
    );
  }
}

class _LineChartPorcentajePainter extends CustomPainter {
  final List<String> labelsX;
  final List<double> valores;
  final Color colorLinea;

  _LineChartPorcentajePainter({required this.labelsX, required this.valores, required this.colorLinea});

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;

    double maxVal = 100.0;
    double paddingLeft = 35;
    double paddingBottom = 30;
    double paddingTop = 20;
    double height = size.height - paddingBottom - paddingTop;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      double y = paddingTop + height - (i * (height / 4));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      TextPainter tp = TextPainter(
        text: TextSpan(text: '${i * 25}%', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(paddingLeft - tp.width - 4, y - 6));
    }

    double stepX = (size.width - paddingLeft) / (valores.length > 1 ? valores.length - 1 : 1);
    List<Offset> points = [];

    for (int i = 0; i < valores.length; i++) {
      double x = paddingLeft + (i * stepX);
      double valClamped = valores[i].clamp(0, 100);
      double y = paddingTop + height - ((valClamped / maxVal) * height);
      points.add(Offset(x, y));

      if (i == 0 || i == valores.length - 1 || i == valores.length ~/ 2) {
        TextPainter tp = TextPainter(
          text: TextSpan(text: labelsX[i], style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x - (tp.width / 2), paddingTop + height + 8));
      }
    }

    Path path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      double p0x = points[i].dx, p0y = points[i].dy, p1x = points[i + 1].dx, p1y = points[i + 1].dy;
      double cX1 = p0x + (p1x - p0x) / 2, cY1 = p0y, cX2 = p0x + (p1x - p0x) / 2, cY2 = p1y;
      path.cubicTo(cX1, cY1, cX2, cY2, p1x, p1y);
    }

    final linePaint = Paint()..color = colorLinea..strokeWidth = 2.5..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = Colors.white;
    final dotBorder = Paint()..color = colorLinea..style = PaintingStyle.stroke..strokeWidth = 2.0;

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, dotPaint);
      canvas.drawCircle(points[i], 4, dotBorder);

      Color colorTexto = valores[i] <= 100.0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

      TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${valores[i].toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorTexto),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(points[i].dx - (tp.width / 2), points[i].dy - 16));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 📊 BARRAS DE TOTALES (A, B, C, GUACALES)
class _BarChartTotalesPainter extends CustomPainter {
  final int totalA, totalB, totalC, guacales;

  _BarChartTotalesPainter({
    required this.totalA,
    required this.totalB,
    required this.totalC,
    required this.guacales,
  });

  @override
  void paint(Canvas canvas, Size size) {
    List<Map<String, dynamic>> items = [
      {'label': 'Tipo A', 'valor': totalA, 'color': const Color(0xFF2563EB)},
      {'label': 'Tipo B', 'valor': totalB, 'color': const Color(0xFF10B981)},
      {'label': 'Tipo C', 'valor': totalC, 'color': const Color(0xFFF59E0B)},
      {'label': 'Guacales', 'valor': guacales, 'color': const Color(0xFF8B5CF6)},
    ];

    double maxVal = [totalA, totalB, totalC, guacales].map((e) => e.toDouble()).reduce(max);
    if (maxVal == 0) maxVal = 100;
    maxVal = maxVal * 1.2;

    double paddingLeft = 40;
    double paddingBottom = 35;
    double paddingTop = 25;
    double height = size.height - paddingBottom - paddingTop;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      double y = paddingTop + height - (i * (height / 4));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      TextPainter tp = TextPainter(
        text: TextSpan(text: '${(maxVal / 4 * i).toInt()}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(5, y - 6));
    }

    double groupWidth = (size.width - paddingLeft) / items.length;
    double barWidth = 35;

    for (int i = 0; i < items.length; i++) {
      double centerX = paddingLeft + (i * groupWidth) + (groupWidth / 2);

      double hBar = (items[i]['valor'] / maxVal) * height;
      double yBar = paddingTop + height - hBar;

      Rect rectBar = Rect.fromLTWH(centerX - (barWidth / 2), yBar, barWidth, hBar);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rectBar, const Radius.circular(4)),
        Paint()..color = items[i]['color'],
      );

      TextPainter tpVal = TextPainter(
        text: TextSpan(text: '${items[i]['valor']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        textDirection: TextDirection.ltr,
      );
      tpVal.layout();
      tpVal.paint(canvas, Offset(centerX - (tpVal.width / 2), yBar - 18));

      TextPainter tpLbl = TextPainter(
        text: TextSpan(text: items[i]['label'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        textDirection: TextDirection.ltr,
      );
      tpLbl.layout();
      tpLbl.paint(canvas, Offset(centerX - (tpLbl.width / 2), paddingTop + height + 8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}