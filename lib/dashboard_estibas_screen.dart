import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'api_service.dart'; // Asegúrate de que la ruta sea correcta según tu proyecto

class DashboardEstibasScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;
  final Map<String, dynamic>? datosEmpleado;

  const DashboardEstibasScreen({super.key, this.onToggleSidebar, this.datosEmpleado});

  @override
  State<DashboardEstibasScreen> createState() => _DashboardEstibasScreenState();
}

class _DashboardEstibasScreenState extends State<DashboardEstibasScreen> {
  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todosLosRegistros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  DateTime _fechaDesde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _fechaHasta = DateTime.now();

  String _turnoSel = 'Todos';
  String _supervisorSel = 'Todos';

  final List<String> _listaTurnos = ['Todos', 'T1', 'T2', 'T3'];
  List<String> _listaSupervisores = ['Todos'];

  // KPIs
  int _totalA = 0;
  int _totalRep = 0;
  int _totalC = 0;
  int _totalMeta = 0;
  double _prodGlobal = 0.0;
  double _pctTipoC = 0.0;

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
      final List<dynamic> dataCompleta = await ApiService.consultar('estibas', 'reparacion_estibas');

      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> supervisoresTemp = {'Todos'};

      for (var fila in dataCompleta) {
        if (fila is Map) {
          final Map<String, dynamic> mapa = {};
          fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
          datosProcesados.add(mapa);

          String sup = (mapa['supervisor']?.toString().toUpperCase().trim() ?? '');
          if (sup.isNotEmpty && sup != 'NULL' && sup != 'N/A') {
            supervisoresTemp.add(sup);
          }
        }
      }

      setState(() {
        _todosLosRegistros = datosProcesados;
        _listaSupervisores = supervisoresTemp.toList()..sort();
        _aplicarFiltros();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error de conexión en Dashboard Estibas: $e');
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

        if (_supervisorSel != 'Todos') {
          String supFila = row['supervisor']?.toString().toUpperCase().trim() ?? '';
          if (supFila != _supervisorSel) return false;
        }

        return true;
      }).toList();

      _calcularKpis();
    });
  }

  void _calcularKpis() {
    _totalA = 0;
    _totalRep = 0;
    _totalC = 0;
    _totalMeta = 0;

    for (var row in _registrosFiltrados) {
      _totalA += _pInt(row['clasificadas'] ?? row['tipo_a']);
      _totalRep += _pInt(row['reparadas']);
      _totalC += _pInt(row['tipo_c']);

      int metaRow = _pInt(row['meta']);
      _totalMeta += metaRow > 0 ? metaRow : 0;
    }

    int produccion = _totalA + _totalRep;
    _prodGlobal = _totalMeta > 0 ? (produccion / _totalMeta) * 100 : 0.0;

    int granTotal = produccion + _totalC;
    _pctTipoC = granTotal > 0 ? (_totalC / granTotal) * 100 : 0.0;
  }

  // ===========================================================================
  // 🔨 LAYOUT PRINCIPAL
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(backgroundColor: Color(0xFFF4F6F9), body: Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))));
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

            // 📈 GRÁFICAS DE LÍNEAS
            Row(
              children: [
                Expanded(
                  child: _buildCardGrafico(
                    titulo: 'Evolución Productividad Diaria (%)',
                    child: EvolucionLineChart(
                      reportes: _registrosFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                      isPorcentaje: true,
                      colorLinea: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildCardGrafico(
                    titulo: 'Producción Diaria (Clasificadas + Rep)',
                    child: EvolucionLineChart(
                      reportes: _registrosFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                      isPorcentaje: false,
                      colorLinea: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 📊 RESUMEN TURNO Y PRODUCTIVIDAD SUPERVISOR
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildResumenTurno()),
                const SizedBox(width: 20),
                Expanded(child: _buildProductividadSupervisor()),
              ],
            ),
            const SizedBox(height: 20),

            // 🍩 CAUSALES Y TOP OPERARIOS
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildCausalesDonut()),
                const SizedBox(width: 20),
                Expanded(child: _buildTopProductivos()),
              ],
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
          Expanded(child: _buildFiltroDropdown('SUPERVISOR', _supervisorSel, _listaSupervisores, (v) => setState(() => _supervisorSel = v!))),
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

  // 2️⃣ TARJETAS KPI (Números aumentados a 34)
  Widget _buildTarjetasKPI() {
    Color colorProd = _prodGlobal >= 100 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Row(
      children: [
        Expanded(child: _buildKPICard('CLASIFICADAS', '$_totalA', const Color(0xFF3B82F6), Colors.black87)),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICard('REPARADAS', '$_totalRep', const Color(0xFF3B82F6), Colors.black87)),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICard('TIPO C', '$_totalC', const Color(0xFFF59E0B), Colors.black87)),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICard('META', '$_totalMeta', const Color(0xFFF59E0B), Colors.black87)),
        const SizedBox(width: 15),
        Expanded(child: _buildKPICard('PRODUCTIVIDAD', '${_prodGlobal.toStringAsFixed(1)}%', colorProd, colorProd)),
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
                  // TAMAÑO AUMENTADO AQUI (34)
                  child: Text(valor, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: colorTexto)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3️⃣ ESTRUCTURA BASE DE TARJETAS
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

  Widget _buildCardTabla({required String titulo, required Widget child, double height = 320}) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
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

  // 4️⃣ RESUMEN POR TURNO
  Widget _buildResumenTurno() {
    Map<String, Map<String, dynamic>> resumen = {};

    for (var r in _registrosFiltrados) {
      String t = r['turno']?.toString().trim().toUpperCase() ?? 'N/A';
      if (t.isEmpty) t = 'N/A';

      int a = _pInt(r['clasificadas'] ?? r['tipo_a']);
      int rep = _pInt(r['reparadas']);
      int c = _pInt(r['tipo_c']);
      int meta = _pInt(r['meta']);

      if (!resumen.containsKey(t)) {
        resumen[t] = {'a': 0, 'rep': 0, 'c': 0, 'meta': 0};
      }
      resumen[t]!['a'] += a;
      resumen[t]!['rep'] += rep;
      resumen[t]!['c'] += c;
      resumen[t]!['meta'] += meta > 0 ? meta : 0;
    }

    var ordenados = resumen.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return _buildCardTabla(
      titulo: 'Resumen por Turno',
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.0),
          1: FlexColumnWidth(1.4),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.0),
          4: FlexColumnWidth(1.5),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
            children: [
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TURNO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('CLASIFICADAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('REPARADAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TIPO C', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('PRODUCTIVIDAD', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            ],
          ),
          ...ordenados.map((e) {
            int a = e.value['a'];
            int rep = e.value['rep'];
            int c = e.value['c'];
            int meta = e.value['meta'];
            double pct = meta > 0 ? ((a + rep) / meta) * 100 : 0.0;
            Color colorPct = pct >= 100 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

            return TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
                      child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569))),
                    ),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$a', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$rep', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$c', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('${pct.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorPct))),
              ],
            );
          }),
        ],
      ),
    );
  }

  // 5️⃣ PRODUCTIVIDAD SUPERVISOR
  Widget _buildProductividadSupervisor() {
    Map<String, int> metaSup = {};
    Map<String, int> realSup = {};
    for (var r in _registrosFiltrados) {
      String s = (r['supervisor']?.toString() ?? 'SIN ASIGNAR').toUpperCase().trim();
      realSup[s] = (realSup[s] ?? 0) + _pInt(r['clasificadas'] ?? r['tipo_a']) + _pInt(r['reparadas']);
      int m = _pInt(r['meta']);
      metaSup[s] = (metaSup[s] ?? 0) + (m > 0 ? m : 0);
    }

    List<MapEntry<String, double>> pctList = [];
    for (var k in realSup.keys) {
      double pct = metaSup[k]! > 0 ? (realSup[k]! / metaSup[k]!) * 100 : 0.0;
      pctList.add(MapEntry(k, pct));
    }

    return _buildCardTabla(
      titulo: 'Productividad por Supervisor',
      child: SizedBox(
        height: 200,
        child: CustomPaint(
          painter: _BarChartPainter(datos: pctList),
          child: Container(),
        ),
      ),
    );
  }

  // 6️⃣ CAUSALES DONUT CHART
  Widget _buildCausalesDonut() {
    Map<String, double> mapa = {};
    for (var r in _registrosFiltrados) {
      String c = (r['causal'] ?? r['causal_tipo_c'] ?? '').toString().trim().toUpperCase();
      int tc = _pInt(r['tipo_c']);

      if (c.isNotEmpty && !c.contains('NINGUN') && c != 'N/A' && c != 'NULL') {
        mapa[c] = (mapa[c] ?? 0) + (tc > 0 ? tc : 1);
      }
    }

    return _buildCardTabla(
      titulo: 'Causales (%)',
      child: SizedBox(
        height: 200,
        child: DonutChartWidget(
          datos: mapa,
          colores: const [Color(0xFF4285F4), Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF9C27B0)],
        ),
      ),
    );
  }

  // 7️⃣ TOP 5 PRODUCTIVOS
  Widget _buildTopProductivos() {
    Map<String, Map<String, dynamic>> ops = {};

    for (var r in _registrosFiltrados) {
      String op = (r['operario']?.toString() ?? 'DESCONOCIDO').toUpperCase().trim();
      int rep = _pInt(r['reparadas']);
      int meta = _pInt(r['meta']);

      if (!ops.containsKey(op)) {
        ops[op] = {'rep': 0, 'meta': 0};
      }
      ops[op]!['rep'] += rep;
      ops[op]!['meta'] += meta > 0 ? meta : 0;
    }

    var ordenados = ops.entries.toList()..sort((a, b) {
      double pctA = a.value['meta'] > 0 ? (a.value['rep'] / a.value['meta']) * 100 : 0.0;
      double pctB = b.value['meta'] > 0 ? (b.value['rep'] / b.value['meta']) * 100 : 0.0;
      return pctB.compareTo(pctA);
    });

    return _buildCardTabla(
      titulo: 'Top 5 - Productivos',
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.5),
          1: FlexColumnWidth(1.0),
          2: FlexColumnWidth(1.0),
          3: FlexColumnWidth(1.0),
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
            children: [
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('OPERARIO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('META', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('REP', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('%', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            ],
          ),
          ...ordenados.take(5).map((e) {
            int rep = e.value['rep'];
            int meta = e.value['meta'];
            double pct = meta > 0 ? (rep / meta) * 100 : 0.0;
            Color colorPct = pct >= 100 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

            return TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$meta', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$rep', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('${pct.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorPct))),
              ],
            );
          }),
        ],
      ),
    );
  }

  // 8️⃣ DETALLE COMPLETO
  Widget _buildDetalleCompleto() {
    return _buildCardTabla(
      titulo: 'Detalle Completo',
      height: 450,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.1), // FECHA
          1: FlexColumnWidth(2.0), // OPERARIO
          2: FlexColumnWidth(1.5), // SUPERVISOR
          3: FlexColumnWidth(1.2), // CAUSAL
          4: FlexColumnWidth(0.8), // TURNO
          5: FlexColumnWidth(1.3), // CLASIFICADAS
          6: FlexColumnWidth(1.1), // REPARADAS
          7: FlexColumnWidth(1.0), // TIPO C
          8: FlexColumnWidth(1.0), // META
          9: FlexColumnWidth(1.4), // PRODUCTIVIDAD
        },
        children: [
          const TableRow(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 2))),
            children: [
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('FECHA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('OPERARIO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('SUPERVISOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('CAUSAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TURNO', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('CLASIFICADAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('REPARADAS', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('TIPO C', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('META', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
              Padding(padding: EdgeInsets.only(bottom: 12), child: Text('PRODUCTIVIDAD', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))),
            ],
          ),
          ..._registrosFiltrados.take(150).map((r) {
            String fecha = (r['fecha']?.toString() ?? '').split('T')[0];
            String op = (r['operario']?.toString() ?? 'DESCONOCIDO').toUpperCase();
            String supRaw = (r['supervisor']?.toString() ?? 'SIN ASIGNAR').toUpperCase();

            String causal = r['causal']?.toString() ?? r['causal_tipo_c']?.toString() ?? 'Ninguna';
            if (causal.trim().isEmpty || causal.toUpperCase() == 'NULL') causal = 'Ninguna';
            String turno = r['turno']?.toString().toUpperCase() ?? 'T1';

            int a = _pInt(r['clasificadas'] ?? r['tipo_a']);
            int rep = _pInt(r['reparadas']);
            int c = _pInt(r['tipo_c']);
            int meta = _pInt(r['meta']);

            double prodPct = meta > 0 ? ((a + rep) / meta) * 100 : 0.0;
            Color colorProd = prodPct >= 100 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

            String supervisorLabel = prodPct >= 100 ? supRaw : '---';

            return TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF8FAFC)))),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(fecha, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(op, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(supervisorLabel, style: TextStyle(fontSize: 12, fontWeight: prodPct >= 100 ? FontWeight.bold : FontWeight.normal, color: prodPct >= 100 ? const Color(0xFF2563EB) : Colors.grey))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(causal, style: const TextStyle(fontSize: 13, color: Colors.grey))),
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
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$a', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$rep', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$c', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('$meta', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('${prodPct.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorProd))),
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

// ===========================================================================
// 📈 GRÁFICOS PERSONALIZADOS
// ===========================================================================

class EvolucionLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> reportes;
  final DateTime fechaDesde;
  final DateTime fechaHasta;
  final bool isPorcentaje;
  final Color colorLinea;

  const EvolucionLineChart({super.key, required this.reportes, required this.fechaDesde, required this.fechaHasta, required this.isPorcentaje, required this.colorLinea});

  @override
  Widget build(BuildContext context) {
    Map<int, double> conteoReal = {};
    Map<int, double> conteoMeta = {};

    for (var r in reportes) {
      String? rawFecha = r['fecha']?.toString();
      if (rawFecha != null && rawFecha.length >= 10) {
        DateTime? dt = DateTime.tryParse(rawFecha.substring(0, 10));
        if (dt != null) {
          int cl = int.tryParse(r['clasificadas']?.toString() ?? r['tipo_a']?.toString() ?? '0') ?? 0;
          int rp = int.tryParse(r['reparadas']?.toString() ?? '0') ?? 0;
          int mt = int.tryParse(r['meta']?.toString() ?? '0') ?? 0;

          conteoReal[dt.day] = (conteoReal[dt.day] ?? 0) + (cl + rp);
          conteoMeta[dt.day] = (conteoMeta[dt.day] ?? 0) + mt;
        }
      }
    }

    List<String> labelsX = [];
    List<double> valores = [];
    List<bool> llegoAMeta = [];

    int totalDias = fechaHasta.difference(fechaDesde).inDays + 1;
    if (totalDias < 1) totalDias = 7;

    for (int i = 0; i < totalDias; i++) {
      DateTime curr = fechaDesde.add(Duration(days: i));
      labelsX.add('${curr.year}-${curr.month.toString().padLeft(2, '0')}-${curr.day.toString().padLeft(2, '0')}');

      double real = conteoReal[curr.day] ?? 0;
      double meta = conteoMeta[curr.day] ?? 0;

      if (isPorcentaje) {
        double pct = meta > 0 ? (real / meta) * 100 : 0.0;
        valores.add(pct);
        llegoAMeta.add(pct >= 100);
      } else {
        valores.add(real);
        llegoAMeta.add(real >= meta && meta > 0);
      }
    }

    if (valores.isEmpty || valores.every((v) => v == 0)) {
      return const SizedBox(height: 240, child: Center(child: Text('Sin datos en el rango', style: TextStyle(fontSize: 13, color: Colors.grey))));
    }

    return SizedBox(
      height: 240,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartPainter(labelsX: labelsX, valores: valores, metasCumplidas: llegoAMeta, colorLinea: colorLinea, isPorcentaje: isPorcentaje),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<String> labelsX;
  final List<double> valores;
  final List<bool> metasCumplidas;
  final Color colorLinea;
  final bool isPorcentaje;

  _LineChartPainter({required this.labelsX, required this.valores, required this.metasCumplidas, required this.colorLinea, required this.isPorcentaje});

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;

    double maxVal = valores.reduce(max);
    if (isPorcentaje && maxVal < 100) maxVal = 120;
    if (!isPorcentaje && maxVal == 0) maxVal = 100;
    maxVal = maxVal * 1.15;

    double paddingLeft = 40;
    double paddingBottom = 30;
    double paddingTop = 25;
    double height = size.height - paddingBottom - paddingTop;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1.0;

    for (int i = 0; i <= 6; i++) {
      double y = paddingTop + height - (i * (height / 6));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      String label = '${(maxVal / 6 * i).toInt()}';
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
      if (valores[i] > 0 || isPorcentaje) {
        canvas.drawCircle(points[i], 5, dotPaint);
        canvas.drawCircle(points[i], 5, dotBorder);

        String vTxt = isPorcentaje ? '${valores[i].toStringAsFixed(1)}%' : '${valores[i].toInt()}';
        Color labelColor = metasCumplidas[i] ? const Color(0xFF10B981) : const Color(0xFFEF4444);

        // ETIQUETAS MÁS GRANDES (fontSize: 13)
        TextPainter tp = TextPainter(text: TextSpan(text: vTxt, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: labelColor)), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(points[i].dx - (tp.width / 2), points[i].dy - 18));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 📊 BAR CHART SUPERVISOR
class _BarChartPainter extends CustomPainter {
  final List<MapEntry<String, double>> datos;
  _BarChartPainter({required this.datos});

  @override
  void paint(Canvas canvas, Size size) {
    if (datos.isEmpty) return;

    double maxVal = datos.map((e) => e.value).reduce(max);
    if (maxVal < 14) maxVal = 14;
    maxVal = maxVal * 1.2;

    double paddingLeft = 30;
    double paddingBottom = 85;
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
    if (barWidth > 60) barWidth = 60;

    for (int i = 0; i < datos.length; i++) {
      double x = paddingLeft + (i * stepX) + (stepX / 2) - (barWidth / 2);
      double barH = (datos[i].value / maxVal) * height;
      double y = paddingTop + height - barH;

      Color barColor = datos[i].value >= 100 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
      final barPaint = Paint()..color = barColor;

      canvas.drawRect(Rect.fromLTWH(x, y, barWidth, barH), barPaint);

      // ETIQUETAS MÁS GRANDES (fontSize: 13)
      TextPainter tpVal = TextPainter(text: TextSpan(text: '${datos[i].value.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)), textDirection: TextDirection.ltr);
      tpVal.layout();
      tpVal.paint(canvas, Offset(x + (barWidth / 2) - (tpVal.width / 2), y - 18));

      canvas.save();
      canvas.translate(x + (barWidth / 2), paddingTop + height + 10);
      canvas.rotate(-pi / 3.5);

      String shortName = datos[i].key;
      if (shortName.length > 20) shortName = '${shortName.substring(0, 18)}...';

      TextPainter tpName = TextPainter(text: TextSpan(text: shortName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))), textDirection: TextDirection.ltr, maxLines: 1);
      tpName.layout();
      tpName.paint(canvas, Offset(-tpName.width, 0));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 🍩 DONUT CHART
class DonutChartWidget extends StatelessWidget {
  final Map<String, double> datos;
  final List<Color> colores;

  const DonutChartWidget({super.key, required this.datos, required this.colores});

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) return const Center(child: Text('Sin datos', style: TextStyle(fontSize: 13, color: Colors.grey)));

    double total = datos.values.fold(0, (s, item) => s + item);

    return Row(
      children: [
        Expanded(flex: 5, child: CustomPaint(painter: _DonutPainter(datos: datos, colores: colores, total: total), child: Container())),
        const SizedBox(width: 20),
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: datos.keys.toList().asMap().entries.map((entry) {
              int idx = entry.key;
              Color color = colores[idx % colores.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(entry.value, style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }).toList(),
          ),
        )
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final Map<String, double> datos;
  final List<Color> colores;
  final double total;

  _DonutPainter({required this.datos, required this.colores, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    double startAngle = -pi / 2;
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = min(size.width, size.height) / 2 - 10;
    final paintArc = Paint()..style = PaintingStyle.fill;

    int idx = 0;
    datos.forEach((key, val) {
      if (val > 0) {
        double sweepAngle = (val / total) * 2 * pi;
        paintArc.color = colores[idx % colores.length];
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, true, paintArc);

        double pct = (val / total) * 100;
        if (pct >= 5) {
          double middleAngle = startAngle + (sweepAngle / 2);
          double textX = center.dx + (radius * 0.70) * cos(middleAngle);
          double textY = center.dy + (radius * 0.70) * sin(middleAngle);

          // ETIQUETAS MÁS GRANDES (fontSize: 12)
          TextPainter tp = TextPainter(text: TextSpan(text: '${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)), textDirection: TextDirection.ltr);
          tp.layout();
          tp.paint(canvas, Offset(textX - (tp.width / 2), textY - (tp.height / 2)));
        }
        startAngle += sweepAngle;
      }
      idx++;
    });

    canvas.drawCircle(center, radius * 0.45, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}