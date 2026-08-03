import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'api_service.dart';

class ReporteHoraHoraScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const ReporteHoraHoraScreen({super.key, this.onToggleSidebar});

  @override
  State<ReporteHoraHoraScreen> createState() => _ReporteHoraHoraScreenState();
}

class _ReporteHoraHoraScreenState extends State<ReporteHoraHoraScreen> {
  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todosLosReportes = [];
  List<Map<String, dynamic>> _reportesFiltrados = [];

  // Filtros de Rango de Fecha
  DateTime _fechaDesde = DateTime(2026, 7, 26);
  DateTime _fechaHasta = DateTime(2026, 7, 27);

  // Filtro de Turno
  String _turnoSel = 'Todos';
  final List<String> _listaTurnos = ['Todos', 'T1', 'T2', 'T3'];

  String _supervisorSel = 'Todos';
  List<String> _listaSupervisores = ['Todos'];

  List<String> _columnasZonas = [];

  final GlobalKey _capturaKey = GlobalKey();
  final ScrollController _horizontalScrollController = ScrollController();

  // Lista maestra de 24 horas
  final List<String> _franjasHorariasMaestras = [
    '06:00 - 07:00', '07:00 - 08:00', '08:00 - 09:00', '09:00 - 10:00',
    '10:00 - 11:00', '11:00 - 12:00', '12:00 - 13:00', '13:00 - 14:00',
    '14:00 - 15:00', '15:00 - 16:00', '16:00 - 17:00', '17:00 - 18:00',
    '18:00 - 19:00', '19:00 - 20:00', '20:00 - 21:00', '21:00 - 22:00',
    '22:00 - 23:00', '23:00 - 00:00', '00:00 - 01:00', '01:00 - 02:00',
    '02:00 - 03:00', '03:00 - 04:00', '04:00 - 05:00', '05:00 - 06:00',
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  // 🍺 CONVERSIÓN SEGURA DE HECTOLITROS (HL_TOTAL)
  double _parseHl(dynamic val) {
    if (val == null) return 0.0;
    String str = val.toString().trim().replaceAll(',', '.');
    if (str.toUpperCase() == 'NULL' || str == '[NULL]' || str.isEmpty) return 0.0;
    return double.tryParse(str) ?? 0.0;
  }

  List<String> _obtenerFranjasHorariasVisibles() {
    if (_turnoSel == 'T2') {
      return [
        '06:00 - 07:00', '07:00 - 08:00', '08:00 - 09:00', '09:00 - 10:00',
        '10:00 - 11:00', '11:00 - 12:00', '12:00 - 13:00', '13:00 - 14:00',
      ];
    } else if (_turnoSel == 'T3') {
      return [
        '14:00 - 15:00', '15:00 - 16:00', '16:00 - 17:00', '17:00 - 18:00',
        '18:00 - 19:00', '19:00 - 20:00', '20:00 - 21:00', '21:00 - 22:00',
      ];
    } else if (_turnoSel == 'T1') {
      return [
        '22:00 - 23:00', '23:00 - 00:00', '00:00 - 01:00', '01:00 - 02:00',
        '02:00 - 03:00', '03:00 - 04:00', '04:00 - 05:00', '05:00 - 06:00',
      ];
    }
    return _franjasHorariasMaestras;
  }

  Future<void> _cargarDatosBD() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final List<dynamic> datosRaw = await ApiService.consultar('roturas', 'reportes_rotura');

      final List<Map<String, dynamic>> datosProcesados = [];
      final Set<String> supervisores = {'Todos'};
      final Set<String> zonasEncontradas = {};
      List<DateTime> fechasEncontradas = [];

      for (var fila in datosRaw) {
        if (fila is Map) {
          final Map<String, dynamic> mapa = {};
          fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
          datosProcesados.add(mapa);

          String? sup = mapa['supervisor']?.toString();
          String? zona = mapa['zona']?.toString() ?? mapa['area']?.toString();
          String? rawFecha = mapa['fecha_evento']?.toString() ?? mapa['timestamp_registro']?.toString();

          if (sup != null && sup.trim().isNotEmpty && sup.toLowerCase() != 'null') {
            supervisores.add(sup.trim());
          }
          if (zona != null && zona.trim().isNotEmpty && zona.toLowerCase() != 'null') {
            zonasEncontradas.add(zona.trim());
          }
          if (rawFecha != null && rawFecha.isNotEmpty) {
            String soloF = rawFecha.split('T')[0].split(' ')[0];
            DateTime? dt = DateTime.tryParse(soloF);
            if (dt != null) fechasEncontradas.add(dt);
          }
        }
      }

      _todosLosReportes = datosProcesados;
      _listaSupervisores = supervisores.toList()..sort();

      List<String> zonasLista = zonasEncontradas.toList()..sort();
      if (zonasLista.isEmpty) {
        zonasLista = ['Bodega Central', 'Zona A', 'Carpa 2', 'Carpa 3', 'Carpa 4', 'Carpa 5', 'Carpa 7', 'REEMPAQUE'];
      }
      _columnasZonas = zonasLista;

      if (fechasEncontradas.isNotEmpty) {
        fechasEncontradas.sort();
        _fechaDesde = fechasEncontradas.first;
        _fechaHasta = fechasEncontradas.last;
      }

      _aplicarFiltros();
    } catch (e) {
      _mensajeError = 'Error al cargar desde el servidor: $e';
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  String _obtenerTurnoPorHora(int hora) {
    if (hora >= 6 && hora < 14) return 'T2';
    if (hora >= 14 && hora < 22) return 'T3';
    return 'T1';
  }

  void _aplicarFiltros() {
    _reportesFiltrados = _todosLosReportes.where((row) {
      DateTime? fechaFila;
      String? rawFecha = row['fecha_evento']?.toString() ?? row['timestamp_registro']?.toString();
      if (rawFecha != null && rawFecha.isNotEmpty) {
        String soloFecha = rawFecha.split('T')[0].split(' ')[0];
        fechaFila = DateTime.tryParse(soloFecha);
      }

      if (fechaFila != null) {
        final fSin = DateTime(fechaFila.year, fechaFila.month, fechaFila.day);
        final dSin = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
        final hSin = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day);

        if (fSin.isBefore(dSin) || fSin.isAfter(hSin)) return false;
      }

      int horaInt = _extraerHoraEntera(
        row['franja']?.toString(),
        row['fecha_evento']?.toString() ?? row['timestamp_registro']?.toString(),
      );

      if (_turnoSel != 'Todos') {
        String turnoCalculado = _obtenerTurnoPorHora(horaInt);
        if (turnoCalculado != _turnoSel) return false;
      }

      if (_supervisorSel != 'Todos' && row['supervisor']?.toString() != _supervisorSel) return false;

      return true;
    }).toList();
  }

  int _extraerHoraEntera(String? franjaRaw, String? timestamp) {
    if (franjaRaw != null && franjaRaw.trim().isNotEmpty && franjaRaw.toLowerCase() != 'null') {
      String f = franjaRaw.trim();
      if (f.contains(':')) {
        return int.tryParse(f.split(':')[0]) ?? 0;
      } else {
        return int.tryParse(f) ?? 0;
      }
    }

    if (timestamp != null && timestamp.isNotEmpty) {
      String horaPart = '';
      if (timestamp.contains('T')) {
        horaPart = timestamp.split('T')[1];
      } else if (timestamp.contains(' ')) {
        horaPart = timestamp.split(' ')[1];
      }
      if (horaPart.contains(':')) {
        return int.tryParse(horaPart.split(':')[0]) ?? 0;
      }
    }

    return 6;
  }

  String _mapearHoraAFranjaLabel(int hora) {
    int hSiguiente = (hora + 1) % 24;
    String h1 = hora.toString().padLeft(2, '0');
    String h2 = hSiguiente.toString().padLeft(2, '0');
    return '$h1:00 - $h2:00';
  }

  String _obtenerZonaRegistro(Map<String, dynamic> registro) {
    String? z = registro['zona']?.toString() ?? registro['area']?.toString();
    if (z != null && z.trim().isNotEmpty && z.toLowerCase() != 'null') {
      return z.trim();
    }
    return _columnasZonas.isNotEmpty ? _columnasZonas.first : 'Bodega Central';
  }

  Future<void> _tomarCapturaFoto() async {
    try {
      RenderRepaintBoundary boundary =
      _capturaKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final blob = html.Blob([pngBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", "Reporte_Hora_a_Hora_${_fechaDesde.day}_al_${_fechaHasta.day}.png")
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint("Error al exportar captura: $e");
    }
  }

  void _activarModoTV() {
    if (widget.onToggleSidebar != null) {
      widget.onToggleSidebar!();
    }
    if (html.document.fullscreenElement == null) {
      html.document.documentElement?.requestFullscreen();
    } else {
      html.document.exitFullscreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE65100)),
      );
    }

    List<String> franjasVisibles = _obtenerFranjasHorariasVisibles();

    // Matriz de Unidades y Matriz de HL
    Map<String, Map<String, double>> matriz = {
      for (var f in franjasVisibles) f: {for (var z in _columnasZonas) z: 0.0}
    };
    Map<String, Map<String, double>> matrizHl = {
      for (var f in franjasVisibles) f: {for (var z in _columnasZonas) z: 0.0}
    };

    for (var r in _reportesFiltrados) {
      int horaInt = _extraerHoraEntera(
        r['franja']?.toString(),
        r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString(),
      );

      String franjaKey = _mapearHoraAFranjaLabel(horaInt);
      String zonaKey = _obtenerZonaRegistro(r);
      double cantidad = double.tryParse(r['cantidad']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      if (matriz.containsKey(franjaKey) && matriz[franjaKey]!.containsKey(zonaKey)) {
        matriz[franjaKey]![zonaKey] = (matriz[franjaKey]![zonaKey] ?? 0) + cantidad;
        matrizHl[franjaKey]![zonaKey] = (matrizHl[franjaKey]![zonaKey] ?? 0) + hlVal;
      }
    }

    Map<String, double> totalesPorZona = {for (var z in _columnasZonas) z: 0.0};
    double granTotalRoturas = 0;
    double granTotalHl = 0;

    matriz.forEach((franja, zonas) {
      zonas.forEach((zona, cant) {
        totalesPorZona[zona] = (totalesPorZona[zona] ?? 0) + cant;
        granTotalRoturas += cant;
      });
    });

    matrizHl.forEach((franja, zonas) {
      zonas.forEach((zona, hlVal) {
        granTotalHl += hlVal;
      });
    });

    Map<int, TableColumnWidth> columnWidths = {
      0: const FixedColumnWidth(125),
    };
    for (int i = 0; i < _columnasZonas.length; i++) {
      columnWidths[i + 1] = const FixedColumnWidth(98);
    }
    columnWidths[_columnasZonas.length + 1] = const FixedColumnWidth(100);
    columnWidths[_columnasZonas.length + 2] = const FixedColumnWidth(100);

    return Container(
      color: const Color(0xFFF4F6FB),
      width: double.infinity,
      height: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: RepaintBoundary(
          key: _capturaKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_mensajeError != null) _buildBannerError(),

              _buildBarraFiltros(),
              const SizedBox(height: 16),

              // 🍺 TARJETAS KPI (INCLUYE HL TOTAL)
              Row(
                children: [
                  _buildKPICard('TOTAL ROTURAS', '${granTotalRoturas.toInt()} und', Icons.warning_rounded, const Color(0xFFF36F21)),
                  const SizedBox(width: 12),
                  _buildKPICard('TOTAL HL', granTotalHl.toStringAsFixed(2), Icons.opacity_rounded, const Color(0xFF00796B)),
                  const SizedBox(width: 12),
                  _buildKPICard('CANTIDAD EVENTOS', '${_reportesFiltrados.length}', Icons.event_note_rounded, const Color(0xFF455A64)),
                ],
              ),
              const SizedBox(height: 20),

              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1450),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeaderExcelVerde(),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        color: Colors.white,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.table_rows_rounded, size: 18, color: Colors.red.shade800),
                            const SizedBox(width: 8),
                            Text(
                              'MONITOREO HORA A HORA DE ROTURA POR ZONA Y HL',
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Table(
                            border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1.0),
                            columnWidths: columnWidths,
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                                children: [
                                  _cellHeader('HORA A HORA\nROTURA', isDark: true),
                                  ..._columnasZonas.map((z) => _cellHeader(z, isDark: true)),
                                  _cellHeader('TOTAL\nx HR', isDark: true, isTotalCol: true),
                                  _cellHeader('HL x HR', isDark: true, isHlCol: true),
                                ],
                              ),

                              ...franjasVisibles.map((franja) {
                                double totalFila = 0;
                                double totalHlFila = 0;

                                matriz[franja]!.values.forEach((v) => totalFila += v);
                                matrizHl[franja]!.values.forEach((v) => totalHlFila += v);

                                bool estaVacio = totalFila == 0;

                                return TableRow(
                                  decoration: BoxDecoration(
                                    color: estaVacio ? Colors.white : const Color(0xFFFFF5F5),
                                  ),
                                  children: [
                                    _cellText(franja, isBold: true),
                                    ..._columnasZonas.map((z) => _cellNumber(matriz[franja]![z]!)),
                                    _cellNumber(totalFila, isTotalFila: true),
                                    _cellNumberHl(totalHlFila),
                                  ],
                                );
                              }),

                              TableRow(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                children: [
                                  _cellText('TOTAL TURNO', isBold: true, isTotalRow: true),
                                  ..._columnasZonas.map((z) => _cellNumber(totalesPorZona[z]!, isTotalRow: true)),
                                  _cellNumber(granTotalRoturas, isTotalRow: true, isGrandTotal: true),
                                  _cellNumberHl(granTotalHl, isTotalRow: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKPICard(String titulo, String valor, IconData icono, Color colorBorde) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: colorBorde, width: 4)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorBorde.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icono, color: colorBorde, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      valor,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderExcelVerde() {
    String fDesdeStr = '${_fechaDesde.day.toString().padLeft(2, '0')}/${_fechaDesde.month.toString().padLeft(2, '0')}/${_fechaDesde.year}';
    String fHastaStr = '${_fechaHasta.day.toString().padLeft(2, '0')}/${_fechaHasta.month.toString().padLeft(2, '0')}/${_fechaHasta.year}';

    String detalleTurno = _turnoSel == 'T2'
        ? 'T2 (06:00 - 14:00)'
        : _turnoSel == 'T3'
        ? 'T3 (14:00 - 22:00)'
        : _turnoSel == 'T1'
        ? 'T1 (22:00 - 06:00)'
        : 'TODOS LOS TURNOS';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              const Text('PERÍODO: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.white70)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(6)),
                child: Text('$fDesdeStr AL $fHastaStr', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              const Text('TURNO: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.white70)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                child: Text(detalleTurno, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellHeader(String text, {bool isDark = false, bool isTotalCol = false, bool isHlCol = false}) {
    Color? bg;
    if (isTotalCol) bg = const Color(0xFFB91C1C);
    if (isHlCol) bg = const Color(0xFF005A4E);

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _cellText(String text, {bool isBold = false, bool isTotalRow = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        textAlign: isTotalRow ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isTotalRow ? Colors.white : const Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _cellNumberHl(double hlVal, {bool isTotalRow = false}) {
    if (hlVal == 0 && !isTotalRow) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('-', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      );
    }

    if (isTotalRow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          hlVal.toStringAsFixed(2),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Color(0xFF80CBC4),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF80CBC4)),
        ),
        child: Text(
          hlVal.toStringAsFixed(2),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00695C),
          ),
        ),
      ),
    );
  }

  Widget _cellNumber(double valor, {bool isTotalRow = false, bool isTotalFila = false, bool isGrandTotal = false}) {
    if (valor == 0 && !isTotalRow && !isTotalFila) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('-', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      );
    }

    int cantInt = valor.toInt();

    if (isTotalRow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(
          '$cantInt',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isGrandTotal ? 12 : 11,
            fontWeight: FontWeight.w900,
            color: isGrandTotal ? const Color(0xFFFEF08A) : Colors.white,
          ),
        ),
      );
    }

    if (isTotalFila) {
      if (cantInt == 0) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('-', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        );
      }
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Text(
            '$cantInt',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Color(0xFF991B1B),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(
          '$cantInt',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildSelectorFecha('DESDE', _fechaDesde, (d) => setState(() {
            _fechaDesde = d;
            _aplicarFiltros();
          })),
          _buildSelectorFecha('HASTA', _fechaHasta, (d) => setState(() {
            _fechaHasta = d;
            _aplicarFiltros();
          })),
          _buildDropdown('TURNO', _turnoSel, _listaTurnos, (v) => setState(() {
            _turnoSel = v!;
            _aplicarFiltros();
          })),
          _buildDropdown('SUPERVISOR', _supervisorSel, _listaSupervisores, (v) => setState(() {
            _supervisorSel = v!;
            _aplicarFiltros();
          })),

          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => setState(() => _aplicarFiltros()),
            icon: const Icon(Icons.filter_alt_rounded, size: 14),
            label: const Text('FILTRAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF36F21),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _tomarCapturaFoto,
            icon: const Icon(Icons.camera_alt_rounded, size: 14),
            label: const Text('CAPTURAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF475569),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _activarModoTV,
            icon: const Icon(Icons.tv_rounded, size: 14),
            label: const Text('MODO TV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorFecha(String label, DateTime fecha, Function(DateTime) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 3),
        InkWell(
          onTap: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: fecha,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (p != null) onSelect(p);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min, // 👈 CORREGIDO AQUÍ
              children: [
                Text(
                  '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildDropdown(String label, String valor, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(valor) ? valor : items.first,
              isDense: true,
              style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w600),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: onChanged,
            ),
          ),
        )
      ],
    );
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade600),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _mensajeError!,
              style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          InkWell(
            onTap: _cargarDatosBD,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.amber.shade900, borderRadius: BorderRadius.circular(4)),
              child: const Text('REINTENTAR', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}