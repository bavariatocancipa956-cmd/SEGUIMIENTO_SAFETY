import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:fl_chart/fl_chart.dart';

class CruceFmsRoturasScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const CruceFmsRoturasScreen({super.key, this.onToggleSidebar});

  @override
  State<CruceFmsRoturasScreen> createState() => _CruceFmsRoturasScreenState();
}

class _CruceFmsRoturasScreenState extends State<CruceFmsRoturasScreen> {
  static const String _apiUrlRoturas = 'https://plantatocancipa.site/api/v1/db_logistica/consultar/roturas/reportes_rotura';
  static const String _apiUrlFms = 'https://plantatocancipa.site/api/v1/db_logistica/consultar/fms/fms_reporte';
  static const String _apiKey = 'PlantaLogistica2026*';

  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _datosFmsRaw = [];
  List<Map<String, dynamic>> _datosRoturasRaw = [];

  // FILTROS
  DateTime _fechaDesde = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fechaHasta = DateTime.now();

  String _mesSeleccionado = 'Mes Actual';
  String _opmSeleccionado = 'Todos';
  String _supervisorSeleccionado = 'Todos';
  String _eventoSeleccionado = 'Todos';

  final List<String> _listaMeses = ['Mes Actual', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
  List<String> _listaOpms = ['Todos'];
  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaEventos = ['Todos'];

  // DATOS PARA TABLAS Y GRÁFICAS
  List<Map<String, dynamic>> _datosDetalle = [];
  List<Map<String, dynamic>> _datosTopOffenders = [];

  // ESTADOS DE ORDENAMIENTO (Por defecto: Descendente en Total FMS)
  int _sortDetalleCol = 4;
  bool _sortDetalleAsc = false;

  int _sortTopCol = 1;
  bool _sortTopAsc = false;

  @override
  void initState() {
    super.initState();
    _cargarAmbasBasesDeDatos();
  }

  Future<void> _cargarAmbasBasesDeDatos() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      final respuestas = await Future.wait([
        http.get(Uri.parse('$_apiUrlFms?_t=$timestamp'), headers: {'x-api-key': _apiKey}),
        http.get(Uri.parse('$_apiUrlRoturas?_t=$timestamp'), headers: {'x-api-key': _apiKey}),
      ]).timeout(const Duration(seconds: 20));

      final resFms = respuestas[0];
      final resRoturas = respuestas[1];

      if (resFms.statusCode == 200 && resRoturas.statusCode == 200) {
        final bodyFms = jsonDecode(resFms.body);
        final bodyRoturas = jsonDecode(resRoturas.body);

        _datosFmsRaw = List<Map<String, dynamic>>.from(bodyFms['data'] ?? []);
        _datosRoturasRaw = List<Map<String, dynamic>>.from(bodyRoturas['data'] ?? []);

        _extraerOpcionesFiltros();
        _procesarCruceDeDatos();

        setState(() {
          _cargando = false;
        });
      } else {
        setState(() {
          _mensajeError = 'Error de servidor. FMS: ${resFms.statusCode}, Roturas: ${resRoturas.statusCode}';
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() {
        _mensajeError = 'Error de conexión: $e';
        _cargando = false;
      });
    }
  }

  String _normalizarEvento(String raw) {
    String ev = raw.toUpperCase().trim();
    if (ev.contains('ACELERACI')) return 'Aceleración';
    if (ev.contains('IMPACTO')) return 'Impacto';
    if (ev.contains('FRENAD')) return 'Frenada';
    if (ev.contains('VELOCIDAD') || ev.contains('EXCESO')) return 'Exc. Velocidad';
    return raw.trim().isNotEmpty ? raw.trim() : 'Desconocido';
  }

  void _extraerOpcionesFiltros() {
    Set<String> opms = {'Todos'};
    Set<String> supervisores = {'Todos'};
    Set<String> eventos = {'Todos'};

    for (var f in _datosFmsRaw) {
      String opm = (f['evaluado']?.toString() ?? f['personal']?.toString() ?? f['operador']?.toString() ?? f['nombre']?.toString() ?? '').trim().toUpperCase();
      String sup = (f['supervisor']?.toString() ?? '').trim().toUpperCase();
      String ev = _normalizarEvento(f['evento']?.toString() ?? '');

      if (opm.isNotEmpty && opm != 'NULL') opms.add(opm);
      if (sup.isNotEmpty && sup != 'NULL') supervisores.add(sup);
      if (ev.isNotEmpty && ev != 'DESCONOCIDO') eventos.add(ev);
    }

    _listaOpms = opms.toList()..sort();
    _listaSupervisores = supervisores.toList()..sort();
    _listaEventos = eventos.toList()..sort();
  }

  void _procesarCruceDeDatos() {
    Map<String, Map<String, dynamic>> agrupacionPersonas = {};

    for (var fms in _datosFmsRaw) {
      if (!_estaEnRango(fms['timestamp_registro']?.toString() ?? fms['fecha']?.toString())) continue;

      String persona = (fms['evaluado']?.toString() ?? fms['personal']?.toString() ?? fms['operador']?.toString() ?? fms['nombre']?.toString() ?? 'DESCONOCIDO').trim().toUpperCase();
      String supervisor = (fms['supervisor']?.toString() ?? 'SIN SUPERVISOR').trim().toUpperCase();
      String evento = _normalizarEvento(fms['evento']?.toString() ?? '');

      if (persona == 'NULL' || persona == 'DESCONOCIDO') continue;

      if (_opmSeleccionado != 'Todos' && persona != _opmSeleccionado) continue;
      if (_supervisorSeleccionado != 'Todos' && supervisor != _supervisorSeleccionado) continue;
      if (_eventoSeleccionado != 'Todos' && evento != _eventoSeleccionado) continue;

      if (!agrupacionPersonas.containsKey(persona)) {
        agrupacionPersonas[persona] = {
          'supervisor': supervisor,
          'personal': persona,
          'eventos_fms': <String, int>{},
          'total_fms': 0,
          'roturas': 0.0,
          'eventos_rotura': 0,
        };
      }

      agrupacionPersonas[persona]!['supervisor'] = supervisor;
      agrupacionPersonas[persona]!['total_fms'] += 1;

      Map<String, int> eventosMap = agrupacionPersonas[persona]!['eventos_fms'];
      eventosMap[evento] = (eventosMap[evento] ?? 0) + 1;
    }

    for (var rot in _datosRoturasRaw) {
      if (!_estaEnRango(rot['timestamp_registro']?.toString() ?? rot['fecha_evento']?.toString())) continue;

      String persona = (rot['personal']?.toString() ?? rot['reportante']?.toString() ?? 'DESCONOCIDO').trim().toUpperCase();
      double cant = double.tryParse(rot['cantidad']?.toString() ?? '0') ?? 0.0;

      if (agrupacionPersonas.containsKey(persona)) {
        agrupacionPersonas[persona]!['roturas'] += cant;
        agrupacionPersonas[persona]!['eventos_rotura'] += 1;
      }
    }

    _datosDetalle = agrupacionPersonas.values.toList();
    _datosTopOffenders = List.from(_datosDetalle);

    _aplicarOrdenDetalle();
    _aplicarOrdenTop();
  }

  // ---------------------------------------------------------------------------
  // LOGICA DE ORDENAMIENTO (TODAS LAS COLUMNAS HABILITADAS)
  // ---------------------------------------------------------------------------
  void _ordenarDetalle(int colIndex) {
    setState(() {
      if (_sortDetalleCol == colIndex) {
        _sortDetalleAsc = !_sortDetalleAsc;
      } else {
        _sortDetalleCol = colIndex;
        _sortDetalleAsc = false;
      }
      _aplicarOrdenDetalle();
    });
  }

  void _aplicarOrdenDetalle() {
    _datosDetalle.sort((a, b) {
      int cmp = 0;
      if (_sortDetalleCol == 0) cmp = a['supervisor'].compareTo(b['supervisor']);
      else if (_sortDetalleCol == 1) cmp = a['personal'].compareTo(b['personal']);
      // Si hacen clic en los detalles internos de FMS (Col 2 y 3), se ordenará por el Total de FMS para que no se rompa la tabla
      else if (_sortDetalleCol == 2 || _sortDetalleCol == 3 || _sortDetalleCol == 4) {
        cmp = (a['total_fms'] as int).compareTo(b['total_fms'] as int);
      }
      else if (_sortDetalleCol == 5) cmp = (a['roturas'] as double).compareTo(b['roturas'] as double);
      else if (_sortDetalleCol == 6) cmp = (a['eventos_rotura'] as int).compareTo(b['eventos_rotura'] as int);

      return _sortDetalleAsc ? cmp : -cmp;
    });
  }

  void _ordenarTop(int colIndex) {
    setState(() {
      if (_sortTopCol == colIndex) {
        _sortTopAsc = !_sortTopAsc;
      } else {
        _sortTopCol = colIndex;
        _sortTopAsc = false;
      }
      _aplicarOrdenTop();
    });
  }

  void _aplicarOrdenTop() {
    _datosTopOffenders.sort((a, b) {
      int cmp = 0;
      if (_sortTopCol == 0) cmp = a['personal'].compareTo(b['personal']);
      else if (_sortTopCol == 1) cmp = (a['total_fms'] as int).compareTo(b['total_fms'] as int);
      else if (_sortTopCol == 2) cmp = (a['roturas'] as double).compareTo(b['roturas'] as double);
      else if (_sortTopCol == 3) cmp = (a['eventos_rotura'] as int).compareTo(b['eventos_rotura'] as int);

      return _sortTopAsc ? cmp : -cmp;
    });
  }

  bool _estaEnRango(String? rawFecha) {
    if (rawFecha == null || rawFecha.isEmpty) return false;
    String fechaLimpia = rawFecha.replaceAll('T', ' ').split('.')[0];
    DateTime? dt = DateTime.tryParse(fechaLimpia);
    if (dt == null) return false;

    DateTime fechaPura = DateTime(dt.year, dt.month, dt.day);
    DateTime desdePura = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
    DateTime hastaPura = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day);

    return !fechaPura.isBefore(desdePura) && !fechaPura.isAfter(hastaPura);
  }

  Future<void> _seleccionarFecha(bool isDesde) async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: isDesde ? _fechaDesde : _fechaHasta,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E293B), onPrimary: Colors.white, onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (seleccion != null) {
      setState(() {
        if (isDesde) _fechaDesde = seleccion; else _fechaHasta = seleccion;
        _mesSeleccionado = 'Personalizado';
      });
    }
  }

  void _alCambiarMes(String? nuevoMes) {
    if (nuevoMes == null) return;
    setState(() {
      _mesSeleccionado = nuevoMes;
      if (nuevoMes != 'Personalizado' && nuevoMes != 'Mes Actual') {
        int mesIndex = _listaMeses.indexOf(nuevoMes);
        int anio = DateTime.now().year;
        _fechaDesde = DateTime(anio, mesIndex, 1);
        _fechaHasta = DateTime(anio, mesIndex + 1, 0);
      } else if (nuevoMes == 'Mes Actual') {
        _fechaDesde = DateTime(DateTime.now().year, DateTime.now().month, 1);
        _fechaHasta = DateTime.now();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(backgroundColor: Color(0xFFF1F5F9), body: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))));
    }

    int totalPersonasEnRiesgo = _datosDetalle.length;
    int totalFMS = _datosDetalle.fold(0, (s, e) => s + (e['total_fms'] as int));
    int totalEventosRotura = _datosDetalle.fold(0, (s, e) => s + (e['eventos_rotura'] as int));
    double totalUndsRotura = _datosDetalle.fold(0.0, (s, e) => s + (e['roturas'] as double));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ENCABEZADO
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.compare_arrows_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Análisis Cruzado: FMS vs Roturas', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                      SizedBox(height: 4),
                      Text('Impacto de alertas conductuales (FMS) en la accidentalidad de producto', style: TextStyle(fontSize: 14, color: Color(0xFF475569))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_mensajeError != null)
                Container(
                  padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                  child: Text(_mensajeError!, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold)),
                ),

              // BARRA DE FILTROS HORIZONTAL
              _buildBarraFiltrosHorizontal(),
              const SizedBox(height: 24),

              // KPIs PREMIUM
              Row(
                children: [
                  Expanded(child: _buildKPICard('OPERADORES', '$totalPersonasEnRiesgo', 'Que cumplen filtros', const Color(0xFF3B82F6), Icons.group_rounded)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKPICard('TOTAL ALERTAS FMS', '$totalFMS', 'En periodo filtrado', const Color(0xFF8B5CF6), Icons.warning_amber_rounded)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKPICard('EVENTOS ROTURA', '$totalEventosRotura', 'Ocasionados', const Color(0xFFF59E0B), Icons.broken_image_rounded)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKPICard('UNIDADES ROTAS', '${totalUndsRotura.toInt()}', 'Físicas afectadas', const Color(0xFFEF4444), Icons.production_quantity_limits_rounded)),
                ],
              ),
              const SizedBox(height: 32),

              // SECCIÓN DE GRÁFICAS (BARRAS Y DONA)
              _buildSeccionGraficas(),
              const SizedBox(height: 32),

              // TABLA TOP OFFENDERS
              _buildTopOffendersTable(),
              const SizedBox(height: 32),

              // TABLA DETALLE (CON BORDES GRUESOS Y SCROLL)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: const Color(0xFF1E293B).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.table_view_rounded, color: Color(0xFF1E293B), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text('Detalle de Operadores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(20)),
                      child: Text('${_datosDetalle.length} Registros', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF334155))),
                    )
                  ],
                ),
              ),
              _buildTablaDetalle(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGETS AUXILIARES (FILTROS Y KPIS)
  // ---------------------------------------------------------------------------
  Widget _buildBarraFiltrosHorizontal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildFiltroSimple('MES', _buildDropdown(_mesSeleccionado, _listaMeses, _alCambiarMes, 130)),
            const SizedBox(width: 16),
            _buildFiltroSimple('DESDE', InkWell(onTap: () => _seleccionarFecha(true), child: _buildBotonFecha(_fechaDesde))),
            const SizedBox(width: 16),
            _buildFiltroSimple('HASTA', InkWell(onTap: () => _seleccionarFecha(false), child: _buildBotonFecha(_fechaHasta))),
            const SizedBox(width: 16),
            _buildFiltroSimple('OPM (PERSONAL)', _buildDropdown(_opmSeleccionado, _listaOpms, (v) => setState(() => _opmSeleccionado = v!), 180)),
            const SizedBox(width: 16),
            _buildFiltroSimple('SUPERVISOR', _buildDropdown(_supervisorSeleccionado, _listaSupervisores, (v) => setState(() => _supervisorSeleccionado = v!), 180)),
            const SizedBox(width: 16),
            _buildFiltroSimple('EVENTO FMS', _buildDropdown(_eventoSeleccionado, _listaEventos, (v) => setState(() => _eventoSeleccionado = v!), 140)),
            const SizedBox(width: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _cargando = true);
                _procesarCruceDeDatos();
                setState(() => _cargando = false);
              },
              icon: const Icon(Icons.filter_alt_rounded, size: 16),
              label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltroSimple(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildDropdown(String valor, List<String> opciones, Function(String?) onChanged, double width) {
    return Container(
      width: width, height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8), color: Colors.white),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: opciones.contains(valor) ? valor : opciones.first,
          icon: const Icon(Icons.expand_more_rounded, size: 18, color: Color(0xFF64748B)),
          style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600),
          onChanged: onChanged,
          items: opciones.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
        ),
      ),
    );
  }

  Widget _buildBotonFecha(DateTime fecha) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(8), color: Colors.white),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(DateFormat('dd/MM/yyyy').format(fecha), style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _buildKPICard(String titulo, String mainValue, String subValue, Color color, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icono, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(mainValue, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color, height: 1.1)),
                const SizedBox(height: 4),
                Text(subValue, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GRÁFICAS DE ALTO NIVEL CON FL_CHART Y ETIQUETAS SUPERIORES
  // ---------------------------------------------------------------------------
  Widget _buildSeccionGraficas() {
    List<Map<String, dynamic>> top5 = List.from(_datosDetalle);
    top5.sort((a, b) {
      int cmp = (b['roturas'] as double).compareTo(a['roturas'] as double);
      if (cmp != 0) return cmp;
      return (b['total_fms'] as int).compareTo(a['total_fms'] as int);
    });
    if (top5.length > 5) top5 = top5.sublist(0, 5);

    double maxVal = 5;
    List<BarChartGroupData> barGroups = [];

    for (int i = 0; i < top5.length; i++) {
      double fms = (top5[i]['total_fms'] as int).toDouble();
      double evRot = (top5[i]['eventos_rotura'] as int).toDouble();
      double rot = (top5[i]['roturas'] as double);

      if (fms > maxVal) maxVal = fms;
      if (evRot > maxVal) maxVal = evRot;
      if (rot > maxVal) maxVal = rot;

      barGroups.add(BarChartGroupData(
        x: i,
        showingTooltipIndicators: [0, 1, 2], // Mostrar etiquetas para las 3 barras permanentemente
        barRods: [
          BarChartRodData(toY: fms, color: const Color(0xFF3B82F6), width: 14, borderRadius: BorderRadius.circular(4)),
          BarChartRodData(toY: evRot, color: const Color(0xFFF59E0B), width: 14, borderRadius: BorderRadius.circular(4)),
          BarChartRodData(toY: rot, color: const Color(0xFFEF4444), width: 14, borderRadius: BorderRadius.circular(4)),
        ],
      ));
    }

    Map<String, double> conteoEventos = {};
    for (var d in _datosDetalle) {
      Map<String, int> eventosMap = d['eventos_fms'];
      eventosMap.forEach((k, v) { conteoEventos[k] = (conteoEventos[k] ?? 0) + v; });
    }

    List<Color> pieColors = [const Color(0xFF8B5CF6), const Color(0xFF059669), const Color(0xFFF59E0B), const Color(0xFFD946EF), const Color(0xFF06B6D4)];
    List<PieChartSectionData> pieSections = [];
    int colorIdx = 0;

    var eventosOrdenados = conteoEventos.entries.toList()..sort((a,b) => b.value.compareTo(a.value));

    for (var entry in eventosOrdenados) {
      if (entry.value > 0) {
        pieSections.add(PieChartSectionData(
          value: entry.value, color: pieColors[colorIdx % pieColors.length],
          title: '${entry.value.toInt()}', radius: 45,
          titleStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ));
        colorIdx++;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BARRAS
        Expanded(
          flex: 5,
          child: Container(
            height: 400,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Top 5 Riesgos: FMS vs Roturas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    Row(
                      children: [
                        _buildLeyenda(const Color(0xFF3B82F6), 'Alertas FMS'),
                        const SizedBox(width: 12),
                        _buildLeyenda(const Color(0xFFF59E0B), 'Eventos Rotura'),
                        const SizedBox(width: 12),
                        _buildLeyenda(const Color(0xFFEF4444), 'Unidades Rotas'),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 40), // Más espacio por los tooltips de arriba
                Expanded(
                  child: top5.isEmpty
                      ? const Center(child: Text('Sin datos'))
                      : BarChart(
                    BarChartData(
                      maxY: maxVal * 1.35, // Margen superior extra para las etiquetas
                      barGroups: barGroups,
                      barTouchData: BarTouchData(
                        enabled: false,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => Colors.transparent, // Fondo invisible
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 4,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              rod.toY.round().toString(),
                              TextStyle(color: rod.color, fontWeight: FontWeight.bold, fontSize: 11),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() < top5.length) {
                                String name = top5[value.toInt()]['personal'];
                                List<String> parts = name.split(' ');
                                String short = parts.length > 1 ? '${parts[0]} ${parts[1]}' : parts[0];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 10.0),
                                  child: Text(short, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v,m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))))),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        // DONA
        Expanded(
          flex: 3,
          child: Container(
            height: 400,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Distribución de Eventos FMS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 32),
                Expanded(
                    child: pieSections.isEmpty
                        ? const Center(child: Text('Sin datos'))
                        : Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: PieChart(PieChartData(sections: pieSections, sectionsSpace: 2, centerSpaceRadius: 45)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(eventosOrdenados.length, (index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: _buildLeyenda(pieColors[index % pieColors.length], '${eventosOrdenados[index].key}\n(${eventosOrdenados[index].value.toInt()} ev)'),
                              );
                            }),
                          ),
                        )
                      ],
                    )
                ),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildLeyenda(Color color, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 2), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(texto, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569), height: 1.3)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TABLA TOP OFFENDERS (ORDENABLE Y 100% CLICKABLE)
  // ---------------------------------------------------------------------------
  Widget _buildTopOffendersTable() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.warning_rounded, color: Colors.red.shade600, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Top Offenders (Prioridad de Intervención)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ],
            ),
          ),

          // ENCABEZADOS FIJOS (AZUL OSCURO, FULL CLICKABLE)
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _buildHeaderCell('PERSONAL', 4, 0, _sortTopCol, _sortTopAsc, _ordenarTop, isDark: true),
                  _buildHeaderCell('TOTAL FMS', 2, 1, _sortTopCol, _sortTopAsc, _ordenarTop, isDark: true),
                  _buildHeaderCell('UNIDADES ROTAS', 2, 2, _sortTopCol, _sortTopAsc, _ordenarTop, isDark: true),
                  _buildHeaderCell('EV. ROTURA', 2, 3, _sortTopCol, _sortTopAsc, _ordenarTop, isLast: true, isDark: true),
                ],
              ),
            ),
          ),

          // CUERPO SCROLLABLE (Altura Máxima 400px ~ 10 líneas)
          SizedBox(
            height: 400,
            child: _datosTopOffenders.isEmpty
                ? const Center(child: Text('Sin datos en este periodo.', style: TextStyle(color: Colors.grey)))
                : Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                itemCount: _datosTopOffenders.length,
                itemBuilder: (context, index) {
                  var d = _datosTopOffenders[index];
                  int fms = d['total_fms'];
                  int rot = (d['roturas'] as double).toInt();
                  int evRot = d['eventos_rotura'];
                  bool isPar = index % 2 == 0;

                  return Container(
                    decoration: BoxDecoration(
                        color: isPar ? Colors.white : const Color(0xFFF8FAFC),
                        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          _buildDataCell(d['personal'], flex: 4, alinearCentro: false, isBold: true),
                          _buildDataCell(fms.toString(), flex: 2, textColor: const Color(0xFF3B82F6), isBold: true),
                          _buildDataCell(rot.toString(), flex: 2, textColor: rot > 0 ? const Color(0xFFDC2626) : const Color(0xFF94A3B8), isBold: true),
                          _buildDataCell(evRot.toString(), flex: 2, textColor: const Color(0xFF475569), isBold: true, isLast: true),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLA DETALLE (ORDENABLE Y CON SUB-DIVISIONES)
  // ---------------------------------------------------------------------------
  Widget _buildTablaDetalle() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ENCABEZADOS FIJOS
            Container(
              color: const Color(0xFF1E293B),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderCell('SUPERVISOR', 2, 0, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isDark: true),
                    _buildHeaderCell('PERSONAL', 3, 1, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isDark: true),
                    _buildHeaderCell('EVENTOS FMS', 2, 2, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isDark: true),
                    _buildHeaderCell('CANT. FMS', 1, 3, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isDark: true),
                    _buildHeaderCell('TOTAL FMS', 1, 4, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isDark: true),
                    _buildHeaderCell('ROTURAS', 1, 5, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isDark: true),
                    _buildHeaderCell('EV. ROTURA', 2, 6, _sortDetalleCol, _sortDetalleAsc, _ordenarDetalle, isLast: true, isDark: true),
                  ],
                ),
              ),
            ),

            // CUERPO SCROLLABLE (Altura Máxima 500px)
            _datosDetalle.isEmpty
                ? const Padding(padding: EdgeInsets.all(60), child: Center(child: Text('No hay cruces de datos con estos filtros.', style: TextStyle(color: Colors.grey, fontSize: 14))))
                : SizedBox(
              height: 500,
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                    itemCount: _datosDetalle.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: _buildFilaEspecializadaGruesa(_datosDetalle[index], index % 2 == 0),
                      );
                    }
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMPONENTES DE TABLA DINÁMICOS
  // ---------------------------------------------------------------------------

  // ENCABEZADOS 100% CLICKABLES CON RIPPLE EFFECT
  Widget _buildHeaderCell(String texto, int flex, int colIndex, int currentCol, bool isAsc, Function(int) onSort, {bool isLast = false, bool isDark = false}) {
    bool isSorted = colIndex == currentCol;

    Color bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    Color txtColor = isDark ? Colors.white : const Color(0xFF64748B);
    Color borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    Color arrowColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF3B82F6);

    return Expanded(
      flex: flex,
      child: Material(
        color: bgColor,
        child: InkWell(
          onTap: () => onSort(colIndex),
          child: Container(
            decoration: BoxDecoration(border: Border(right: isLast ? BorderSide.none : BorderSide(color: borderColor))),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(texto, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: txtColor, letterSpacing: 0.8))),
                if (isSorted) ...[
                  const SizedBox(width: 6),
                  Icon(isAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: arrowColor),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataCell(String texto, {required int flex, bool alinearCentro = true, Color textColor = const Color(0xFF334155), bool isLast = false, bool isBold = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(border: Border(right: isLast ? BorderSide.none : const BorderSide(color: Color(0xFFE2E8F0)))),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        alignment: alinearCentro ? Alignment.center : Alignment.centerLeft,
        child: Text(
            texto,
            textAlign: alinearCentro ? TextAlign.center : TextAlign.left,
            style: TextStyle(fontSize: 12, color: textColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)
        ),
      ),
    );
  }

  // Fila del Detalle (Bordes Gruesos y Marcados por Operador)
  Widget _buildFilaEspecializadaGruesa(Map<String, dynamic> data, bool isPar) {
    Map<String, int> eventosFms = data['eventos_fms'];

    if (eventosFms.isEmpty) {
      eventosFms = {'N/A': 0};
    }

    List<Widget> filasEventos = [];
    int index = 0;
    eventosFms.forEach((eventoNombre, cantidadFms) {
      bool isLast = index == eventosFms.length - 1;
      filasEventos.add(
          Row(
            children: [
              Expanded(flex: 2, child: Container(
                decoration: BoxDecoration(border: Border(bottom: isLast ? BorderSide.none : const BorderSide(color: Color(0xFFCBD5E1)), right: const BorderSide(color: Color(0xFFCBD5E1)))),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                alignment: Alignment.centerLeft,
                child: Text(eventoNombre, style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
              )),
              Expanded(flex: 1, child: Container(
                decoration: BoxDecoration(border: Border(bottom: isLast ? BorderSide.none : const BorderSide(color: Color(0xFFCBD5E1)))),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                alignment: Alignment.center,
                child: Text(cantidadFms.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              )),
            ],
          )
      );
      index++;
    });

    int cantRoturas = (data['roturas'] as double).toInt();
    int evRoturas = data['eventos_rotura'] as int;
    bool tieneRoturas = cantRoturas > 0;

    return Container(
      decoration: BoxDecoration(
        color: isPar ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCeldaUnificadaGruesa(data['supervisor'], flex: 2),
              _buildCeldaUnificadaGruesa(data['personal'], flex: 3, isBold: true),

              Expanded(
                  flex: 3,
                  child: Container(
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFCBD5E1)))),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: filasEventos)
                  )
              ),

              _buildCeldaPildoraGruesa(data['total_fms'].toString(), flex: 1, colorBg: Colors.blue.shade50, colorTxt: Colors.blue.shade700),

              _buildCeldaPildoraGruesa(cantRoturas.toString(), flex: 1, colorBg: tieneRoturas ? Colors.red.shade50 : Colors.transparent, colorTxt: tieneRoturas ? Colors.red.shade700 : const Color(0xFF94A3B8)),

              _buildCeldaUnificadaGruesa(evRoturas.toString(), flex: 2, colorExtra: tieneRoturas ? Colors.red.shade700 : const Color(0xFF94A3B8), isLast: true, isBold: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCeldaUnificadaGruesa(String texto, {required int flex, bool isBold = false, Color colorExtra = const Color(0xFF1E293B), bool isLast = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(border: Border(right: isLast ? BorderSide.none : const BorderSide(color: Color(0xFFCBD5E1)))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        alignment: Alignment.center,
        child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colorExtra, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600)
        ),
      ),
    );
  }

  Widget _buildCeldaPildoraGruesa(String texto, {required int flex, required Color colorBg, required Color colorTxt}) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFCBD5E1)))),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: colorBg, borderRadius: BorderRadius.circular(6)),
          child: Text(texto, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: colorTxt)),
        ),
      ),
    );
  }
}