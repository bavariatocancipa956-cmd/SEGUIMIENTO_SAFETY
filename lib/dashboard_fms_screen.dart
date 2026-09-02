import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'api_service.dart';

class DashboardFmsScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const DashboardFmsScreen({super.key, this.onToggleSidebar});

  @override
  State<DashboardFmsScreen> createState() => _DashboardFmsScreenState();
}

class _DashboardFmsScreenState extends State<DashboardFmsScreen> {
  // ---------------------------------------------------------------------------
  // 📅 ESTADOS DE FILTROS
  // ---------------------------------------------------------------------------
  DateTime _fechaDesde = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _fechaHasta = DateTime.now();

  String _turnoSeleccionado = 'Todos';
  String _supervisorSeleccionado = 'Todos';
  String _operadorSeleccionado = 'Todos';
  String _areaSeleccionada = 'Todos';
  String _origenSeleccionado = 'Todos';

  List<String> _listaTurnos = ['Todos', 'T1', 'T2', 'T3'];
  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaOperadores = ['Todos'];
  List<String> _listaAreas = ['Todos'];
  List<String> _listaOrigenes = ['Todos'];

  // ---------------------------------------------------------------------------
  // 🌐 ESTADOS DE LA BASE DE DATOS
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> _reportesFms = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  // ---------------------------------------------------------------------------
  // 🔌 CONSUMO DE API Y EXTRACCIÓN DE FILTROS
  // ---------------------------------------------------------------------------
  Future<void> _cargarDatosBD() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final resultados = await ApiService.consultarTabla(
        esquema: 'fms',
        tabla: 'fms_reporte',
      );

      if (resultados.isEmpty) {
        setState(() {
          _reportesFms = [];
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> dataLista = resultados.map((e) {
        Map<String, dynamic> mapa = Map<String, dynamic>.from(e);
        mapa['fecha_dt'] = DateTime.tryParse(mapa['fecha'].toString()) ?? DateTime.now();
        return mapa;
      }).toList();

      Set<String> ops = {'Todos'};
      Set<String> sups = {'Todos'};
      Set<String> areas = {'Todos'};
      Set<String> origenes = {'Todos'};

      for (var d in dataLista) {
        if (d['nombre'] != null && d['nombre'].toString().trim().isNotEmpty) ops.add(d['nombre'].toString().trim());
        if (d['supervisor'] != null && d['supervisor'].toString().trim().isNotEmpty) sups.add(d['supervisor'].toString().trim());
        if (d['area'] != null && d['area'].toString().trim().isNotEmpty) areas.add(d['area'].toString().trim());
        if (d['origen_opm'] != null && d['origen_opm'].toString().trim().isNotEmpty) origenes.add(d['origen_opm'].toString().trim());
      }

      setState(() {
        _listaOperadores = ops.toList()..sort();
        _listaSupervisores = sups.toList()..sort();
        _listaAreas = areas.toList()..sort();
        _listaOrigenes = origenes.toList()..sort();

        _reportesFms = dataLista;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al conectar con la API: $e';
        _isLoading = false;
      });
    }
  }

  String _normalizarEvento(String raw) {
    String ev = raw.toUpperCase().trim();
    ev = ev.replaceAll('Á', 'A').replaceAll('É', 'E').replaceAll('Í', 'I').replaceAll('Ó', 'O').replaceAll('Ú', 'U');

    if (ev.contains('ACELERACI')) return 'ACEL';
    if (ev.contains('IMPACTO')) return 'IMPAC';
    if (ev.contains('FRENAD')) return 'FREN';

    if (ev.contains('VELOCIDAD') || ev.contains('EXCESO')) return 'EXC. VEL.';
    if (ev.endsWith('S') && ev.length > 3 && ev != 'VAS') {
      ev = ev.substring(0, ev.length - 1);
    }
    return ev;
  }

  String _formatearFechaLimpia(dynamic fechaRaw) {
    if (fechaRaw == null) return '';
    String f = fechaRaw.toString().trim();
    if (f.contains('T')) {
      return f.split('T')[0];
    }
    if (f.contains(' ')) {
      return f.split(' ')[0];
    }
    return f;
  }

  // ---------------------------------------------------------------------------
  // 🔄 FILTRADO DINÁMICO
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> get _reportesFiltrados {
    DateTime desdeClean = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
    DateTime hastaClean = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day, 23, 59, 59);

    return _reportesFms.where((item) {
      try {
        DateTime fechaItem = item['fecha_dt'] as DateTime;
        bool cumpleFecha = fechaItem.isAfter(desdeClean.subtract(const Duration(seconds: 1))) &&
            fechaItem.isBefore(hastaClean.add(const Duration(seconds: 1)));

        bool cumpleTurno = _turnoSeleccionado == 'Todos' || item['turno'] == _turnoSeleccionado;
        bool cumpleSupervisor = _supervisorSeleccionado == 'Todos' || item['supervisor'] == _supervisorSeleccionado;
        bool cumpleOperador = _operadorSeleccionado == 'Todos' || item['nombre'] == _operadorSeleccionado;
        bool cumpleArea = _areaSeleccionada == 'Todos' || item['area'] == _areaSeleccionada;
        bool cumpleOrigen = _origenSeleccionado == 'Todos' || item['origen_opm'] == _origenSeleccionado;

        return cumpleFecha && cumpleTurno && cumpleSupervisor && cumpleOperador && cumpleArea && cumpleOrigen;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // 📊 DESCARGAR EXCEL / CSV
  // ---------------------------------------------------------------------------
  void _descargarExcel(List<Map<String, dynamic>> datos) {
    if (datos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar'), backgroundColor: Colors.orange),
      );
      return;
    }

    StringBuffer csvData = StringBuffer();
    csvData.writeln('FECHA,HORA,TURNO,MÁQUINA,ÁREA,OPERADOR,ORIGEN OPM,ALERTA,SUPERVISOR');

    for (var item in datos) {
      String fecha = _formatearFechaLimpia(item['fecha']);
      String hora = item['hora']?.toString() ?? '';
      String turno = item['turno']?.toString() ?? '';
      String maquina = item['maquina']?.toString() ?? '';
      String area = '"${(item['area']?.toString() ?? '').replaceAll('"', '""')}"';
      String operador = '"${(item['nombre']?.toString() ?? '').replaceAll('"', '""')}"';
      String origen = '"${(item['origen_opm']?.toString() ?? '').replaceAll('"', '""')}"';
      String evento = '"${_normalizarEvento(item['evento']?.toString() ?? '').replaceAll('"', '""')}"';
      String supervisor = '"${(item['supervisor']?.toString() ?? '').replaceAll('"', '""')}"';

      csvData.writeln('$fecha,$hora,$turno,$maquina,$area,$operador,$origen,$evento,$supervisor');
    }

    final bytes = utf8.encode(csvData.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "reporte_fms_diario_${DateTime.now().millisecondsSinceEpoch}.csv")
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📊 Archivo Excel/CSV generado exitosamente'),
        backgroundColor: Color(0xFF107C41),
      ),
    );
  }

  void _tomarFoto() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📸 Capturando vista del Dashboard...'),
        backgroundColor: Color(0xFF475569),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _activarModoTV() {
    if (widget.onToggleSidebar != null) {
      widget.onToggleSidebar!();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F3F9),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF2563EB)),
              SizedBox(height: 16),
              Text('Consultando base de datos...', style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F3F9),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 60),
              const SizedBox(height: 16),
              Text(_errorMessage, style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _cargarDatosBD,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar Conexión', style: TextStyle(fontSize: 15)),
              )
            ],
          ),
        ),
      );
    }

    final datosActuales = _reportesFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFiltrosBarra(),
            const SizedBox(height: 24),

            if (datosActuales.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: const Column(
                  children: [
                    Icon(Icons.search_off_rounded, size: 60, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No hay eventos en este rango o con los filtros seleccionados.', style: TextStyle(fontSize: 18, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else ...[
              _buildKpiCards(datosActuales),
              const SizedBox(height: 24),
              _buildFilaGraficas(context, datosActuales),
              const SizedBox(height: 24),
              _buildFilaTablasPrincipales(context, datosActuales),
              const SizedBox(height: 24),
              _buildFilaTablasSecundarias(context, datosActuales),
              const SizedBox(height: 24),
              _buildTablaDetalleCompletoStateful(datosActuales),
            ]
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔍 1. FILTROS
  // ---------------------------------------------------------------------------
  Widget _buildFiltrosBarra() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Wrap(
        spacing: 16, // Espaciado horizontal
        runSpacing: 16, // Espaciado vertical si hace salto de línea
        crossAxisAlignment: WrapCrossAlignment.end, // Alinea los botones al ras de los inputs
        children: [
          _buildCampoFecha('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d)),
          _buildCampoFecha('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d)),
          _buildSearchableDropdown('TURNO', _turnoSeleccionado, _listaTurnos, (val) => setState(() => _turnoSeleccionado = val!)),
          _buildSearchableDropdown('SUPERVISOR', _supervisorSeleccionado, _listaSupervisores, (val) => setState(() => _supervisorSeleccionado = val!)),
          _buildSearchableDropdown('OPERADOR', _operadorSeleccionado, _listaOperadores, (val) => setState(() => _operadorSeleccionado = val!)),
          _buildSearchableDropdown('ÁREA', _areaSeleccionada, _listaAreas, (val) => setState(() => _areaSeleccionada = val!)),
          _buildSearchableDropdown('ORIGEN OPM', _origenSeleccionado, _listaOrigenes, (val) => setState(() => _origenSeleccionado = val!)),

          // Botones (Se eliminó RECARGAR BD y se ajustó el contenedor)
          SizedBox(
            height: 52, // Misma altura que los TextFields
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.filter_alt_rounded, size: 20),
                  label: const Text('FILTRAR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _tomarFoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, size: 22),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _activarModoTV,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.tv_rounded, size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoFecha(String titulo, DateTime fecha, Function(DateTime) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: fecha,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) onSelect(picked);
          },
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_rounded, size: 20, color: Colors.blueGrey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchableDropdown(String titulo, String valorActual, List<String> opciones, Function(String?) onChanged) {
    if (!opciones.contains(valorActual)) {
      valorActual = 'Todos';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        DropdownMenu<String>(
          initialSelection: valorActual,
          onSelected: onChanged,
          dropdownMenuEntries: opciones.map((e) => DropdownMenuEntry(value: e, label: e)).toList(),
          width: titulo == 'OPERADOR' || titulo == 'SUPERVISOR' ? 260 : 200,
          menuHeight: 350,
          enableFilter: true,
          enableSearch: true,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          inputDecorationTheme: InputDecorationTheme(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 📈 2. TARJETAS KPI
  // ---------------------------------------------------------------------------
  Widget _buildKpiCards(List<Map<String, dynamic>> datos) {
    int totalEventos = datos.length;

    Set<String> personasUnicas = datos
        .map((e) => e['nombre']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();
    int persInvolucradas = personasUnicas.length;

    Map<String, int> conteoAlertas = {};
    for (var item in datos) {
      String evento = _normalizarEvento(item['evento']?.toString() ?? 'DESCONOCIDO');
      conteoAlertas[evento] = (conteoAlertas[evento] ?? 0) + 1;
    }

    List<Widget> tarjetas = [
      _buildKpiCard('TOTAL EVENTOS', '$totalEventos', const Color(0xFF2563EB)),
      _buildKpiCard('PERS. INVOLUCRADAS', '$persInvolucradas', const Color(0xFF059669)),
    ];

    List<Color> coloresAlertas = [
      const Color(0xFFD97706),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
      const Color(0xFF0891B2),
      const Color(0xFFEA580C),
      const Color(0xFF4F46E5),
    ];

    int colorIndex = 0;
    conteoAlertas.forEach((alerta, cantidad) {
      tarjetas.add(_buildKpiCard(alerta, '$cantidad', coloresAlertas[colorIndex % coloresAlertas.length]));
      colorIndex++;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        double minCardWidth = 260.0;
        double widthNecesario = tarjetas.length * minCardWidth + ((tarjetas.length - 1) * 16);

        if (widthNecesario <= constraints.maxWidth) {
          return Row(
            children: tarjetas.map((t) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: t == tarjetas.last ? 0 : 20.0),
                  child: t,
                ),
              );
            }).toList(),
          );
        } else {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tarjetas.map((t) {
                return Padding(
                  padding: EdgeInsets.only(right: t == tarjetas.last ? 0 : 20.0),
                  child: SizedBox(
                    width: minCardWidth,
                    child: t,
                  ),
                );
              }).toList(),
            ),
          );
        }
      },
    );
  }

  Widget _buildKpiCard(String titulo, String valor, Color colorBorde) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 54,
            decoration: BoxDecoration(color: colorBorde, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  valor,
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📊 FILA 1: GRÁFICAS (Semanal, Mensual, Diaria, Radial)
  // ---------------------------------------------------------------------------
  Widget _buildFilaGraficas(BuildContext context, List<Map<String, dynamic>> datos) {

    Map<String, int> eventosPorSemana = {};
    for (var item in datos) {
      DateTime d = item['fecha_dt'] as DateTime;
      DateTime startOfWeek = d.subtract(Duration(days: d.weekday - 1));
      String key = "${startOfWeek.year}-${startOfWeek.month.toString().padLeft(2,'0')}-${startOfWeek.day.toString().padLeft(2,'0')}";
      eventosPorSemana[key] = (eventosPorSemana[key] ?? 0) + 1;
    }

    List<String> labelsSemanas = [];
    List<int> conteoPorSemana = [];
    DateTime cursorSemana = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
    cursorSemana = cursorSemana.subtract(Duration(days: cursorSemana.weekday - 1));
    DateTime finSemana = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day);

    while (!cursorSemana.isAfter(finSemana)) {
      String label = "${cursorSemana.day.toString().padLeft(2, '0')}/${cursorSemana.month.toString().padLeft(2, '0')}";
      labelsSemanas.add(label);
      String key = "${cursorSemana.year}-${cursorSemana.month.toString().padLeft(2,'0')}-${cursorSemana.day.toString().padLeft(2,'0')}";
      conteoPorSemana.add(eventosPorSemana[key] ?? 0);
      cursorSemana = cursorSemana.add(const Duration(days: 7));
    }

    List<FlSpot> weeklySpots = [];
    for (int i = 0; i < conteoPorSemana.length; i++) {
      weeklySpots.add(FlSpot(i.toDouble(), conteoPorSemana[i].toDouble()));
    }

    final weeklyBarData = LineChartBarData(
      spots: weeklySpots,
      isCurved: true,
      color: const Color(0xFF8B5CF6),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: true, color: const Color(0xFF8B5CF6).withOpacity(0.1)),
    );


    List<int> mesesOrdenados = [];
    DateTime temp = DateTime(_fechaDesde.year, _fechaDesde.month, 1);
    DateTime finMes = DateTime(_fechaHasta.year, _fechaHasta.month, 1);
    while (!temp.isAfter(finMes)) {
      if (!mesesOrdenados.contains(temp.month)) mesesOrdenados.add(temp.month);
      temp = DateTime(temp.year, temp.month + 1, 1);
    }

    Map<int, int> conteoMensual = { for (var m in mesesOrdenados) m: 0 };
    for (var item in datos) {
      DateTime d = item['fecha_dt'] as DateTime;
      if(conteoMensual.containsKey(d.month)) {
        conteoMensual[d.month] = (conteoMensual[d.month] ?? 0) + 1;
      }
    }

    const nombresMeses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    List<BarChartGroupData> monthlyBars = [];
    for (int i = 0; i < mesesOrdenados.length; i++) {
      monthlyBars.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: conteoMensual[mesesOrdenados[i]]!.toDouble(),
            color: const Color(0xFF2563EB),
            width: mesesOrdenados.length > 6 ? 24 : 45,
            borderRadius: BorderRadius.circular(6),
          )
        ],
        showingTooltipIndicators: [0],
      ));
    }


    Map<String, int> eventosPorFecha = {};
    for (var item in datos) {
      DateTime d = item['fecha_dt'] as DateTime;
      String key = "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}";
      eventosPorFecha[key] = (eventosPorFecha[key] ?? 0) + 1;
    }

    List<String> labelsFechas = [];
    List<int> conteoPorDia = [];
    DateTime cursor = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
    DateTime fin = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day);

    while (!cursor.isAfter(fin)) {
      String label = cursor.day.toString().padLeft(2, '0');
      labelsFechas.add(label);
      String key = "${cursor.year}-${cursor.month.toString().padLeft(2,'0')}-${cursor.day.toString().padLeft(2,'0')}";
      conteoPorDia.add(eventosPorFecha[key] ?? 0);
      cursor = cursor.add(const Duration(days: 1));
    }

    List<FlSpot> dailySpots = [];
    for (int i = 0; i < conteoPorDia.length; i++) {
      dailySpots.add(FlSpot(i.toDouble(), conteoPorDia[i].toDouble()));
    }

    final dailyBarData = LineChartBarData(
      spots: dailySpots,
      isCurved: true,
      color: const Color(0xFFE11D48),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: true, color: const Color(0xFFE11D48).withOpacity(0.1)),
    );


    Map<int, int> eventosPorDiaSemana = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
    for (var item in datos) {
      DateTime d = item['fecha_dt'] as DateTime;
      eventosPorDiaSemana[d.weekday] = (eventosPorDiaSemana[d.weekday] ?? 0) + 1;
    }

    double containerHeight = 260;
    bool isWide = MediaQuery.of(context).size.width > 1100;

    Widget graficaSemanal = Container(
      height: containerHeight,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Eventos por Semana', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: weeklySpots.isNotEmpty
                ? LayoutBuilder(
                builder: (context, constr) {
                  double minWidthRequired = weeklySpots.length * 55.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: minWidthRequired > constr.maxWidth ? minWidthRequired : constr.maxWidth,
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [weeklyBarData],
                          showingTooltipIndicators: weeklySpots.map((spot) => ShowingTooltipIndicators([LineBarSpot(weeklyBarData, 0, spot)])).toList(),
                          lineTouchData: LineTouchData(
                            enabled: false,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (touchedSpot) => Colors.transparent,
                              tooltipPadding: EdgeInsets.zero,
                              tooltipMargin: 8,
                              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(s.y.toInt().toString(), const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 14))).toList(),
                            ),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                reservedSize: 36,
                                getTitlesWidget: (value, meta) {
                                  int idx = value.toInt();
                                  if (idx >= 0 && idx < labelsSemanas.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: Text(labelsSemanas[idx], style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  );
                }
            )
                : const Center(child: Text("Sin datos", style: TextStyle(fontSize: 16))),
          ),
        ],
      ),
    );

    Widget graficaMensual = Container(
      height: containerHeight,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total por Mes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: monthlyBars.isNotEmpty
                ? BarChart(
              BarChartData(
                barGroups: monthlyBars,
                barTouchData: BarTouchData(
                  enabled: false,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.transparent,
                    tooltipPadding: EdgeInsets.zero,
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(rod.toY.round().toString(), const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, meta) {
                        int idx = value.toInt();
                        if (idx >= 0 && idx < mesesOrdenados.length) {
                          int mesReal = mesesOrdenados[idx] - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 10.0),
                            child: Text(nombresMeses[mesReal], style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            )
                : const Center(child: Text("Sin datos", style: TextStyle(fontSize: 16))),
          ),
        ],
      ),
    );

    Widget graficaDiaria = Container(
      height: containerHeight,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Eventos por Día', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: dailySpots.isNotEmpty
                ? LayoutBuilder(
                builder: (context, constr) {
                  double minWidthRequired = dailySpots.length * 45.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: minWidthRequired > constr.maxWidth ? minWidthRequired : constr.maxWidth,
                      child: LineChart(
                        LineChartData(
                          lineBarsData: [dailyBarData],
                          showingTooltipIndicators: dailySpots.map((spot) => ShowingTooltipIndicators([LineBarSpot(dailyBarData, 0, spot)])).toList(),
                          lineTouchData: LineTouchData(
                            enabled: false,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (touchedSpot) => Colors.transparent,
                              tooltipPadding: EdgeInsets.zero,
                              tooltipMargin: 8,
                              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(s.y.toInt().toString(), const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold, fontSize: 14))).toList(),
                            ),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                reservedSize: 36,
                                getTitlesWidget: (value, meta) {
                                  int idx = value.toInt();
                                  if (idx >= 0 && idx < labelsFechas.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: Text(labelsFechas[idx], style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                  );
                }
            )
                : const Center(child: Text("Sin datos", style: TextStyle(fontSize: 16))),
          ),
        ],
      ),
    );

    Widget graficaRadialDias = Container(
      height: containerHeight,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Distribución por Días', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: const Color(0xFF059669).withOpacity(0.25),
                    borderColor: const Color(0xFF059669),
                    entryRadius: 3.5,
                    borderWidth: 2,
                    dataEntries: List.generate(
                      7,
                          (i) => RadarEntry(value: eventosPorDiaSemana[i + 1]!.toDouble()),
                    ),
                  )
                ],
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                radarBorderData: const BorderSide(color: Colors.transparent),
                titlePositionPercentageOffset: 0.15,
                getTitle: (index, angle) {
                  const dias = ['LUN', 'MAR', 'MIE', 'JUE', 'VIE', 'SAB', 'DOM'];
                  int cantidad = eventosPorDiaSemana[index + 1] ?? 0;
                  return RadarChartTitle(
                    text: '${dias[index]}\n($cantidad)',
                    angle: 0,
                  );
                },
                titleTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                tickCount: 3,
                ticksTextStyle: const TextStyle(fontSize: 10, color: Colors.transparent),
                tickBorderData: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                gridBorderData: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );

    Widget fila1 = isWide
        ? Row(children: [Expanded(flex: 3, child: graficaSemanal), const SizedBox(width: 24), Expanded(flex: 2, child: graficaMensual)])
        : Column(children: [graficaSemanal, const SizedBox(height: 24), graficaMensual]);

    Widget fila2 = isWide
        ? Row(children: [Expanded(flex: 3, child: graficaDiaria), const SizedBox(width: 24), Expanded(flex: 2, child: graficaRadialDias)])
        : Column(children: [graficaDiaria, const SizedBox(height: 24), graficaRadialDias]);

    return Column(
      children: [
        fila1,
        const SizedBox(height: 24),
        fila2,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 FILA 2: TABLAS PRINCIPALES CON ORDENAMIENTO (TURNOS, SUPERVISORES, OPERADORES)
  // ---------------------------------------------------------------------------
  Widget _buildFilaTablasPrincipales(BuildContext context, List<Map<String, dynamic>> datos) {
    bool isWide = MediaQuery.of(context).size.width > 1400;
    int total = datos.isEmpty ? 1 : datos.length;

    // TURNO
    int t1 = datos.where((e) => e['turno'] == 'T1').length;
    int t2 = datos.where((e) => e['turno'] == 'T2').length;
    int t3 = datos.where((e) => e['turno'] == 'T3').length;

    List<List<String>> filasTurno = [
      ['T1', '$t1', '${((t1 / total) * 100).toStringAsFixed(1)}%'],
      ['T2', '$t2', '${((t2 / total) * 100).toStringAsFixed(1)}%'],
      ['T3', '$t3', '${((t3 / total) * 100).toStringAsFixed(1)}%'],
    ];

    Widget tablaTurno = _buildTablaSortable(
      titulo: 'Resumen por Turno',
      headers: ['TURNO', 'EVENTOS', '% TOTAL'],
      minWidths: [2, 3, 3],
      filasIniciales: filasTurno,
      height: 480,
      mostrarTotal: true,
      calcularTotales: (filas) {
        int sumTotal = 0;
        for (var f in filas) { sumTotal += int.parse(f[1]); }
        return ['TOTALES', '$sumTotal', '100%'];
      },
    );

    Set<String> eventosSet = {};
    for(var d in datos) {
      eventosSet.add(_normalizarEvento(d['evento']?.toString() ?? ''));
    }
    List<String> columnasEventos = eventosSet.toList()..sort();
    List<double> anchosEventos = List.generate(columnasEventos.length, (index) => 3.0);

    int anioObjetivo = _fechaHasta.year;
    Map<String, int> supervisorTotalAno = {};
    Map<String, int> operadorTotalAno = {};

    for (var d in _reportesFms) {
      DateTime fecha = d['fecha_dt'] as DateTime;
      if (fecha.year == anioObjetivo) {
        String sup = d['supervisor']?.toString().trim() ?? 'SIN SUPERVISOR';
        String op = d['nombre']?.toString().trim() ?? 'SIN NOMBRE';

        if (sup.isEmpty) sup = 'SIN SUPERVISOR';
        if (op.isEmpty) op = 'SIN NOMBRE';

        supervisorTotalAno[sup] = (supervisorTotalAno[sup] ?? 0) + 1;
        operadorTotalAno[op] = (operadorTotalAno[op] ?? 0) + 1;
      }
    }

    Map<String, Map<String, int>> supData = {};
    Map<String, int> supTotal = {};

    for (var d in datos) {
      String sup = d['supervisor']?.toString().trim() ?? 'SIN SUPERVISOR';
      if (sup.isEmpty) sup = 'SIN SUPERVISOR';
      String ev = _normalizarEvento(d['evento']?.toString() ?? '');

      if (!supData.containsKey(sup)) {
        supData[sup] = { for (var e in columnasEventos) e : 0 };
        supTotal[sup] = 0;
      }
      supData[sup]![ev] = (supData[sup]![ev] ?? 0) + 1;
      supTotal[sup] = (supTotal[sup] ?? 0) + 1;
    }

    var supActivos = supTotal.keys.toList();
    List<List<String>> filasSup = supActivos.map((sup) {
      return [
        sup,
        ...columnasEventos.map((ev) => supData[sup]![ev].toString()),
        supTotal[sup].toString(),
        (supervisorTotalAno[sup] ?? 0).toString()
      ];
    }).toList();

    Widget tablaSupervisores = _buildTablaSortable(
      titulo: 'Eventos por Supervisor',
      headers: ['SUPERVISOR', ...columnasEventos, 'TOTAL MES', 'TOTAL AÑO'],
      minWidths: [6, ...anchosEventos, 3, 3],
      filasIniciales: filasSup,
      height: 480,
      mostrarTotal: true,
      calcularTotales: (filas) {
        List<String> totales = ['TOTALES'];
        for (int i = 0; i < columnasEventos.length; i++) {
          int sum = 0;
          for (var f in filas) { sum += int.parse(f[i + 1]); }
          totales.add(sum.toString());
        }
        int sumTotal = 0, sumAno = 0;
        for (var f in filas) {
          sumTotal += int.parse(f[f.length - 2]);
          sumAno += int.parse(f[f.length - 1]);
        }
        totales.add(sumTotal.toString());
        totales.add(sumAno.toString());
        return totales;
      },
    );

    Map<String, Map<String, int>> opData = {};
    Map<String, int> opTotal = {};

    for (var d in datos) {
      String op = d['nombre']?.toString().trim() ?? 'SIN NOMBRE';
      if (op.isEmpty) op = 'SIN NOMBRE';
      String ev = _normalizarEvento(d['evento']?.toString() ?? '');

      if (!opData.containsKey(op)) {
        opData[op] = { for (var e in columnasEventos) e : 0 };
        opTotal[op] = 0;
      }
      opData[op]![ev] = (opData[op]![ev] ?? 0) + 1;
      opTotal[op] = (opTotal[op] ?? 0) + 1;
    }

    var opActivos = opTotal.keys.toList();
    List<List<String>> filasOp = opActivos.map((op) {
      return [
        op,
        ...columnasEventos.map((ev) => opData[op]![ev].toString()),
        opTotal[op].toString(),
        (operadorTotalAno[op] ?? 0).toString()
      ];
    }).toList();

    Widget tablaOperadores = _buildTablaSortable(
      titulo: 'Eventos por Operador',
      headers: ['OPERADOR', ...columnasEventos, 'TOTAL MES', 'TOTAL AÑO'],
      minWidths: [6, ...anchosEventos, 3, 3],
      filasIniciales: filasOp,
      height: 480,
      mostrarTotal: true,
      calcularTotales: (filas) {
        List<String> totales = ['TOTALES'];
        for (int i = 0; i < columnasEventos.length; i++) {
          int sum = 0;
          for (var f in filas) { sum += int.parse(f[i + 1]); }
          totales.add(sum.toString());
        }
        int sumTotal = 0, sumAno = 0;
        for (var f in filas) {
          sumTotal += int.parse(f[f.length - 2]);
          sumAno += int.parse(f[f.length - 1]);
        }
        totales.add(sumTotal.toString());
        totales.add(sumAno.toString());
        return totales;
      },
    );

    return SizedBox(
      width: double.infinity,
      child: isWide
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: tablaTurno),
          const SizedBox(width: 24),
          Expanded(flex: 6, child: tablaSupervisores),
          const SizedBox(width: 24),
          Expanded(flex: 7, child: tablaOperadores)
        ],
      )
          : Column(
        children: [
          tablaTurno, const SizedBox(height: 24),
          tablaSupervisores, const SizedBox(height: 24),
          tablaOperadores
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 FILA 3: TABLAS SECUNDARIAS
  // ---------------------------------------------------------------------------
  Widget _buildFilaTablasSecundarias(BuildContext context, List<Map<String, dynamic>> datos) {
    bool isWide = MediaQuery.of(context).size.width > 1100;
    int total = datos.isEmpty ? 1 : datos.length;

    Map<String, int> conteoEventos = {};
    for(var d in datos) {
      String ev = _normalizarEvento(d['evento']?.toString() ?? 'SIN EVENTO');
      conteoEventos[ev] = (conteoEventos[ev] ?? 0) + 1;
    }
    List<List<String>> filasEv = conteoEventos.keys.map((e) => [e, conteoEventos[e].toString(), '${((conteoEventos[e]!/total)*100).toStringAsFixed(1)}%']).toList();

    Map<String, int> conteoAreas = {};
    for(var d in datos) {
      String ar = d['area']?.toString().trim() ?? 'SIN ÁREA';
      if(ar.isEmpty) ar = 'SIN ÁREA';
      conteoAreas[ar] = (conteoAreas[ar] ?? 0) + 1;
    }
    List<List<String>> filasAr = conteoAreas.keys.map((a) => [a, conteoAreas[a].toString(), '${((conteoAreas[a]!/total)*100).toStringAsFixed(1)}%']).toList();

    Map<String, int> conteoOrigen = {};
    for(var d in datos) {
      String or = d['origen_opm']?.toString().trim() ?? 'SIN ORIGEN';
      if(or.isEmpty) or = 'SIN ORIGEN';
      conteoOrigen[or] = (conteoOrigen[or] ?? 0) + 1;
    }
    List<List<String>> filasOr = conteoOrigen.keys.map((o) => [o, conteoOrigen[o].toString(), '${((conteoOrigen[o]!/total)*100).toStringAsFixed(1)}%']).toList();

    List<String> Function(List<List<String>>) calculadorBasicoTotales = (filas) {
      int sumTotal = 0;
      for (var f in filas) { sumTotal += int.parse(f[1]); }
      return ['TOTALES', '$sumTotal', '100%'];
    };

    return SizedBox(
      width: double.infinity,
      child: isWide
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: _buildTablaSortable(titulo: 'Tipos de Evento', headers: ['EVENTO', 'TOTAL', '% GRAL'], minWidths: [4, 2, 2], filasIniciales: filasEv, height: 420, mostrarTotal: true, calcularTotales: calculadorBasicoTotales)),
          const SizedBox(width: 24),
          Expanded(flex: 1, child: _buildTablaSortable(titulo: 'Áreas de Ocurrencia', headers: ['ÁREA', 'TOTAL', '% GRAL'], minWidths: [4, 2, 2], filasIniciales: filasAr, height: 420, mostrarTotal: true, calcularTotales: calculadorBasicoTotales)),
          const SizedBox(width: 24),
          Expanded(flex: 1, child: _buildTablaSortable(titulo: 'Origen del OPM', headers: ['ORIGEN OPM', 'TOTAL', '% GRAL'], minWidths: [4, 2, 2], filasIniciales: filasOr, height: 420, mostrarTotal: true, calcularTotales: calculadorBasicoTotales))
        ],
      )
          : Column(
        children: [
          _buildTablaSortable(titulo: 'Tipos de Evento', headers: ['EVENTO', 'TOTAL', '% GRAL'], minWidths: [4, 2, 2], filasIniciales: filasEv, height: 420, mostrarTotal: true, calcularTotales: calculadorBasicoTotales),
          const SizedBox(height: 24),
          _buildTablaSortable(titulo: 'Áreas de Ocurrencia', headers: ['ÁREA', 'TOTAL', '% GRAL'], minWidths: [4, 2, 2], filasIniciales: filasAr, height: 420, mostrarTotal: true, calcularTotales: calculadorBasicoTotales),
          const SizedBox(height: 24),
          _buildTablaSortable(titulo: 'Origen del OPM', headers: ['ORIGEN OPM', 'TOTAL', '% GRAL'], minWidths: [4, 2, 2], filasIniciales: filasOr, height: 420, mostrarTotal: true, calcularTotales: calculadorBasicoTotales)
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 FILA 4: TABLA DETALLE (CON STATEFUL LOCAL PARA ORDENAMIENTO INDEPENDIENTE)
  // ---------------------------------------------------------------------------
  Widget _buildTablaDetalleCompletoStateful(List<Map<String, dynamic>> datos) {
    List<String> headers = ['FECHA', 'HORA', 'TURNO', 'MÁQUINA', 'ÁREA', 'OPERADOR', 'ORIGEN', 'ALERTA', 'SUPERVISOR'];
    List<double> flexWidths = [3, 2, 2, 3, 4, 5, 3, 4, 5];

    List<List<String>> filasIniciales = datos.map((item) {
      return [
        _formatearFechaLimpia(item['fecha']),
        item['hora']?.toString() ?? '',
        item['turno']?.toString() ?? '',
        item['maquina']?.toString() ?? '',
        item['area']?.toString() ?? '',
        item['nombre']?.toString() ?? '',
        item['origen_opm']?.toString() ?? '',
        _normalizarEvento(item['evento']?.toString() ?? ''), // Aplicamos la abreviatura aquí también
        item['supervisor']?.toString() ?? '',
      ];
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 40),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Reporte Detallado FMS Diario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _descargarExcel(datos),
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: const Text('DESCARGAR EXCEL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF107C41),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text('${datos.length} Registros', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 600,
              child: _buildTablaSortableCore(
                headers: headers,
                minWidths: flexWidths,
                filasIniciales: filasIniciales,
                mostrarTotal: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💡 MOTOR DE TABLAS "PRO" (CON SORTING Y TOTALES DINÁMICOS - COMPONENTE AISLADO)
  // ---------------------------------------------------------------------------
  Widget _buildTablaSortable({
    required String titulo,
    required List<String> headers,
    required List<double> minWidths,
    required List<List<String>> filasIniciales,
    required double height,
    required bool mostrarTotal,
    List<String> Function(List<List<String>>)? calcularTotales,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          Expanded(
            child: _buildTablaSortableCore(
              headers: headers,
              minWidths: minWidths,
              filasIniciales: filasIniciales,
              mostrarTotal: mostrarTotal,
              calcularTotales: calcularTotales,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTablaSortableCore({
    required List<String> headers,
    required List<double> minWidths,
    required List<List<String>> filasIniciales,
    required bool mostrarTotal,
    List<String> Function(List<List<String>>)? calcularTotales,
  }) {
    List<List<String>> filasLocales = List.from(filasIniciales);
    int sortColumnIndex = -1;
    bool isAscending = true;

    if (filasLocales.isNotEmpty) {
      int targetIndex = headers.indexOf('TOTAL MES');
      if (targetIndex == -1) targetIndex = headers.indexOf('TOTAL');

      if (targetIndex != -1) {
        sortColumnIndex = targetIndex;
        isAscending = false;
        filasLocales.sort((a, b) {
          int aInt = int.tryParse(a[sortColumnIndex].replaceAll('%', '')) ?? 0;
          int bInt = int.tryParse(b[sortColumnIndex].replaceAll('%', '')) ?? 0;
          return bInt.compareTo(aInt);
        });
      }
    }

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setStateLocal) {
        void sort(int columnIndex) {
          setStateLocal(() {
            if (sortColumnIndex == columnIndex) {
              isAscending = !isAscending;
            } else {
              sortColumnIndex = columnIndex;
              isAscending = true;
            }

            filasLocales.sort((a, b) {
              String valA = a[columnIndex];
              String valB = b[columnIndex];
              bool isNumeric = int.tryParse(valA.replaceAll('%', '')) != null && int.tryParse(valB.replaceAll('%', '')) != null;

              int result;
              if (isNumeric) {
                result = double.parse(valA.replaceAll('%', '')).compareTo(double.parse(valB.replaceAll('%', '')));
              } else {
                result = valA.compareTo(valB);
              }
              return isAscending ? result : -result;
            });
          });
        }

        List<String>? filaTotal;
        if (mostrarTotal && calcularTotales != null && filasLocales.isNotEmpty) {
          filaTotal = calcularTotales(filasLocales);
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                // ENCABEZADOS
                Container(
                  color: const Color(0xFF1E293B),
                  child: Row(
                    children: List.generate(headers.length, (i) {
                      return Expanded(
                        flex: minWidths[i].toInt(),
                        child: InkWell(
                          onTap: () => sort(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    headers[i],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (sortColumnIndex == i)
                                  Icon(
                                    isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                    color: Colors.blueAccent,
                                    size: 14,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // FILAS
                Expanded(
                  child: ListView.builder(
                    itemCount: filasLocales.length,
                    itemBuilder: (context, index) {
                      final fila = filasLocales[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: index % 2 != 0 ? const Color(0xFFF8FAFC) : Colors.white,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Row(
                          children: List.generate(fila.length, (i) {
                            bool isTurnoCol = headers[i] == 'TURNO';
                            bool isAlerta = headers[i] == 'ALERTA';
                            bool isOperador = headers[i] == 'OPERADOR' || headers[i] == 'SUPERVISOR';
                            bool isFirst = i == 0;

                            Widget cellContent = Text(
                              fila[i],
                              textAlign: isFirst && isOperador ? TextAlign.left : TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: (isAlerta || isOperador) ? FontWeight.bold : FontWeight.w500,
                                color: isAlerta ? Colors.redAccent : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            );

                            if (isTurnoCol && (fila[i] == 'T1' || fila[i] == 'T2' || fila[i] == 'T3')) {
                              Color badgeC = fila[i] == 'T1' ? const Color(0xFF2563EB) : (fila[i] == 'T2' ? const Color(0xFFD97706) : const Color(0xFF7C3AED));
                              cellContent = Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: badgeC, borderRadius: BorderRadius.circular(12)),
                                child: Text(fila[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              );
                            }

                            return Expanded(
                              flex: minWidths[i].toInt(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                alignment: isFirst && isOperador ? Alignment.centerLeft : Alignment.center,
                                child: cellContent,
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ),
                // FILA DE TOTALES
                if (filaTotal != null)
                  Container(
                    color: const Color(0xFFE2E8F0),
                    child: Row(
                      children: List.generate(filaTotal.length, (i) {
                        return Expanded(
                          flex: minWidths[i].toInt(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            alignment: i == 0 ? Alignment.centerRight : Alignment.center,
                            child: Text(
                              filaTotal![i],
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }),
                    ),
                  )
              ],
            ),
          ),
        );
      },
    );
  }
}