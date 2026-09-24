import 'dart:convert';
import 'dart:math';
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

class DashboardRoturasScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const DashboardRoturasScreen({super.key, this.onToggleSidebar});

  @override
  State<DashboardRoturasScreen> createState() => _DashboardRoturasScreenState();
}

class _DashboardRoturasScreenState extends State<DashboardRoturasScreen> {
  static const String _apiUrl = 'https://plantatocancipa.site/api/v1/db_logistica/consultar/roturas/reportes_rotura';
  static const String _apiKey = 'PlantaLogistica2026*';

  bool _cargando = true;
  String? _mensajeError;

  List<Map<String, dynamic>> _todosLosReportes = [];
  List<Map<String, dynamic>> _reportesFiltrados = [];
  List<Map<String, dynamic>> _reportesAnual = [];

  DateTime _fechaDesde = DateTime(2026, 7, 1);
  DateTime _fechaHasta = DateTime.now();

  // Filtros
  List<String> _listaTurnos = [];
  List<String> _listaSupervisores = [];
  List<String> _listaAreas = [];
  List<String> _listaAtribuibles = ['Comportamiento', 'Condición'];
  List<String> _listaTipos = [];
  List<String> _listaOpms = [];
  List<String> _listaCausales = [];
  List<String> _listaEscenarios = [];
  List<String> _listaZonas = [];
  List<String> _listaWqi = [];

  List<String> _turnosSel = [];
  List<String> _supervisoresSel = [];
  List<String> _areasSel = [];
  List<String> _atribuiblesSel = [];
  List<String> _tiposSel = [];
  List<String> _opmsSel = [];
  List<String> _causalesSel = [];
  List<String> _escenariosSel = [];
  List<String> _zonasSel = [];
  List<String> _wqiSel = [];

  final GlobalKey _capturaKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  double _parseHl(dynamic val) {
    if (val == null) return 0.0;
    String str = val.toString().trim().replaceAll(',', '.');
    if (str.toUpperCase() == 'NULL' || str == '[NULL]' || str.isEmpty) return 0.0;
    return double.tryParse(str) ?? 0.0;
  }

  Future<void> _cargarDatosBD() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final urlSinCache = '$_apiUrl?_t=${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.get(
        Uri.parse(urlSinCache),
        headers: {'Content-Type': 'application/json', 'x-api-key': _apiKey},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> datosRaw = body['data'] ?? [];

        final List<Map<String, dynamic>> datosProcesados = [];
        final Set<String> turnos = {}, supervisores = {}, areas = {}, tipos = {}, opms = {}, causales = {}, escenarios = {}, zonas = {}, wqis = {};

        for (var fila in datosRaw) {
          if (fila is Map) {
            final Map<String, dynamic> mapa = {};
            fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);

            // ----------------------------------------------------------------------------------
            // LECTURA SEPARADA PARA EVITAR CONFLICTOS DE LÓGICA
            // ----------------------------------------------------------------------------------
            // 1. Extraemos tipo_material_2 para los Filtros visuales, Donas y Tablas (PET, Lata...)
            String t2Raw = (mapa['tipo_material_2']?.toString() ?? '').trim().toUpperCase();
            String tipo2 = (t2Raw == 'NULL' || t2Raw == '[NULL]' || t2Raw.isEmpty) ? 'SIN DEFINIR' : t2Raw;
            mapa['tipo_material_limpio'] = tipo2;

            // 2. Extraemos tipo_material solo para la regla oculta del WQI (PT, ERR...)
            String t1Raw = (mapa['tipo_material']?.toString() ?? '').trim().toUpperCase();
            String tipo1 = (t1Raw == 'NULL' || t1Raw == '[NULL]' || t1Raw.isEmpty) ? 'SIN DEFINIR' : t1Raw;
            mapa['tipo_material_pt'] = tipo1;
            // ----------------------------------------------------------------------------------

            String? t = mapa['turno']?.toString();
            String? sup = mapa['supervisor']?.toString();
            String? area = mapa['area']?.toString();
            String? opm = mapa['personal']?.toString() ?? mapa['reportante']?.toString();
            String? causal = mapa['causal']?.toString();
            String? escenario = mapa['escenario']?.toString();
            String? zona = mapa['zona']?.toString();

            String wRaw = (mapa['wqi']?.toString() ?? '').trim().toUpperCase();
            String wqi = (wRaw == 'NULL' || wRaw == '[NULL]' || wRaw.isEmpty) ? 'NO ASIGNADO' : wRaw;
            mapa['wqi_limpio'] = wqi;

            datosProcesados.add(mapa);

            if (t != null && t.trim().isNotEmpty) turnos.add(t.trim());
            if (sup != null && sup.trim().isNotEmpty) supervisores.add(sup.trim());
            if (area != null && area.trim().isNotEmpty) areas.add(area.trim());
            if (tipo2 != 'SIN DEFINIR') tipos.add(tipo2); // Llena el dropdown con "PET", "LATA", etc.
            if (opm != null && opm.trim().isNotEmpty && opm.toUpperCase() != 'NULL') opms.add(opm.trim());
            if (causal != null && causal.trim().isNotEmpty && causal.toUpperCase() != 'NULL') causales.add(causal.trim());
            if (escenario != null && escenario.trim().isNotEmpty && escenario.toUpperCase() != 'NULL') escenarios.add(escenario.trim());
            if (zona != null && zona.trim().isNotEmpty && zona.toUpperCase() != 'NULL') zonas.add(zona.trim());
            if (wqi != 'NO ASIGNADO') wqis.add(wqi);
          }
        }

        setState(() {
          _todosLosReportes = datosProcesados;
          _listaTurnos = turnos.toList()..sort();
          _listaSupervisores = supervisores.toList()..sort();
          _listaAreas = areas.toList()..sort();
          _listaTipos = tipos.toList()..sort();
          _listaOpms = opms.toList()..sort();
          _listaCausales = causales.toList()..sort();
          _listaEscenarios = escenarios.toList()..sort();
          _listaZonas = zonas.toList()..sort();
          _listaWqi = wqis.toList()..sort();

          _turnosSel = List.from(_listaTurnos);
          _supervisoresSel = List.from(_listaSupervisores);
          _areasSel = List.from(_listaAreas);
          _atribuiblesSel = List.from(_listaAtribuibles);
          _tiposSel = List.from(_listaTipos);
          _opmsSel = List.from(_listaOpms);
          _causalesSel = List.from(_listaCausales);
          _escenariosSel = List.from(_listaEscenarios);
          _zonasSel = List.from(_listaZonas);
          _wqiSel = List.from(_listaWqi);

          if (_todosLosReportes.isNotEmpty) {
            List<DateTime> fechas = [];
            for (var r in _todosLosReportes) {
              String? rawF = r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString();
              if (rawF != null && rawF.isNotEmpty) {
                String soloF = rawF.split('T')[0].split(' ')[0];
                DateTime? dt = DateTime.tryParse(soloF);
                if (dt != null) fechas.add(dt);
              }
            }
            if (fechas.isNotEmpty) {
              fechas.sort();
              _fechaDesde = fechas.first;
              _fechaHasta = fechas.last;
            }
          }
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
      debugPrint('Error de conexión en Dashboard: $e');
      setState(() {
        _mensajeError = 'Error de conexión: $e\n(Si estás en Web, revisa CORS o tu API)';
        _cargando = false;
      });
    }
  }

  bool _cumpleFiltrosSinFecha(Map<String, dynamic> row) {
    String turnoRow = (row['turno']?.toString() ?? '').trim();
    String supRow = (row['supervisor']?.toString() ?? '').trim();
    String areaRow = (row['area']?.toString() ?? '').trim();
    String tipoRow = row['tipo_material_limpio'] ?? 'SIN DEFINIR'; // Usado para el Dropdown (PET, Lata...)
    String tipoPTRow = row['tipo_material_pt'] ?? 'SIN DEFINIR'; // Usado para la Regla WQI (PT, ERR...)
    String opmRow = (row['personal']?.toString() ?? row['reportante']?.toString() ?? '').trim();
    String causalRow = (row['causal']?.toString() ?? '').trim();
    String escRow = (row['escenario']?.toString() ?? '').trim();
    String zonaRow = (row['zona']?.toString() ?? '').trim();
    String wqiRow = row['wqi_limpio'] ?? 'NO ASIGNADO';

    // 1. REGLA INTELIGENTE WQI: Revisa la columna tipo_material buscando "PT"
    if (_wqiSel.length == 1 && (_wqiSel.first.toUpperCase() == 'SI' || _wqiSel.first.toUpperCase() == 'SÍ')) {
      if (tipoPTRow != 'PT') {
        return false;
      }
    }

    // 2. Comprobación estándar de Dropdowns (El de Tipo Material ahora filtra por PET, LATA...)
    if (_turnosSel.isEmpty || (_turnosSel.length != _listaTurnos.length && !_turnosSel.contains(turnoRow))) return false;
    if (_supervisoresSel.isEmpty || (_supervisoresSel.length != _listaSupervisores.length && !_supervisoresSel.contains(supRow))) return false;
    if (_areasSel.isEmpty || (_areasSel.length != _listaAreas.length && !_areasSel.contains(areaRow))) return false;
    if (_tiposSel.isEmpty || (_tiposSel.length != _listaTipos.length && !_tiposSel.contains(tipoRow))) return false;
    if (_opmsSel.isEmpty || (_opmsSel.length != _listaOpms.length && !_opmsSel.contains(opmRow))) return false;
    if (_causalesSel.isEmpty || (_causalesSel.length != _listaCausales.length && !_causalesSel.contains(causalRow))) return false;
    if (_escenariosSel.isEmpty || (_escenariosSel.length != _listaEscenarios.length && !_escenariosSel.contains(escRow))) return false;
    if (_zonasSel.isEmpty || (_zonasSel.length != _listaZonas.length && !_zonasSel.contains(zonaRow))) return false;
    if (_wqiSel.isEmpty || (_wqiSel.length != _listaWqi.length && !_wqiSel.contains(wqiRow))) return false;

    if (_atribuiblesSel.isEmpty) return false;
    if (_atribuiblesSel.length != _listaAtribuibles.length) {
      String at = (row['atribuible']?.toString() ?? '').toUpperCase();
      bool esCondicion = at.contains('NO') || at.contains('CONDICI');
      bool esComportamiento = (at.contains('ATRIBUIBLE') && !at.contains('NO')) || at.contains('COMPORTAMIENTO');
      bool pasaFiltro = false;
      if (_atribuiblesSel.contains('Condición') && esCondicion) pasaFiltro = true;
      if (_atribuiblesSel.contains('Comportamiento') && esComportamiento) pasaFiltro = true;
      if (!pasaFiltro) return false;
    }

    return true;
  }

  void _aplicarFiltros() {
    setState(() {
      _reportesFiltrados = [];
      _reportesAnual = [];

      for (var row in _todosLosReportes) {
        if (!_cumpleFiltrosSinFecha(row)) continue;

        DateTime? fechaFila;
        String? rawFecha = row['fecha_evento']?.toString() ?? row['timestamp_registro']?.toString();
        if (rawFecha != null && rawFecha.isNotEmpty) {
          String soloFecha = rawFecha.split('T')[0].split(' ')[0];
          fechaFila = DateTime.tryParse(soloFecha);
        }

        if (fechaFila != null) {
          if (fechaFila.year == _fechaHasta.year) {
            _reportesAnual.add(row);
          }

          final fSin = DateTime(fechaFila.year, fechaFila.month, fechaFila.day);
          final dSin = DateTime(_fechaDesde.year, _fechaDesde.month, _fechaDesde.day);
          final hSin = DateTime(_fechaHasta.year, _fechaHasta.month, _fechaHasta.day);
          if (!fSin.isBefore(dSin) && !fSin.isAfter(hSin)) {
            _reportesFiltrados.add(row);
          }
        }
      }
    });
  }

  Future<void> _tomarCapturaFoto() async {
    try {
      RenderRepaintBoundary boundary = _capturaKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 0.6);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final blob = html.Blob([pngBytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", "Reporte_Dashboard_Roturas.png")
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint("Error al tomar la foto: $e");
    }
  }

  void _activarModoTV() {
    if (widget.onToggleSidebar != null) widget.onToggleSidebar!();
    if (html.document.fullscreenElement == null) {
      html.document.documentElement?.requestFullscreen();
    } else {
      html.document.exitFullscreen();
    }
  }

  void _descargarExcel() {
    if (_reportesFiltrados.isEmpty) return;
    StringBuffer sb = StringBuffer();
    sb.write('\uFEFF');
    sb.writeln("FECHA;SUPERVISOR;PERSONAL INVOLUCRADO;ZONA;UBICACION;SKU;CANTIDAD;HL TOTAL;CAUSAL;WQI;OBSERVACION;CONCILIADOR;PRECIO BAJA TOTAL;PRECIO BAJA FULL PRICE");

    for (var r in _reportesFiltrados) {
      String fecha = (r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString() ?? '').split('T')[0];
      String supervisor = (r['supervisor']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String personal = (r['personal']?.toString() ?? r['reportante']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String zona = (r['zona']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String ubicacion = (r['ubicacion']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String sku = (r['sku']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String cantidad = r['cantidad']?.toString() ?? '0';
      double hlTotal = _parseHl(r['hl_total'] ?? r['hl']);
      String causal = (r['causal']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String wqi = (r['wqi_limpio']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');
      String obs = (r['descripcion']?.toString() ?? r['observacion']?.toString() ?? 'Sin observación').replaceAll(';', ',').replaceAll('\n', ' ');
      String conciliador = (r['conciliador']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');

      double costoBaja = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double costoFull = double.tryParse(r['costo_total_full_price']?.toString() ?? '0') ?? 0;

      sb.writeln("$fecha;$supervisor;$personal;$zona;$ubicacion;$sku;$cantidad;${hlTotal.toStringAsFixed(3)};$causal;$wqi;$obs;$conciliador;${costoBaja.toStringAsFixed(0)};${costoFull.toStringAsFixed(0)}");
    }

    final bytes = utf8.encode(sb.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", "Reporte_Roturas_Tocancipa.csv")
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  // ===========================================================================
  // 🔨 CONSTRUCCIÓN DEL LAYOUT
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFF36F21))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: RepaintBoundary(
          key: _capturaKey,
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_mensajeError != null) _buildBannerError(),

                _buildBarraFiltros(),
                const SizedBox(height: 18),

                _buildTarjetasKPI(),
                const SizedBox(height: 18),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildCardBase(
                        titulo: 'Evolución Diaria de Roturas - Rango Seleccionado',
                        child: SizedBox(
                          height: 240,
                          child: EvolucionDiariaChart(
                            reportes: _reportesFiltrados,
                            fechaDesde: _fechaDesde,
                            fechaHasta: _fechaHasta,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildCardBase(
                        titulo: 'Evolución Mensual de Roturas - Año ${_fechaHasta.year}',
                        child: SizedBox(
                          height: 240,
                          child: EvolucionMensualChart(
                            reportes: _reportesAnual,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildDonaTipo()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildDonaAtribuible()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildDonaTopCausales()),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaZona()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildTablaTipoMaterial()),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaUbicacion()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildTablaOpmDinero()),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaTopSkus()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildTablaEscenario()),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaSupervisor()),
                    const SizedBox(width: 14),
                    Expanded(child: _buildTablaTurno()),
                  ],
                ),
                const SizedBox(height: 18),

                _buildTablaDetalleCompleto(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildSelectorFecha('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d)),
          _buildSelectorFecha('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d)),
          _buildMultiSelect('TURNO', _listaTurnos, _turnosSel, (sel) => setState(() => _turnosSel = sel)),
          _buildMultiSelect('SUPERVISOR', _listaSupervisores, _supervisoresSel, (sel) => setState(() => _supervisoresSel = sel)),
          _buildMultiSelect('ÁREA', _listaAreas, _areasSel, (sel) => setState(() => _areasSel = sel)),
          _buildMultiSelect('CLASIFICACIÓN', _listaAtribuibles, _atribuiblesSel, (sel) => setState(() => _atribuiblesSel = sel)),
          _buildMultiSelect('TIPO MAT.', _listaTipos, _tiposSel, (sel) => setState(() => _tiposSel = sel)),
          _buildMultiSelect('OPM', _listaOpms, _opmsSel, (sel) => setState(() => _opmsSel = sel)),
          _buildMultiSelect('CAUSAL', _listaCausales, _causalesSel, (sel) => setState(() => _causalesSel = sel)),
          _buildMultiSelect('WQI', _listaWqi, _wqiSel, (sel) => setState(() => _wqiSel = sel)),
          _buildMultiSelect('ESCENARIO', _listaEscenarios, _escenariosSel, (sel) => setState(() => _escenariosSel = sel)),
          _buildMultiSelect('ZONA', _listaZonas, _zonasSel, (sel) => setState(() => _zonasSel = sel)),

          ElevatedButton.icon(
            onPressed: _aplicarFiltros,
            icon: const Icon(Icons.filter_alt_rounded, size: 14),
            label: const Text('FILTRAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF36F21),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _tomarCapturaFoto,
            icon: const Icon(Icons.camera_alt, size: 14),
            label: const Text('FOTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF64748B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _activarModoTV,
            icon: const Icon(Icons.tv_rounded, size: 14),
            label: const Text('TV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: fecha, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) onSelect(p);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                const SizedBox(width: 6),
                const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildMultiSelect(String label, List<String> opciones, List<String> seleccionados, Function(List<String>) onChanged) {
    String textLabel = seleccionados.length == opciones.length ? 'Todos' : seleccionados.isEmpty ? 'Ninguno' : '${seleccionados.length} selecc.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            List<String> tempSel = List.from(seleccionados);
            await showDialog(
                context: context,
                builder: (ctx) {
                  return StatefulBuilder(
                      builder: (context, setStateSB) {
                        bool todosSeleccionados = tempSel.length == opciones.length;
                        return AlertDialog(
                          title: Text('Filtrar $label', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          contentPadding: const EdgeInsets.only(top: 10),
                          content: SizedBox(
                            width: 300, height: 400,
                            child: Column(
                              children: [
                                CheckboxListTile(
                                    title: const Text('Seleccionar Todos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    value: todosSeleccionados,
                                    activeColor: const Color(0xFFF36F21),
                                    onChanged: (v) => setStateSB(() => v == true ? tempSel = List.from(opciones) : tempSel.clear())
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: opciones.length,
                                    itemBuilder: (context, index) {
                                      String op = opciones[index];
                                      return CheckboxListTile(
                                        dense: true,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        activeColor: const Color(0xFFF36F21),
                                        title: Text(op, style: const TextStyle(fontSize: 11)),
                                        value: tempSel.contains(op),
                                        onChanged: (v) => setStateSB(() => v == true ? tempSel.add(op) : tempSel.remove(op)),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF36F21), foregroundColor: Colors.white),
                                onPressed: () { Navigator.pop(ctx); onChanged(tempSel); },
                                child: const Text('Aplicar')
                            )
                          ],
                        );
                      }
                  );
                }
            );
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 100),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(textLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetasKPI() {
    int totalEventos = _reportesFiltrados.length;
    double totalUnidades = 0, totalHl = 0, costoTotalBaja = 0, costoTotalFullPrice = 0;

    for (var r in _reportesFiltrados) {
      totalUnidades += double.tryParse(r['cantidad']?.toString() ?? '0') ?? 0;
      totalHl += _parseHl(r['hl_total'] ?? r['hl']);
      costoTotalBaja += double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      costoTotalFullPrice += double.tryParse(r['costo_total_full_price']?.toString() ?? '0') ?? 0;
    }

    return Row(
      children: [
        Expanded(child: _buildKPICard('TOTAL EVENTOS', '$totalEventos', const Color(0xFFF36F21))),
        const SizedBox(width: 14),
        Expanded(child: _buildKPICard('TOTAL UNIDADES ROTAS', '${totalUnidades.toInt()}', const Color(0xFFF36F21))),
        const SizedBox(width: 14),
        Expanded(child: _buildKPICard('HL TOTAL', totalHl.toStringAsFixed(2), const Color(0xFF00B4D8))),
        const SizedBox(width: 14),
        Expanded(child: _buildKPICard('COSTO TOTAL BAJA', '\$ ${_formatearMoneda(costoTotalBaja)}', const Color(0xFFE63946))),
        const SizedBox(width: 14),
        Expanded(child: _buildKPICard('COSTO TOTAL FULL PRICE', '\$ ${_formatearMoneda(costoTotalFullPrice)}', const Color(0xFF7209B7))),
      ],
    );
  }

  Widget _buildKPICard(String titulo, String valor, Color colorBorde) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: colorBorde.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(titulo, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: colorBorde, letterSpacing: 0.5), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBase({required String titulo, Widget? actionRight, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)))),
              if (actionRight != null) actionRight,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GRÁFICAS CIRCULARES
  // ---------------------------------------------------------------------------

  Widget _buildDonaTipo() {
    Map<String, double> mapa = {};
    for (var r in _reportesFiltrados) {
      String t = r['tipo_material_limpio']?.toString() ?? 'Sin Tipo';
      if (t.trim().isEmpty || t == 'NULL') t = 'Sin Tipo';
      mapa[t] = (mapa[t] ?? 0) + 1;
    }
    return _buildCardBase(
      titulo: 'Roturas por Tipo (%)',
      child: SizedBox(height: 200, child: DonutChartWidget(datos: _agruparTop(mapa, 5), colores: const [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF64748B)])),
    );
  }

  Widget _buildDonaAtribuible() {
    Map<String, double> mapa = {'Comportamiento': 0, 'Condición': 0};
    for (var r in _reportesFiltrados) {
      String at = (r['atribuible']?.toString() ?? '').toUpperCase();
      if (at.contains('NO') || at.contains('CONDICI')) {
        mapa['Condición'] = (mapa['Condición'] ?? 0) + 1;
      } else if (at.contains('ATRIBUIBLE') || at.contains('COMPORTAMIENTO')) {
        mapa['Comportamiento'] = (mapa['Comportamiento'] ?? 0) + 1;
      }
    }
    return _buildCardBase(
      titulo: 'Comportamiento vs Condición (%)',
      child: SizedBox(height: 200, child: DonutChartWidget(datos: mapa, colores: const [Color(0xFFEF4444), Color(0xFF64748B)])),
    );
  }

  Widget _buildDonaTopCausales() {
    Map<String, double> mapa = {};
    for (var r in _reportesFiltrados) {
      String c = r['causal']?.toString() ?? 'Otros';
      if (c.trim().isEmpty || c == 'NULL') c = 'Otros';
      if (c.length > 22) c = '${c.substring(0, 20)}...';
      mapa[c] = (mapa[c] ?? 0) + 1;
    }
    return _buildCardBase(
      titulo: 'Top Causales de Rotura',
      child: SizedBox(height: 200, child: DonutChartWidget(datos: _agruparTop(mapa, 5), colores: const [Color(0xFFF36F21), Color(0xFFEF4444), Color(0xFFF59E0B), Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFF64748B)])),
    );
  }

  Map<String, double> _agruparTop(Map<String, double> mapaOriginal, int topN) {
    var sorted = mapaOriginal.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    Map<String, double> topMapa = {};
    double otros = 0;
    for (int i = 0; i < sorted.length; i++) {
      if (i < topN) topMapa[sorted[i].key] = sorted[i].value;
      else otros += sorted[i].value;
    }
    if (otros > 0) topMapa['Otras'] = otros;
    return topMapa;
  }

  // ---------------------------------------------------------------------------
  // TABLAS INTELIGENTES CON ORDENAMIENTO Y TOTALES
  // ---------------------------------------------------------------------------

  Widget _buildTablaTipoMaterial() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String k = r['tipo_material_limpio']?.toString() ?? 'SIN DEFINIR';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'costo': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      agrupados[k]!['costo'] = (agrupados[k]!['costo'] as double) + costo;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'val': v['costo']}));

    return SmartTableWidget(
      titulo: 'Roturas por Tipo Material',
      columnas: const [
        {'key': 'k', 'label': 'TIPO MATERIAL', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'CANTIDAD', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'val', 'label': 'VALOR TOTAL', 'flex': 3, 'type': 'money', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaZona() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    double totalGeneral = 0;
    for (var r in _reportesFiltrados) {
      String k = r['zona']?.toString() ?? 'Sin Zona';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      totalGeneral += cant;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'pct': totalGeneral > 0 ? ((v['cant'] as int) / totalGeneral) * 100 : 0.0}));

    return SmartTableWidget(
      titulo: 'Roturas por Zona',
      columnas: const [
        {'key': 'k', 'label': 'ZONA', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'CANTIDAD', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'pct', 'label': '% TOTAL', 'flex': 2, 'type': 'pct', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaUbicacion() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    double totalGeneral = 0;
    for (var r in _reportesFiltrados) {
      String k = r['ubicacion']?.toString() ?? r['zona']?.toString() ?? 'Sin Ubicación';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      totalGeneral += cant;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'pct': totalGeneral > 0 ? ((v['cant'] as int) / totalGeneral) * 100 : 0.0}));

    return SmartTableWidget(
      titulo: 'Roturas por Ubicación',
      columnas: const [
        {'key': 'k', 'label': 'UBICACIÓN', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'CANTIDAD', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'pct', 'label': '% TOTAL', 'flex': 2, 'type': 'pct', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaOpmDinero() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String k = r['personal']?.toString() ?? r['reportante']?.toString() ?? 'SIN ASIGNAR';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'costo': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      agrupados[k]!['costo'] = (agrupados[k]!['costo'] as double) + costo;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'val': v['costo']}));

    return SmartTableWidget(
      titulo: 'Roturas por OPM y Dinero',
      columnas: const [
        {'key': 'k', 'label': 'OPM', 'flex': 4, 'type': 'text'},
        {'key': 'cant', 'label': 'ROTURAS', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'val', 'label': 'VALOR TOTAL', 'flex': 3, 'type': 'money', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaTopSkus() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String k = r['sku']?.toString() ?? 'SIN SKU';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'costo': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      agrupados[k]!['costo'] = (agrupados[k]!['costo'] as double) + costo;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'val': v['costo']}));

    return SmartTableWidget(
      titulo: 'Top SKUs con mayor Rotura',
      columnas: const [
        {'key': 'k', 'label': 'SKU', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'CANTIDAD', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'val', 'label': 'VALOR TOTAL', 'flex': 3, 'type': 'money', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaEscenario() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String k = r['escenario']?.toString() ?? 'Sin Escenario';
      if (k.trim().isEmpty || k.toUpperCase() == 'NULL') k = 'Sin Escenario';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'costo': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      agrupados[k]!['costo'] = (agrupados[k]!['costo'] as double) + costo;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'val': v['costo']}));

    return SmartTableWidget(
      titulo: 'Roturas por Escenario',
      columnas: const [
        {'key': 'k', 'label': 'ESCENARIO', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'CANTIDAD', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'val', 'label': 'VALOR TOTAL', 'flex': 3, 'type': 'money', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaSupervisor() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String k = r['supervisor']?.toString() ?? 'SIN SUPERVISOR';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'costo': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      agrupados[k]!['costo'] = (agrupados[k]!['costo'] as double) + costo;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length, 'val': v['costo']}));

    return SmartTableWidget(
      titulo: 'Roturas por Supervisor',
      columnas: const [
        {'key': 'k', 'label': 'SUPERVISOR', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'CANTIDAD', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
        {'key': 'val', 'label': 'VALOR TOTAL', 'flex': 3, 'type': 'money', 'sum': true},
      ],
      datos: datos,
    );
  }

  Widget _buildTablaTurno() {
    List<Map<String, dynamic>> datos = [];
    Map<String, Map<String, dynamic>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String k = r['turno']?.toString() ?? 'SIN TURNO';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
      agrupados.putIfAbsent(k, () => {'id': k, 'cant': 0, 'hl': 0.0, 'reins': <String>{}});
      agrupados[k]!['cant'] = (agrupados[k]!['cant'] as int) + cant;
      agrupados[k]!['hl'] = (agrupados[k]!['hl'] as double) + hlVal;
      (agrupados[k]!['reins'] as Set<String>).add(r['id']?.toString() ?? '');
    }
    agrupados.forEach((k, v) => datos.add({'k': k, 'cant': v['cant'], 'hl': v['hl'], 'rein': (v['reins'] as Set).length}));

    return SmartTableWidget(
      titulo: 'Roturas por Turno',
      columnas: const [
        {'key': 'k', 'label': 'TURNO', 'flex': 3, 'type': 'text'},
        {'key': 'cant', 'label': 'ROTURAS', 'flex': 2, 'type': 'num', 'sum': true},
        {'key': 'hl', 'label': 'TOTAL HL', 'flex': 2, 'type': 'hl', 'sum': true},
        {'key': 'rein', 'label': 'REINCID.', 'flex': 2, 'type': 'num'},
      ],
      datos: datos,
    );
  }

  // ---------------------------------------------------------------------------
  // TABLA DE DETALLE COMPLETO
  // ---------------------------------------------------------------------------

  Widget _buildTablaDetalleCompleto() {
    List<Map<String, dynamic>> columnas = [
      {'key': 'fecha', 'label': 'FECHA', 'w': 100.0},
      {'key': 'sup', 'label': 'SUPERVISOR', 'w': 160.0},
      {'key': 'opm', 'label': 'PERSONAL', 'w': 160.0},
      {'key': 'zona', 'label': 'ZONA', 'w': 90.0},
      {'key': 'ub', 'label': 'UBICACIÓN', 'w': 100.0},
      {'key': 'sku', 'label': 'SKU', 'w': 120.0},
      {'key': 'cant', 'label': 'CANT.', 'w': 60.0},
      {'key': 'hl', 'label': 'HL TOTAL', 'w': 80.0},
      {'key': 'causal', 'label': 'CAUSAL', 'w': 200.0},
      {'key': 'obs', 'label': 'OBSERVACIÓN', 'w': 250.0},
      {'key': 'con', 'label': 'CONCILIADOR', 'w': 140.0},
      {'key': 'pbaja', 'label': 'PRECIO BAJA', 'w': 110.0},
      {'key': 'pfull', 'label': 'PRECIO FULL', 'w': 110.0},
      {'key': 'ev', 'label': 'EVIDENCIAS', 'w': 150.0},
    ];

    return _buildCardBase(
      titulo: 'Detalle Completo Roturas',
      actionRight: ElevatedButton.icon(
        onPressed: _descargarExcel,
        icon: const Icon(Icons.download_rounded, size: 14),
        label: const Text('EXCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      child: Container(
        height: 400,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: columnas.fold<double>(0.0, (p, c) => p + (c['w'] as double)),
              child: Column(
                children: [
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFFF8FAFC), border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                    child: Row(
                      children: columnas.map((c) => Container(
                        width: c['w'] as double,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        child: Text(c['label'] as String, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                      )).toList(),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: min(100, _reportesFiltrados.length),
                      itemBuilder: (context, i) {
                        var r = _reportesFiltrados[i];
                        String rawF = r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString() ?? '';
                        String fecha = rawF.isNotEmpty ? rawF.split('T')[0].split(' ')[0] : 'N/A';
                        int cantidad = double.tryParse(r['cantidad']?.toString() ?? '0')?.toInt() ?? 0;
                        double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
                        double costoBaja = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
                        double costoFull = double.tryParse(r['costo_total_full_price']?.toString() ?? '0') ?? 0;

                        String? urlFirma = r['firma_conciliador']?.toString() ?? r['firma']?.toString() ?? r['evidencia_firma']?.toString() ?? r['url_firma']?.toString();
                        String? urlEvento = r['evidencia_evento']?.toString();
                        String? urlCausante = r['evidencia_causante']?.toString() ?? r['evidencia_condicion']?.toString();

                        return Container(
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                          child: Row(
                            children: [
                              _buildFixedCell(columnas[0]['w'] as double, fecha),
                              _buildFixedCell(columnas[1]['w'] as double, r['supervisor']?.toString() ?? 'N/A'),
                              _buildFixedCell(columnas[2]['w'] as double, r['personal']?.toString() ?? r['reportante']?.toString() ?? 'N/A', isBold: true),
                              _buildFixedCell(columnas[3]['w'] as double, r['zona']?.toString() ?? 'N/A'),
                              _buildFixedCell(columnas[4]['w'] as double, r['ubicacion']?.toString() ?? 'N/A'),
                              _buildFixedCell(columnas[5]['w'] as double, r['sku']?.toString() ?? 'N/A', isBold: true),
                              _buildFixedCell(columnas[6]['w'] as double, '$cantidad', isBold: true, color: Colors.red),
                              _buildFixedCell(columnas[7]['w'] as double, hlVal.toStringAsFixed(3), isBold: true, color: Colors.teal.shade800),
                              _buildFixedCell(columnas[8]['w'] as double, r['causal']?.toString() ?? 'N/A'),
                              _buildFixedCell(columnas[9]['w'] as double, r['descripcion']?.toString() ?? r['observacion']?.toString() ?? 'Sin observación'),
                              _buildFixedCell(columnas[10]['w'] as double, r['conciliador']?.toString() ?? 'N/A'),
                              _buildFixedCell(columnas[11]['w'] as double, '\$ ${_formatearMoneda(costoBaja)}', isBold: true, color: Colors.orange.shade800),
                              _buildFixedCell(columnas[12]['w'] as double, '\$ ${_formatearMoneda(costoFull)}', isBold: true, color: Colors.green),
                              Container(
                                width: columnas[13]['w'] as double,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                child: Wrap(
                                  spacing: 4, runSpacing: 4,
                                  children: [
                                    _buildAccionButton('Ver Firma', Icons.draw_rounded, urlFirma),
                                    _buildAccionButton('Ver Foto Evento', Icons.broken_image_rounded, urlEvento),
                                    _buildAccionButton('Ver Foto Causante', Icons.person_search_rounded, urlCausante),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFixedCell(double width, String text, {bool isBold = false, Color color = const Color(0xFF1E293B)}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
    );
  }

  Widget _buildAccionButton(String tooltip, IconData icon, String? rawUrl) {
    String urlLimpia = (rawUrl ?? '').trim();
    bool hasUrl = urlLimpia.isNotEmpty && urlLimpia.toLowerCase() != 'null' && urlLimpia != '[NULL]';

    return Container(
      decoration: BoxDecoration(color: hasUrl ? Colors.blue.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: hasUrl ? Colors.blue.shade200 : Colors.transparent)),
      child: IconButton(
        icon: Icon(icon, color: hasUrl ? Colors.blue.shade700 : Colors.grey.shade400, size: 14),
        tooltip: tooltip,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
        onPressed: hasUrl ? () {
          String linkFinal = urlLimpia;
          if (!linkFinal.startsWith('http') && !linkFinal.contains('Firma_Registrada')) linkFinal = 'https://plantatocancipa.site/uploads/firma_conciliador/$linkFinal';
          _mostrarImagenDialog(linkFinal, tooltip);
        } : null,
      ),
    );
  }

  void _mostrarImagenDialog(String url, String titulo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(30.0), child: Text('La firma o imagen no es un enlace válido o está en formato de texto.', style: TextStyle(color: Colors.red)))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatearMoneda(double valor) {
    return valor.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade600)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w600))),
          ElevatedButton(
            onPressed: _cargarDatosBD,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade600, foregroundColor: Colors.white, elevation: 0),
            child: const Text('REINTENTAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

// ===========================================================================
// COMPONENTE: TABLA INTELIGENTE (STICKY HEADER, SORT, TOTALS)
// ===========================================================================
class SmartTableWidget extends StatefulWidget {
  final String titulo;
  final List<Map<String, dynamic>> columnas;
  final List<Map<String, dynamic>> datos;

  const SmartTableWidget({super.key, required this.titulo, required this.columnas, required this.datos});

  @override
  State<SmartTableWidget> createState() => _SmartTableWidgetState();
}

class _SmartTableWidgetState extends State<SmartTableWidget> {
  String sortCol = '';
  bool sortAsc = false;
  List<Map<String, dynamic>> sortedData = [];

  @override
  void initState() {
    super.initState();
    sortedData = List.from(widget.datos);
    if (widget.columnas.length > 1) {
      sortCol = widget.columnas[1]['key'] as String;
    }
    _aplicarSort();
  }

  @override
  void didUpdateWidget(covariant SmartTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    sortedData = List.from(widget.datos);
    _aplicarSort();
  }

  void _aplicarSort() {
    if (sortCol.isEmpty) return;
    sortedData.sort((a, b) {
      var valA = a[sortCol];
      var valB = b[sortCol];
      if (valA == null) return sortAsc ? 1 : -1;
      if (valB == null) return sortAsc ? -1 : 1;
      int comp = (valA as Comparable).compareTo(valB);
      return sortAsc ? comp : -comp;
    });
  }

  void _onSort(String key) {
    setState(() {
      if (sortCol == key) {
        sortAsc = !sortAsc;
      } else {
        sortCol = key;
        sortAsc = false;
      }
      _aplicarSort();
    });
  }

  String _formatVal(dynamic val, String type) {
    if (val == null) return '-';
    if (type == 'money') return '\$ ${_formatear(val)}';
    if (type == 'hl') return (val as num).toStringAsFixed(2);
    if (type == 'pct') return '${(val as num).toStringAsFixed(1)}%';
    if (type == 'num') return '${(val as num).toInt()}';
    return val.toString();
  }

  Color _getColor(String type) {
    if (type == 'money') return Colors.green.shade700;
    if (type == 'hl') return Colors.teal.shade700;
    if (type == 'num') return Colors.red.shade700;
    if (type == 'pct') return Colors.orange.shade800;
    return const Color(0xFF1E293B);
  }

  String _formatear(dynamic valor) {
    double v = (valor as num).toDouble();
    return v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }

  @override
  Widget build(BuildContext context) {
    Map<String, double> totales = {};
    for (var c in widget.columnas) {
      if (c['sum'] == true) {
        double s = 0;
        for (var row in widget.datos) {
          s += (row[c['key']] as num).toDouble();
        }
        totales[c['key'] as String] = s;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const SizedBox(height: 12),
          Container(
            height: 250,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Container(
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(8)), border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
                  child: Row(
                    children: widget.columnas.map((c) => Expanded(
                      flex: c['flex'] as int,
                      child: InkWell(
                        onTap: () => _onSort(c['key'] as String),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text(c['label'] as String, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFF475569), letterSpacing: 0.5), overflow: TextOverflow.ellipsis)),
                              if (sortCol == c['key']) Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: const Color(0xFFF36F21)),
                            ],
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: sortedData.length,
                    itemBuilder: (ctx, i) {
                      var row = sortedData[i];
                      return Container(
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                        child: Row(
                          children: widget.columnas.map((c) => Expanded(
                            flex: c['flex'] as int,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              child: Text(
                                _formatVal(row[c['key']], c['type'] as String),
                                style: TextStyle(fontSize: 10.5, fontWeight: c['type'] == 'text' ? FontWeight.w600 : FontWeight.w800, color: _getColor(c['type'] as String)),
                              ),
                            ),
                          )).toList(),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)), border: Border(top: BorderSide(color: Colors.orange.shade200))),
                  child: Row(
                    children: widget.columnas.map((c) => Expanded(
                      flex: c['flex'] as int,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        child: Text(
                          c['sum'] == true ? _formatVal(totales[c['key']], c['type'] as String) : (c == widget.columnas.first ? 'TOTALES' : ''),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c['sum'] == true ? _getColor(c['type'] as String) : Colors.black87),
                        ),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// COMPONENTE: GRÁFICA DIARIA
// ===========================================================================
class EvolucionDiariaChart extends StatelessWidget {
  final List<Map<String, dynamic>> reportes;
  final DateTime fechaDesde, fechaHasta;
  const EvolucionDiariaChart({super.key, required this.reportes, required this.fechaDesde, required this.fechaHasta});

  @override
  Widget build(BuildContext context) {
    Map<int, double> conteoDias = {};
    for (var r in reportes) {
      String? rawFecha = r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString();
      if (rawFecha != null && rawFecha.isNotEmpty) {
        DateTime? dt = DateTime.tryParse(rawFecha.split('T')[0].split(' ')[0]);
        if (dt != null) conteoDias[dt.day] = (conteoDias[dt.day] ?? 0.0) + (double.tryParse(r['cantidad']?.toString() ?? '1') ?? 1.0);
      }
    }
    List<int> dias = []; List<double> valores = [];
    int totalDias = max(1, fechaHasta.difference(fechaDesde).inDays + 1);
    for (int i = 0; i < min(totalDias, 31); i++) {
      DateTime curr = fechaDesde.add(Duration(days: i));
      dias.add(curr.day); valores.add(conteoDias[curr.day] ?? 0);
    }
    if (valores.isEmpty || valores.every((v) => v == 0)) return const Center(child: Text('Sin datos en el rango', style: TextStyle(color: Colors.grey)));
    return CustomPaint(painter: _SmoothLineChartPainter(dias: dias, valores: valores), child: Container());
  }
}

class _SmoothLineChartPainter extends CustomPainter {
  final List<int> dias; final List<double> valores;
  _SmoothLineChartPainter({required this.dias, required this.valores});

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;
    double maxVal = max(10, valores.reduce(max));
    double pL = 30, pB = 20, w = size.width - pL, h = size.height - pB;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      double y = h - (i * (h / 4));
      canvas.drawLine(Offset(pL, y), Offset(size.width, y), gridPaint);
      TextPainter(text: TextSpan(text: '${(maxVal / 4 * i).toInt()}', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(0, y - 6));
    }

    double stepX = w / max(1, valores.length - 1);
    List<Offset> pts = [];
    for (int i = 0; i < valores.length; i++) {
      double x = pL + (i * stepX), y = h - ((valores[i] / maxVal) * (h - 20));
      pts.add(Offset(x, y));
      TextPainter(text: TextSpan(text: dias[i].toString().padLeft(2, '0'), style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(x - 6, h + 6));
    }

    Path path = Path()..moveTo(pts[0].dx, pts[0].dy);
    Path fill = Path()..moveTo(pts[0].dx, h)..lineTo(pts[0].dx, pts[0].dy);

    for (int i = 0; i < pts.length - 1; i++) {
      double cx1 = pts[i].dx + (pts[i + 1].dx - pts[i].dx) / 2;
      path.cubicTo(cx1, pts[i].dy, cx1, pts[i + 1].dy, pts[i + 1].dx, pts[i + 1].dy);
      fill.cubicTo(cx1, pts[i].dy, cx1, pts[i + 1].dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    fill..lineTo(pts.last.dx, h)..close();

    canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFFF36F21).withOpacity(0.3), const Color(0xFFF36F21).withOpacity(0.0)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(path, Paint()..color = const Color(0xFFF36F21)..strokeWidth = 3..style = PaintingStyle.stroke);

    for (int i = 0; i < pts.length; i++) {
      if (valores[i] > 0) {
        canvas.drawCircle(pts[i], 4, Paint()..color = const Color(0xFFF36F21));
        canvas.drawCircle(pts[i], 4, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
        TextPainter(text: TextSpan(text: '${valores[i].toInt()}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFD84315))), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(pts[i].dx - 6, pts[i].dy - 16));
      }
    }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

// ===========================================================================
// COMPONENTE NUEVO: GRÁFICA MENSUAL (SOLO MESES ACTIVOS Y CON BARRAS)
// ===========================================================================
class EvolucionMensualChart extends StatelessWidget {
  final List<Map<String, dynamic>> reportes;
  const EvolucionMensualChart({super.key, required this.reportes});

  @override
  Widget build(BuildContext context) {
    List<double> mesesTotales = List.filled(12, 0.0);
    final List<String> nombresMeses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    for (var r in reportes) {
      String? rawFecha = r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString();
      if (rawFecha != null && rawFecha.isNotEmpty) {
        DateTime? dt = DateTime.tryParse(rawFecha.split('T')[0].split(' ')[0]);
        if (dt != null) {
          double cant = double.tryParse(r['cantidad']?.toString() ?? '1') ?? 1.0;
          mesesTotales[dt.month - 1] += cant;
        }
      }
    }

    List<String> mesesActivos = [];
    List<double> valoresActivos = [];

    for (int i = 0; i < 12; i++) {
      if (mesesTotales[i] > 0) {
        mesesActivos.add(nombresMeses[i]);
        valoresActivos.add(mesesTotales[i]);
      }
    }

    if (valoresActivos.isEmpty) {
      return const Center(child: Text('Sin datos en todo el año para este filtro', style: TextStyle(color: Colors.grey)));
    }

    return CustomPaint(painter: _BarChartMensualPainter(meses: mesesActivos, valores: valoresActivos), child: Container());
  }
}

class _BarChartMensualPainter extends CustomPainter {
  final List<String> meses;
  final List<double> valores;
  _BarChartMensualPainter({required this.meses, required this.valores});

  @override
  void paint(Canvas canvas, Size size) {
    double maxVal = max(10, valores.reduce(max)) * 1.35;
    double pL = 35, pB = 20, w = size.width - pL, h = size.height - pB;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      double y = h - (i * (h / 4));
      canvas.drawLine(Offset(pL, y), Offset(size.width, y), gridPaint);

      double val = (maxVal / 4 * i);
      String label = val >= 1000 ? '${(val / 1000).toStringAsFixed(1)}k' : val.toInt().toString();

      TextPainter tp = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(pL - tp.width - 6, y - 6));
    }

    int cantidadMeses = meses.length;
    double stepX = w / cantidadMeses;

    double barWidth = cantidadMeses == 1 ? 60.0 : min(stepX * 0.5, 50.0);

    final paintBar = Paint()..style = PaintingStyle.fill;
    final paintEmpty = Paint()..color = Colors.grey.shade50..style = PaintingStyle.fill;

    for (int i = 0; i < cantidadMeses; i++) {
      double cx = pL + (i * stepX) + (stepX / 2);
      double barH = (valores[i] / maxVal) * h;
      double barY = h - barH;

      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, h / 2), width: barWidth, height: h), const Radius.circular(4)), paintEmpty);

      paintBar.color = const Color(0xFF00B4D8);
      canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTRB(cx - barWidth / 2, barY, cx + barWidth / 2, h), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), paintBar);

      String valorStr = valores[i].toInt().toString();
      TextPainter tpVal = TextPainter(text: TextSpan(text: valorStr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF0077B6))), textDirection: TextDirection.ltr)..layout();
      tpVal.paint(canvas, Offset(cx - (tpVal.width / 2), barY - 16));

      TextPainter tpLbl = TextPainter(text: TextSpan(text: meses[i], style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tpLbl.paint(canvas, Offset(cx - (tpLbl.width / 2), h + 6));
    }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

// ===========================================================================
// COMPONENTE: GRÁFICA DONA
// ===========================================================================
class DonutChartWidget extends StatelessWidget {
  final Map<String, double> datos;
  final List<Color> colores;
  const DonutChartWidget({super.key, required this.datos, required this.colores});

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) return const Center(child: Text('Sin datos', style: TextStyle(color: Colors.grey)));
    double total = datos.values.fold<double>(0.0, (sum, item) => sum + item);

    return Row(
      children: [
        Expanded(flex: 5, child: CustomPaint(painter: _DonutPainter(datos: datos, colores: colores, total: total), child: Container())),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: datos.keys.toList().asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Row(
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: colores[e.key % colores.length], borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e.value, style: const TextStyle(fontSize: 9, color: Color(0xFF475569), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        )
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final Map<String, double> datos; final List<Color> colores; final double total;
  _DonutPainter({required this.datos, required this.colores, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    double startAngle = -pi / 2;
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = min(size.width, size.height) / 2 - 8;
    final paintArc = Paint()..style = PaintingStyle.fill;

    int idx = 0;
    datos.forEach((key, val) {
      if (val > 0) {
        double sweepAngle = (val / total) * 2 * pi;
        paintArc.color = colores[idx % colores.length];
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, true, paintArc);

        double pct = (val / total) * 100;
        if (pct >= 5) {
          double mid = startAngle + (sweepAngle / 2);
          TextPainter(text: TextSpan(text: '${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(center.dx + (radius * 0.65) * cos(mid) - 12, center.dy + (radius * 0.65) * sin(mid) - 6));
        }
        startAngle += sweepAngle;
      }
      idx++;
    });
    canvas.drawCircle(center, radius * 0.55, Paint()..color = Colors.white);
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}