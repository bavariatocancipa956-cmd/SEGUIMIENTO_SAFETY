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

      List<Map<String, dynamic>> dataCalculada = _calcularReincidenciasOptimizadas(dataLista);

      Set<String> ops = {'Todos'};
      Set<String> sups = {'Todos'};
      Set<String> areas = {'Todos'};
      Set<String> origenes = {'Todos'};

      for (var d in dataCalculada) {
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

        _reportesFms = dataCalculada;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al conectar con la API: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _calcularReincidenciasOptimizadas(List<Map<String, dynamic>> dataRows) {
    Map<String, int> conteoAno = {};
    Map<String, int> conteoMes = {};

    for (var row in dataRows) {
      if (row['nombre'] == null) continue;
      String nombre = row['nombre'].toString();
      DateTime d = row['fecha_dt'] as DateTime;
      String keyAno = "${nombre}_${d.year}";
      String keyMes = "${nombre}_${d.year}_${d.month}";
      conteoAno[keyAno] = (conteoAno[keyAno] ?? 0) + 1;
      conteoMes[keyMes] = (conteoMes[keyMes] ?? 0) + 1;
    }

    for (var row in dataRows) {
      if (row['nombre'] == null) {
        row['reinc_mes'] = 0;
        row['reinc_ano'] = 0;
        continue;
      }
      String nombre = row['nombre'].toString();
      DateTime d = row['fecha_dt'] as DateTime;
      String keyAno = "${nombre}_${d.year}";
      String keyMes = "${nombre}_${d.year}_${d.month}";
      row['reinc_mes'] = conteoMes[keyMes] ?? 0;
      row['reinc_ano'] = conteoAno[keyAno] ?? 0;
    }

    return dataRows;
  }

  String _normalizarEvento(String raw) {
    String ev = raw.toUpperCase().trim();
    ev = ev.replaceAll('Á', 'A').replaceAll('É', 'E').replaceAll('Í', 'I').replaceAll('Ó', 'O').replaceAll('Ú', 'U');
    if (ev.contains('ACELERACI')) return 'ACELERACION';
    if (ev.contains('IMPACTO')) return 'IMPACTO';
    if (ev.contains('FRENAD')) return 'FRENADA';
    if (ev.contains('VELOCIDAD') || ev.contains('EXCESO')) return 'EXCESO VELOCIDAD';
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
      String evento = '"${(item['evento']?.toString() ?? '').replaceAll('"', '""')}"';
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
              _buildTablaDetalleCompleto(datosActuales),
            ]
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💡 MOTOR DE TABLAS "PRO"
  // ---------------------------------------------------------------------------
  Widget _buildTablaPro({
    required String titulo,
    required List<String> headers,
    required List<double> minWidths,
    required List<List<String>> filas,
    required double height,
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
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LayoutBuilder(
                    builder: (context, constraints) {
                      double totalWidth = minWidths.fold(0, (s, w) => s + w);
                      List<double> finalWidths = List.from(minWidths);

                      if (totalWidth < constraints.maxWidth) {
                        finalWidths[0] += (constraints.maxWidth - totalWidth);
                        totalWidth = constraints.maxWidth;
                      }

                      Widget tableContent = Column(
                        children: [
                          Container(
                            color: const Color(0xFF1E293B),
                            child: Row(
                              children: List.generate(headers.length, (i) {
                                return Container(
                                  width: finalWidths[i],
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  alignment: i == 0 ? Alignment.centerLeft : Alignment.center,
                                  child: Text(headers[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
                                );
                              }),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: filas.length,
                              itemBuilder: (context, index) {
                                final fila = filas[index];
                                return Container(
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                                  child: Row(
                                    children: List.generate(fila.length, (i) {
                                      bool isFirst = i == 0;
                                      bool isLast = i == fila.length - 1;

                                      Widget cellContent = Text(
                                        fila[i],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isFirst ? FontWeight.w600 : FontWeight.w500,
                                          color: (headers[i].contains('REINC') && fila[i] != '0') ? Colors.red.shade700 : (isLast ? Colors.blueGrey.shade700 : Colors.black87),
                                        ),
                                      );

                                      if (isFirst && (fila[i] == 'T1' || fila[i] == 'T2' || fila[i] == 'T3')) {
                                        Color badgeC = fila[i] == 'T1' ? const Color(0xFF2563EB) : (fila[i] == 'T2' ? const Color(0xFFD97706) : const Color(0xFF7C3AED));
                                        cellContent = Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                          decoration: BoxDecoration(color: badgeC, borderRadius: BorderRadius.circular(16)),
                                          child: Text(fila[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        );
                                      }

                                      return Container(
                                        width: finalWidths[i],
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        alignment: isFirst ? Alignment.centerLeft : Alignment.center,
                                        child: cellContent,
                                      );
                                    }),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalWidth,
                          child: tableContent,
                        ),
                      );
                    }
                ),
              ),
            ),
          ),
        ],
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
        spacing: 20,
        runSpacing: 20,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _buildCampoFecha('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d)),
          _buildCampoFecha('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d)),

          _buildSearchableDropdown('TURNO', _turnoSeleccionado, _listaTurnos, (val) => setState(() => _turnoSeleccionado = val!)),
          _buildSearchableDropdown('SUPERVISOR', _supervisorSeleccionado, _listaSupervisores, (val) => setState(() => _supervisorSeleccionado = val!)),
          _buildSearchableDropdown('OPERADOR', _operadorSeleccionado, _listaOperadores, (val) => setState(() => _operadorSeleccionado = val!)),
          _buildSearchableDropdown('ÁREA', _areaSeleccionada, _listaAreas, (val) => setState(() => _areaSeleccionada = val!)),
          _buildSearchableDropdown('ORIGEN OPM', _origenSeleccionado, _listaOrigenes, (val) => setState(() => _origenSeleccionado = val!)),

          Container(
            height: 52,
            margin: const EdgeInsets.only(top: 8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _cargarDatosBD,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('RECARGAR BD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF475569),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
  // 📊 FILA 1: GRÁFICAS
  // ---------------------------------------------------------------------------
  Widget _buildFilaGraficas(BuildContext context, List<Map<String, dynamic>> datos) {
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

    final lineBarData = LineChartBarData(
      spots: dailySpots,
      isCurved: true,
      color: const Color(0xFFE11D48),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: true, color: const Color(0xFFE11D48).withOpacity(0.1)),
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

    double containerHeight = 420;
    bool isWide = MediaQuery.of(context).size.width > 900;

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
          const Text('Eventos FMS por Día (Línea Continua)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 40),
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
                          lineBarsData: [lineBarData],
                          showingTooltipIndicators: dailySpots.map((spot) => ShowingTooltipIndicators([LineBarSpot(lineBarData, 0, spot)])).toList(),
                          lineTouchData: LineTouchData(
                            enabled: false,
                            getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes.map((i) => TouchedSpotIndicatorData(const FlLine(color: Colors.transparent), const FlDotData(show: false))).toList(),
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
                                      child: Text(labelsFechas[idx], style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
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
                                reservedSize: 40,
                                getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
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
                : const Center(child: Text("Sin datos para este rango", style: TextStyle(fontSize: 16))),
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
          const Text('Total de Eventos por Mes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 40),
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
                            child: Text(nombresMeses[mesReal], style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
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
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
              ),
            )
                : const Center(child: Text("Sin datos para este rango", style: TextStyle(fontSize: 16))),
          ),
        ],
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: isWide
          ? Row(children: [Expanded(flex: 3, child: graficaDiaria), const SizedBox(width: 24), Expanded(flex: 2, child: graficaMensual)])
          : Column(children: [graficaDiaria, const SizedBox(height: 24), graficaMensual]),
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 FILA 2: TABLAS PRINCIPALES (TURNOS, SUPERVISORES, OPERADORES)
  // ---------------------------------------------------------------------------
  Widget _buildFilaTablasPrincipales(BuildContext context, List<Map<String, dynamic>> datos) {
    bool isWide = MediaQuery.of(context).size.width > 1200;
    int total = datos.isEmpty ? 1 : datos.length;

    int t1 = datos.where((e) => e['turno'] == 'T1').length;
    int t2 = datos.where((e) => e['turno'] == 'T2').length;
    int t3 = datos.where((e) => e['turno'] == 'T3').length;

    Widget tablaTurno = _buildTablaPro(
      titulo: 'Resumen por Turno',
      headers: ['TURNO', 'EVENTOS', '% TOTAL'],
      minWidths: [90, 110, 110],
      filas: [
        ['T1', '$t1', '${((t1 / total) * 100).toStringAsFixed(1)}%'],
        ['T2', '$t2', '${((t2 / total) * 100).toStringAsFixed(1)}%'],
        ['T3', '$t3', '${((t3 / total) * 100).toStringAsFixed(1)}%'],
      ],
      height: 480,
    );

    Set<String> eventosSet = {};
    for(var d in datos) {
      eventosSet.add(_normalizarEvento(d['evento']?.toString() ?? ''));
    }
    List<String> columnasEventos = eventosSet.toList()..sort();
    List<double> anchosEventos = List.generate(columnasEventos.length, (index) => 120.0);

    Map<String, Map<String, int>> supData = {};
    Map<String, int> supTotal = {};
    Map<String, int> supReincAno = {};
    for(var s in _listaSupervisores.where((s) => s != 'Todos')) {
      supData[s] = { for (var e in columnasEventos) e : 0 };
      supTotal[s] = 0;
      supReincAno[s] = 0;
    }
    for(var d in datos) {
      String sup = d['supervisor']?.toString() ?? '';
      String ev = _normalizarEvento(d['evento']?.toString() ?? '');
      int rAno = int.tryParse(d['reinc_ano']?.toString() ?? '0') ?? 0;
      if(supData.containsKey(sup)) {
        supData[sup]![ev] = (supData[sup]![ev] ?? 0) + 1;
        supTotal[sup] = (supTotal[sup] ?? 0) + 1;
        if(rAno > supReincAno[sup]!) supReincAno[sup] = rAno;
      }
    }
    var supActivos = supTotal.keys.where((k) => supTotal[k]! > 0).toList();
    supActivos.sort((a,b) => supTotal[b]!.compareTo(supTotal[a]!));

    List<List<String>> filasSup = supActivos.map((sup) {
      return [
        sup,
        ...columnasEventos.map((ev) => supData[sup]![ev].toString()),
        supTotal[sup].toString(),
        supReincAno[sup].toString()
      ];
    }).toList();

    Widget tablaSupervisores = _buildTablaPro(
      titulo: 'Eventos por Supervisor',
      headers: ['SUPERVISOR', ...columnasEventos, 'TOTAL', 'REINC. AÑO'],
      minWidths: [260, ...anchosEventos, 90, 110],
      filas: filasSup,
      height: 480,
    );

    Map<String, Map<String, int>> opData = {};
    Map<String, int> opTotal = {};
    Map<String, int> opReincAno = {};
    for(var d in datos) {
      String op = d['nombre']?.toString().trim() ?? 'SIN NOMBRE';
      if (op.isEmpty) op = 'SIN NOMBRE';
      String ev = _normalizarEvento(d['evento']?.toString() ?? '');
      int rAno = int.tryParse(d['reinc_ano']?.toString() ?? '0') ?? 0;
      if(!opData.containsKey(op)) {
        opData[op] = { for (var e in columnasEventos) e : 0 };
        opTotal[op] = 0;
        opReincAno[op] = 0;
      }
      opData[op]![ev] = (opData[op]![ev] ?? 0) + 1;
      opTotal[op] = (opTotal[op] ?? 0) + 1;
      if (rAno > opReincAno[op]!) opReincAno[op] = rAno;
    }
    var opActivos = opTotal.keys.toList();
    opActivos.sort((a,b) => opTotal[b]!.compareTo(opTotal[a]!));

    List<List<String>> filasOp = opActivos.map((op) {
      return [
        op,
        ...columnasEventos.map((ev) => opData[op]![ev].toString()),
        opTotal[op].toString(),
        opReincAno[op].toString()
      ];
    }).toList();

    Widget tablaOperadores = _buildTablaPro(
      titulo: 'Eventos por Operador',
      headers: ['OPERADOR', ...columnasEventos, 'TOTAL', 'REINC. AÑO'],
      minWidths: [300, ...anchosEventos, 90, 110],
      filas: filasOp,
      height: 480,
    );

    return SizedBox(
      width: double.infinity,
      child: isWide
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: tablaTurno),
          const SizedBox(width: 24),
          Expanded(flex: 4, child: tablaSupervisores),
          const SizedBox(width: 24),
          Expanded(flex: 4, child: tablaOperadores)
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
    bool isWide = MediaQuery.of(context).size.width > 900;
    int total = datos.isEmpty ? 1 : datos.length;

    Map<String, int> conteoEventos = {};
    for(var d in datos) {
      String ev = _normalizarEvento(d['evento']?.toString() ?? 'SIN EVENTO');
      conteoEventos[ev] = (conteoEventos[ev] ?? 0) + 1;
    }
    var eventosList = conteoEventos.keys.toList()..sort((a,b) => conteoEventos[b]!.compareTo(conteoEventos[a]!));
    List<List<String>> filasEv = eventosList.map((e) => [e, conteoEventos[e].toString(), '${((conteoEventos[e]!/total)*100).toStringAsFixed(1)}%']).toList();

    Map<String, int> conteoAreas = {};
    for(var d in datos) {
      String ar = d['area']?.toString().trim() ?? 'SIN ÁREA';
      if(ar.isEmpty) ar = 'SIN ÁREA';
      conteoAreas[ar] = (conteoAreas[ar] ?? 0) + 1;
    }
    var areasList = conteoAreas.keys.toList()..sort((a,b) => conteoAreas[b]!.compareTo(conteoAreas[a]!));
    List<List<String>> filasAr = areasList.map((a) => [a, conteoAreas[a].toString(), '${((conteoAreas[a]!/total)*100).toStringAsFixed(1)}%']).toList();

    Map<String, int> conteoOrigen = {};
    for(var d in datos) {
      String or = d['origen_opm']?.toString().trim() ?? 'SIN ORIGEN';
      if(or.isEmpty) or = 'SIN ORIGEN';
      conteoOrigen[or] = (conteoOrigen[or] ?? 0) + 1;
    }
    var origenList = conteoOrigen.keys.toList()..sort((a,b) => conteoOrigen[b]!.compareTo(conteoOrigen[a]!));
    List<List<String>> filasOr = origenList.map((o) => [o, conteoOrigen[o].toString(), '${((conteoOrigen[o]!/total)*100).toStringAsFixed(1)}%']).toList();

    return SizedBox(
      width: double.infinity,
      child: isWide
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: _buildTablaPro(titulo: 'Tipos de Evento', headers: ['EVENTO', 'TOTAL', '% GRAL'], minWidths: [220, 100, 100], filas: filasEv, height: 420)),
          const SizedBox(width: 24),
          Expanded(flex: 1, child: _buildTablaPro(titulo: 'Áreas de Ocurrencia', headers: ['ÁREA', 'TOTAL', '% GRAL'], minWidths: [220, 100, 100], filas: filasAr, height: 420)),
          const SizedBox(width: 24),
          Expanded(flex: 1, child: _buildTablaPro(titulo: 'Origen del OPM', headers: ['ORIGEN OPM', 'TOTAL', '% GRAL'], minWidths: [200, 100, 100], filas: filasOr, height: 420))
        ],
      )
          : Column(
        children: [
          _buildTablaPro(titulo: 'Tipos de Evento', headers: ['EVENTO', 'TOTAL', '% GRAL'], minWidths: [220, 100, 100], filas: filasEv, height: 420),
          const SizedBox(height: 24),
          _buildTablaPro(titulo: 'Áreas de Ocurrencia', headers: ['ÁREA', 'TOTAL', '% GRAL'], minWidths: [220, 100, 100], filas: filasAr, height: 420),
          const SizedBox(height: 24),
          _buildTablaPro(titulo: 'Origen del OPM', headers: ['ORIGEN OPM', 'TOTAL', '% GRAL'], minWidths: [200, 100, 100], filas: filasOr, height: 420)
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 FILA 4: TABLA DE DETALLE COMPLETO (CENTRADAS SIN REINCIDENCIAS)
  // ---------------------------------------------------------------------------
  Widget _buildTablaDetalleCompleto(List<Map<String, dynamic>> datos) {
    List<String> columnas = ['FECHA', 'HORA', 'TURNO', 'MÁQUINA', 'ÁREA', 'OPERADOR', 'ORIGEN', 'ALERTA', 'SUPERVISOR'];
    List<double> anchos = [120, 100, 90, 110, 220, 300, 120, 160, 260];

    List<List<String>> filas = datos.map((item) {
      return [
        _formatearFechaLimpia(item['fecha']),
        item['hora']?.toString() ?? '',
        item['turno']?.toString() ?? '',
        item['maquina']?.toString() ?? '',
        item['area']?.toString() ?? '',
        item['nombre']?.toString() ?? '',
        item['origen_opm']?.toString() ?? '',
        item['evento']?.toString() ?? '',
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
              child: _buildTablaProHeaderWidget(headers: columnas, minWidths: anchos, filas: filas),
            ),
          ],
        ),
      ),
    );
  }

  // WIDGET CENTRADO PARA EL DETALLE COMPLETO
  Widget _buildTablaProHeaderWidget({
    required List<String> headers,
    required List<double> minWidths,
    required List<List<String>> filas,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
            builder: (context, constraints) {
              double totalWidth = minWidths.fold(0, (s, w) => s + w);
              List<double> finalWidths = List.from(minWidths);

              if (totalWidth < constraints.maxWidth) {
                double extra = (constraints.maxWidth - totalWidth) / headers.length;
                for (int i = 0; i < finalWidths.length; i++) {
                  finalWidths[i] += extra;
                }
                totalWidth = constraints.maxWidth;
              }

              Widget tableContent = Column(
                children: [
                  // ENCABEZADOS CENTRADOS
                  Container(
                    color: const Color(0xFF1E293B),
                    child: Row(
                      children: List.generate(headers.length, (i) {
                        return Container(
                          width: finalWidths[i],
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          alignment: Alignment.center,
                          child: Text(
                              headers[i],
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)
                          ),
                        );
                      }),
                    ),
                  ),
                  // CELDAS CENTRADAS
                  Expanded(
                    child: ListView.builder(
                      itemCount: filas.length,
                      itemBuilder: (context, index) {
                        final fila = filas[index];
                        return Container(
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                          child: Row(
                            children: List.generate(fila.length, (i) {
                              bool isTurnoCol = headers[i] == 'TURNO';

                              Widget cellContent = Text(
                                fila[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: (headers[i] == 'OPERADOR' || headers[i] == 'ALERTA') ? FontWeight.bold : FontWeight.w500,
                                  color: headers[i] == 'ALERTA' ? Colors.redAccent : Colors.black87,
                                ),
                              );

                              if (isTurnoCol && (fila[i] == 'T1' || fila[i] == 'T2' || fila[i] == 'T3')) {
                                Color badgeC = fila[i] == 'T1' ? const Color(0xFF2563EB) : (fila[i] == 'T2' ? const Color(0xFFD97706) : const Color(0xFF7C3AED));
                                cellContent = Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(color: badgeC, borderRadius: BorderRadius.circular(16)),
                                  child: Text(fila[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                );
                              }

                              return Container(
                                width: finalWidths[i],
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                alignment: Alignment.center,
                                child: cellContent,
                              );
                            }),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  child: tableContent,
                ),
              );
            }
        ),
      ),
    );
  }
}