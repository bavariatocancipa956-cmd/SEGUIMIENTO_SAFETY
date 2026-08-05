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

  DateTime _fechaDesde = DateTime(2026, 7, 1);
  DateTime _fechaHasta = DateTime(2026, 7, 27);

  // Filtros - Listas de opciones disponibles
  List<String> _listaTurnos = [];
  List<String> _listaSupervisores = [];
  List<String> _listaAreas = [];
  List<String> _listaAtribuibles = ['ATRIBUIBLE', 'NO ATRIBUIBLE'];
  List<String> _listaTipos = [];
  List<String> _listaOpms = [];
  List<String> _listaCausales = [];
  List<String> _listaEscenarios = [];
  List<String> _listaZonas = [];

  // Filtros - Selecciones actuales (Múltiple)
  List<String> _turnosSel = [];
  List<String> _supervisoresSel = [];
  List<String> _areasSel = [];
  List<String> _atribuiblesSel = [];
  List<String> _tiposSel = [];
  List<String> _opmsSel = [];
  List<String> _causalesSel = [];
  List<String> _escenariosSel = [];
  List<String> _zonasSel = [];

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
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> datosRaw = body['data'] ?? [];

        final List<Map<String, dynamic>> datosProcesados = [];

        final Set<String> turnos = {};
        final Set<String> supervisores = {};
        final Set<String> areas = {};
        final Set<String> tipos = {};
        final Set<String> opms = {};
        final Set<String> causales = {};
        final Set<String> escenarios = {};
        final Set<String> zonas = {};

        for (var fila in datosRaw) {
          if (fila is Map) {
            final Map<String, dynamic> mapa = {};
            fila.forEach((key, val) => mapa[key.toString().toLowerCase()] = val);
            datosProcesados.add(mapa);

            String? t = mapa['turno']?.toString();
            String? sup = mapa['supervisor']?.toString();
            String? area = mapa['area']?.toString();
            String? tipo = mapa['tipo_material_2']?.toString() ?? mapa['tipo_material']?.toString();
            String? opm = mapa['personal']?.toString() ?? mapa['reportante']?.toString();
            String? causal = mapa['causal']?.toString();
            String? escenario = mapa['escenario']?.toString();
            String? zona = mapa['zona']?.toString();

            if (t != null && t.trim().isNotEmpty) turnos.add(t.trim());
            if (sup != null && sup.trim().isNotEmpty) supervisores.add(sup.trim());
            if (area != null && area.trim().isNotEmpty) areas.add(area.trim());
            if (tipo != null && tipo.trim().isNotEmpty) tipos.add(tipo.trim());
            if (opm != null && opm.trim().isNotEmpty && opm.toUpperCase() != 'NULL') opms.add(opm.trim());
            if (causal != null && causal.trim().isNotEmpty && causal.toUpperCase() != 'NULL') causales.add(causal.trim());
            if (escenario != null && escenario.trim().isNotEmpty && escenario.toUpperCase() != 'NULL') escenarios.add(escenario.trim());
            if (zona != null && zona.trim().isNotEmpty && zona.toUpperCase() != 'NULL') zonas.add(zona.trim());
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

          // Inicializar filtros con todas las opciones seleccionadas por defecto
          _turnosSel = List.from(_listaTurnos);
          _supervisoresSel = List.from(_listaSupervisores);
          _areasSel = List.from(_listaAreas);
          _atribuiblesSel = List.from(_listaAtribuibles);
          _tiposSel = List.from(_listaTipos);
          _opmsSel = List.from(_listaOpms);
          _causalesSel = List.from(_listaCausales);
          _escenariosSel = List.from(_listaEscenarios);
          _zonasSel = List.from(_listaZonas);

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

  void _aplicarFiltros() {
    setState(() {
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

        String turnoRow = row['turno']?.toString() ?? '';
        String supRow = row['supervisor']?.toString() ?? '';
        String areaRow = row['area']?.toString() ?? '';
        String tipoRow = row['tipo_material_2']?.toString() ?? row['tipo_material']?.toString() ?? '';
        String opmRow = row['personal']?.toString() ?? row['reportante']?.toString() ?? '';
        String causalRow = row['causal']?.toString() ?? '';
        String escRow = row['escenario']?.toString() ?? '';
        String zonaRow = row['zona']?.toString() ?? '';

        if (_turnosSel.isNotEmpty && !(_turnosSel.contains(turnoRow))) return false;
        if (_supervisoresSel.isNotEmpty && !(_supervisoresSel.contains(supRow))) return false;
        if (_areasSel.isNotEmpty && !(_areasSel.contains(areaRow))) return false;
        if (_tiposSel.isNotEmpty && !(_tiposSel.contains(tipoRow))) return false;
        if (_opmsSel.isNotEmpty && !(_opmsSel.contains(opmRow))) return false;
        if (_causalesSel.isNotEmpty && !(_causalesSel.contains(causalRow))) return false;
        if (_escenariosSel.isNotEmpty && !(_escenariosSel.contains(escRow))) return false;
        if (_zonasSel.isNotEmpty && !(_zonasSel.contains(zonaRow))) return false;

        if (_atribuiblesSel.isNotEmpty) {
          String at = (row['atribuible']?.toString() ?? '').toUpperCase();
          bool esNo = at.contains('NO');
          bool esAtr = at.contains('ATRIBUIBLE') && !esNo;

          bool pasaFiltro = false;
          if (_atribuiblesSel.contains('NO ATRIBUIBLE') && esNo) pasaFiltro = true;
          if (_atribuiblesSel.contains('ATRIBUIBLE') && esAtr) pasaFiltro = true;

          if (!pasaFiltro && (esNo || esAtr)) return false;
        }

        return true;
      }).toList();
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
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "Reporte_Dashboard_Roturas.png")
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint("Error al tomar la foto: $e");
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

  void _descargarExcel() {
    if (_reportesFiltrados.isEmpty) return;

    StringBuffer sb = StringBuffer();
    sb.write('\uFEFF');
    sb.writeln("FECHA;SUPERVISOR;PERSONAL INVOLUCRADO;ZONA;UBICACION;SKU;CANTIDAD;HL TOTAL;CAUSAL;OBSERVACION;CONCILIADOR;PRECIO BAJA TOTAL;PRECIO BAJA FULL PRICE");

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
      String obs = (r['descripcion']?.toString() ?? r['observacion']?.toString() ?? 'Sin observación').replaceAll(';', ',').replaceAll('\n', ' ');
      String conciliador = (r['conciliador']?.toString() ?? 'N/A').replaceAll(';', ',').replaceAll('\n', ' ');

      double costoBaja = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double costoFull = double.tryParse(r['costo_total_full_price']?.toString() ?? '0') ?? 0;

      sb.writeln("$fecha;$supervisor;$personal;$zona;$ubicacion;$sku;$cantidad;${hlTotal.toStringAsFixed(3)};$causal;$obs;$conciliador;${costoBaja.toStringAsFixed(0)};${costoFull.toStringAsFixed(0)}");
    }

    final bytes = utf8.encode(sb.toString());
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "Reporte_Roturas_Tocancipa.csv")
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  // ===========================================================================
  // 📂 MOTOR DE EVIDENCIAS Y PLANES DE ACCIÓN (INVESTIGACION)
  // ===========================================================================

  Widget _buildBotonEvidenciaInvestigacion(Map<String, dynamic> filaBase) {
    String inv = filaBase['investigacion']?.toString() ?? '';
    bool tieneEvidencia = inv.isNotEmpty && inv.toLowerCase() != 'null' && inv != '[NULL]';

    if (tieneEvidencia) {
      return InkWell(
        onTap: () {
          String linkFinal = inv;
          if (!linkFinal.startsWith('http')) {
            linkFinal = 'https://plantatocancipa.site/uploads/investigacion/$inv';
          }
          if (linkFinal.toLowerCase().endsWith('.pdf')) {
            html.window.open(linkFinal, '_blank');
          } else {
            _mostrarImagenDialog(linkFinal, 'Evidencia de Acción / FMS');
          }
        },
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: Colors.green.shade400), borderRadius: BorderRadius.circular(4)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 10),
                SizedBox(width: 4),
                Text('Ver', style: TextStyle(fontSize: 8, color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            )
        ),
      );
    } else {
      return InkWell(
        onTap: () => _seleccionarYSubirEvidencia(filaBase),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red.shade400), borderRadius: BorderRadius.circular(4)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.close_rounded, color: Colors.red, size: 10),
                SizedBox(width: 4),
                Text('Cargar', style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            )
        ),
      );
    }
  }

  void _seleccionarYSubirEvidencia(Map<String, dynamic> filaBase) {
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = '.pdf, image/jpeg, image/png';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        setState(() {
          filaBase['investigacion'] = 'https://plantatocancipa.site/uploads/simulacion_${file.name}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Evidencia cargada exitosamente: ${file.name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            )
        );
      }
    });
  }

  Widget _buildTablaEventosCriticos() {
    var filtrados = _reportesFiltrados.where((r) {
      String personal = r['personal']?.toString() ?? r['reportante']?.toString() ?? 'N/A';
      String pUpper = personal.trim().toUpperCase();
      if (pUpper == 'NO APLICA' || pUpper == 'N/A' || pUpper == 'NULL' || pUpper.isEmpty) {
        return false;
      }
      double cant = double.tryParse(r['cantidad']?.toString() ?? '0') ?? 0;
      return cant >= 150;
    }).toList();

    filtrados.sort((a,b) => (b['fecha_evento']?.toString() ?? '').compareTo(a['fecha_evento']?.toString() ?? ''));

    return _buildCardTablaAction(
        titulo: 'Plan de Acción - Críticos (≥ 150 und por evento)',
        columnas: const ['FECHA', 'PERSONAL', 'ROTURA', 'HL TOTAL', 'ACCIÓN', 'EVIDENCIA'],
        filas: filtrados.map((e) {
          String rawF = e['fecha_evento']?.toString() ?? e['timestamp_registro']?.toString() ?? '';
          String fecha = rawF.isNotEmpty ? rawF.split('T')[0].split(' ')[0] : 'N/A';
          String personal = e['personal']?.toString() ?? e['reportante']?.toString() ?? 'N/A';
          double cant = double.tryParse(e['cantidad']?.toString() ?? '0') ?? 0;
          double hlVal = _parseHl(e['hl_total'] ?? e['hl']);

          String accion = cant >= 350 ? 'Realizar Investigación' : 'Realizar 5WHY';
          Color cColor = cant >= 350 ? Colors.red : Colors.orange.shade800;

          return [
            Text(fecha, style: const TextStyle(fontSize: 9)),
            Text(personal, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            Text('${cant.toInt()}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cColor)),
            Text(hlVal.toStringAsFixed(3), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.teal)),
            Text(accion, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cColor)),
            _buildBotonEvidenciaInvestigacion(e),
          ];
        }).toList()
    );
  }

  Widget _buildTablaReincidencias() {
    Map<String, List<Map<String, dynamic>>> agrupados = {};
    for (var r in _reportesFiltrados) {
      String p = r['personal']?.toString() ?? r['reportante']?.toString() ?? 'N/A';
      String pUpper = p.trim().toUpperCase();
      if (pUpper.isNotEmpty && pUpper != 'NULL' && pUpper != 'N/A' && pUpper != 'NO APLICA') {
        agrupados.putIfAbsent(pUpper, () => []).add(r);
      }
    }

    var reincidentes = agrupados.entries.where((e) => e.value.length >= 2).toList();
    reincidentes.sort((a, b) => b.value.length.compareTo(a.value.length));

    return _buildCardTablaAction(
        titulo: 'Plan de Acción - Reincidencias',
        columnas: const ['FECHA', 'PERSONAL', 'REINCIDENCIAS', 'HL TOTAL', 'ACCIÓN', 'EVIDENCIA'],
        filas: reincidentes.map((e) {
          var eventos = e.value;
          eventos.sort((a, b) => (b['fecha_evento']?.toString() ?? '').compareTo(a['fecha_evento']?.toString() ?? ''));
          var ultimoEvento = eventos.first;

          String rawF = ultimoEvento['fecha_evento']?.toString() ?? ultimoEvento['timestamp_registro']?.toString() ?? '';
          String fecha = rawF.isNotEmpty ? rawF.split('T')[0].split(' ')[0] : 'N/A';
          int cantidadReincidencias = eventos.length;
          double hlAcumulado = eventos.fold(0.0, (sum, item) => sum + _parseHl(item['hl_total'] ?? item['hl']));

          String accion;
          Color aColor;
          if (cantidadReincidencias == 2) {
            accion = 'Abordaje';
            aColor = Colors.orange.shade800;
          } else if (cantidadReincidencias == 3) {
            accion = 'Entrenamiento y llamado\nde atención';
            aColor = Colors.redAccent;
          } else {
            accion = 'Comité de FMS';
            aColor = Colors.red.shade900;
          }

          return [
            Text(fecha, style: const TextStyle(fontSize: 9)),
            Text(e.key, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            Text('$cantidadReincidencias', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
            Text(hlAcumulado.toStringAsFixed(3), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.teal)),
            Text(accion, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: aColor)),
            _buildBotonEvidenciaInvestigacion(ultimoEvento),
          ];
        }).toList()
    );
  }

  // ===========================================================================
  // 🔨 CONSTRUCCIÓN DEL LAYOUT
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F3F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: RepaintBoundary(
          key: _capturaKey,
          child: Container(
            color: const Color(0xFFF1F3F9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_mensajeError != null) _buildBannerError(),

                _buildBarraFiltros(),
                const SizedBox(height: 16),

                _buildTarjetasKPI(),
                const SizedBox(height: 16),

                _buildCardBase(
                  titulo: 'Evolución Diaria de Roturas (Cantidades)',
                  child: SizedBox(
                    height: 240,
                    child: EvolucionDiariaChart(
                      reportes: _reportesFiltrados,
                      fechaDesde: _fechaDesde,
                      fechaHasta: _fechaHasta,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildDonaTipo()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDonaAtribuible()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDonaTopCausales()),
                  ],
                ),
                const SizedBox(height: 16),

                // 🌟 NUEVA FILA DE TABLAS ZONA y TIPO MATERIAL
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaZona()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTablaTipoMaterial()),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaUbicacion()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTablaOpmDinero()),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaTopSkus()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTablaEscenario()),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaSupervisor()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTablaTurno()),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTablaEventosCriticos()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTablaReincidencias()),
                  ],
                ),
                const SizedBox(height: 16),

                _buildTablaDetalleCompleto(),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBarraFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildSelectorFecha('DESDE', _fechaDesde, (d) => setState(() => _fechaDesde = d)),
          _buildSelectorFecha('HASTA', _fechaHasta, (d) => setState(() => _fechaHasta = d)),

          _buildMultiSelect('TURNO', _listaTurnos, _turnosSel, (sel) => setState(() => _turnosSel = sel)),
          _buildMultiSelect('SUPERVISOR', _listaSupervisores, _supervisoresSel, (sel) => setState(() => _supervisoresSel = sel)),
          _buildMultiSelect('ÁREA', _listaAreas, _areasSel, (sel) => setState(() => _areasSel = sel)),
          _buildMultiSelect('ATRIBUIBLE', _listaAtribuibles, _atribuiblesSel, (sel) => setState(() => _atribuiblesSel = sel)),
          _buildMultiSelect('TIPO MAT.', _listaTipos, _tiposSel, (sel) => setState(() => _tiposSel = sel)),
          _buildMultiSelect('OPM', _listaOpms, _opmsSel, (sel) => setState(() => _opmsSel = sel)),
          _buildMultiSelect('CAUSAL', _listaCausales, _causalesSel, (sel) => setState(() => _causalesSel = sel)),
          _buildMultiSelect('ESCENARIO', _listaEscenarios, _escenariosSel, (sel) => setState(() => _escenariosSel = sel)),
          _buildMultiSelect('ZONA', _listaZonas, _zonasSel, (sel) => setState(() => _zonasSel = sel)),

          ElevatedButton.icon(
            onPressed: _aplicarFiltros,
            icon: const Icon(Icons.filter_alt_rounded, size: 14),
            label: const Text('FILTRAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF36F21),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _tomarCapturaFoto,
            icon: const Icon(Icons.camera_alt, size: 14),
            label: const Text('FOTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF455A64),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _activarModoTV,
            icon: const Icon(Icons.tv_rounded, size: 14),
            label: const Text('TV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2138),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
              ],
            ),
          ),
        )
      ],
    );
  }

  // 🌟 NUEVO WIDGET PARA FILTROS MULTIPLE SELECCIÓN (CHECKBOX)
  Widget _buildMultiSelect(String label, List<String> opciones, List<String> seleccionados, Function(List<String>) onChanged) {
    String textLabel;
    if (seleccionados.length == opciones.length) {
      textLabel = 'Todos';
    } else if (seleccionados.isEmpty) {
      textLabel = 'Ninguno';
    } else {
      textLabel = '${seleccionados.length} selecc.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 3),
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
                            width: 300,
                            height: 400,
                            child: Column(
                              children: [
                                CheckboxListTile(
                                    title: const Text('Seleccionar Todos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    value: todosSeleccionados,
                                    activeColor: const Color(0xFFF36F21),
                                    onChanged: (v) {
                                      setStateSB(() {
                                        if (v == true) {
                                          tempSel = List.from(opciones);
                                        } else {
                                          tempSel.clear();
                                        }
                                      });
                                    }
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: opciones.length,
                                    itemBuilder: (context, index) {
                                      String op = opciones[index];
                                      bool isSel = tempSel.contains(op);
                                      return CheckboxListTile(
                                        dense: true,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        activeColor: const Color(0xFFF36F21),
                                        title: Text(op, style: const TextStyle(fontSize: 11)),
                                        value: isSel,
                                        onChanged: (v) {
                                          setStateSB(() {
                                            if (v == true) {
                                              tempSel.add(op);
                                            } else {
                                              tempSel.remove(op);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.grey))
                            ),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF36F21), foregroundColor: Colors.white),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  onChanged(tempSel);
                                },
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
            constraints: const BoxConstraints(minWidth: 90),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(5),
              color: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(textLabel, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetasKPI() {
    int totalEventos = _reportesFiltrados.length;
    double totalUnidades = 0;
    double totalHl = 0;
    double costoTotalBaja = 0;
    double costoTotalFullPrice = 0;

    for (var r in _reportesFiltrados) {
      totalUnidades += double.tryParse(r['cantidad']?.toString() ?? '0') ?? 0;
      totalHl += _parseHl(r['hl_total'] ?? r['hl']);
      costoTotalBaja += double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      costoTotalFullPrice += double.tryParse(r['costo_total_full_price']?.toString() ?? '0') ?? 0;
    }

    return Row(
      children: [
        Expanded(child: _buildKPICard('TOTAL EVENTOS', '$totalEventos', const Color(0xFFF36F21))),
        const SizedBox(width: 10),
        Expanded(child: _buildKPICard('TOTAL UNIDADES ROTAS', '${totalUnidades.toInt()}', const Color(0xFFF36F21))),
        const SizedBox(width: 10),
        Expanded(child: _buildKPICard('HL TOTAL', totalHl.toStringAsFixed(2), const Color(0xFF00796B))),
        const SizedBox(width: 10),
        Expanded(child: _buildKPICard('COSTO TOTAL BAJA', '\$ ${_formatearMoneda(costoTotalBaja)}', const Color(0xFFD84315))),
        const SizedBox(width: 10),
        Expanded(child: _buildKPICard('COSTO TOTAL FULL PRICE', '\$ ${_formatearMoneda(costoTotalFullPrice)}', const Color(0xFF8E24AA))),
      ],
    );
  }

  Widget _buildKPICard(String titulo, String valor, Color colorBorde) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: colorBorde, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
      ),
      child: Column(
        children: [
          Text(titulo, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDonaTipo() {
    Map<String, double> mapa = {};
    for (var r in _reportesFiltrados) {
      String t = r['tipo_material_2']?.toString() ?? r['tipo_material']?.toString() ?? 'Sin Tipo';
      mapa[t] = (mapa[t] ?? 0) + 1;
    }
    return _buildCardBase(
      titulo: 'Roturas por Tipo (%)',
      child: SizedBox(
        height: 190,
        child: DonutChartWidget(
          datos: mapa,
          colores: const [Color(0xFF4285F4), Color(0xFF00C853), Color(0xFFFFB300), Color(0xFFE53935)],
        ),
      ),
    );
  }

  Widget _buildDonaAtribuible() {
    Map<String, double> mapa = {'ATRIBUIBLE': 0, 'NO ATRIBUIBLE': 0};
    for (var r in _reportesFiltrados) {
      String at = (r['atribuible']?.toString() ?? '').toUpperCase();
      if (at.contains('NO')) {
        mapa['NO ATRIBUIBLE'] = (mapa['NO ATRIBUIBLE'] ?? 0) + 1;
      } else if (at.contains('ATRIBUIBLE')) {
        mapa['ATRIBUIBLE'] = (mapa['ATRIBUIBLE'] ?? 0) + 1;
      }
    }
    return _buildCardBase(
      titulo: 'Atribuible vs No Atribuible (%)',
      child: SizedBox(
        height: 190,
        child: DonutChartWidget(
          datos: mapa,
          colores: const [Color(0xFFEF5350), Color(0xFF546E7A)],
        ),
      ),
    );
  }

  Widget _buildDonaTopCausales() {
    Map<String, double> mapa = {};
    for (var r in _reportesFiltrados) {
      String c = r['causal']?.toString() ?? 'Otros';
      if (c.length > 20) c = '${c.substring(0, 18)}...';
      mapa[c] = (mapa[c] ?? 0) + 1;
    }
    return _buildCardBase(
      titulo: 'Top Causales de Rotura',
      child: SizedBox(
        height: 190,
        child: DonutChartWidget(
          datos: mapa,
          colores: const [Color(0xFFF36F21), Color(0xFFE53935), Color(0xFFFFB300), Color(0xFF4285F4), Color(0xFF00C853), Color(0xFFAB47BC)],
        ),
      ),
    );
  }

  // 🌟 NUEVA TABLA: TIPO MATERIAL 2
  Widget _buildTablaTipoMaterial() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, double> costos = {};
    Map<String, Set<String>> reincidencias = {};

    for (var r in _reportesFiltrados) {
      String tm = r['tipo_material_2']?.toString() ?? r['tipo_material']?.toString() ?? 'SIN DEFINIR';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[tm] = (conteo[tm] ?? 0) + cant;
      hlConteo[tm] = (hlConteo[tm] ?? 0) + hlVal;
      costos[tm] = (costos[tm] ?? 0) + costo;
      reincidencias.putIfAbsent(tm, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por Tipo Material',
      columnas: const ['TIPO MATERIAL', 'CANTIDAD', 'TOTAL HL', 'REINCID.', 'VALOR TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(1.4),
      },
      filas: ordenados.map((e) {
        double val = costos[e.key] ?? 0;
        int rein = reincidencias[e.key]?.length ?? 1;
        double hlTm = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(hlTm.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('\$ ${_formatearMoneda(val)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
        ];
      }).toList(),
    );
  }

  // 🌟 NUEVA TABLA: ZONA
  Widget _buildTablaZona() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, Set<String>> reincidencias = {};
    double totalGeneral = 0;

    for (var r in _reportesFiltrados) {
      String z = r['zona']?.toString() ?? 'Sin Zona';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[z] = (conteo[z] ?? 0) + cant;
      hlConteo[z] = (hlConteo[z] ?? 0) + hlVal;
      totalGeneral += cant;
      reincidencias.putIfAbsent(z, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por Zona',
      columnas: const ['ZONA', 'CANTIDAD', 'TOTAL HL', 'REINCID.', '% TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(1.0),
      },
      filas: ordenados.map((e) {
        double pct = totalGeneral > 0 ? (e.value / totalGeneral) * 100 : 0;
        int rein = (reincidencias[e.key]?.length ?? 1);
        double totalHlLoc = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(totalHlLoc.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
        ];
      }).toList(),
    );
  }

  Widget _buildTablaUbicacion() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, Set<String>> reincidencias = {};
    double totalGeneral = 0;

    for (var r in _reportesFiltrados) {
      String u = r['ubicacion']?.toString() ?? r['zona']?.toString() ?? 'Sin Ubicación';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[u] = (conteo[u] ?? 0) + cant;
      hlConteo[u] = (hlConteo[u] ?? 0) + hlVal;
      totalGeneral += cant;
      reincidencias.putIfAbsent(u, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por Ubicación',
      columnas: const ['UBICACIÓN', 'CANTIDAD', 'TOTAL HL', 'REINCIDENCIA', '% TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.0),
        4: FlexColumnWidth(1.0),
      },
      filas: ordenados.map((e) {
        double pct = totalGeneral > 0 ? (e.value / totalGeneral) * 100 : 0;
        int rein = (reincidencias[e.key]?.length ?? 1);
        double totalHlLoc = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(totalHlLoc.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange)),
        ];
      }).toList(),
    );
  }

  Widget _buildTablaOpmDinero() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, double> costos = {};
    Map<String, Set<String>> reincidencias = {};

    for (var r in _reportesFiltrados) {
      String opm = r['personal']?.toString() ?? r['reportante']?.toString() ?? 'SIN ASIGNAR';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[opm] = (conteo[opm] ?? 0) + cant;
      hlConteo[opm] = (hlConteo[opm] ?? 0) + hlVal;
      costos[opm] = (costos[opm] ?? 0) + costo;
      reincidencias.putIfAbsent(opm, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por OPM y Dinero',
      columnas: const ['OPM', 'ROTURAS', 'TOTAL HL', 'REINCIDENCIA', 'VALOR TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.0),
        4: FlexColumnWidth(1.4),
      },
      filas: ordenados.map((e) {
        double val = costos[e.key] ?? 0;
        int rein = reincidencias[e.key]?.length ?? 1;
        double hlOpm = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(hlOpm.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('\$ ${_formatearMoneda(val)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
        ];
      }).toList(),
    );
  }

  Widget _buildTablaTopSkus() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, double> costos = {};
    Map<String, Set<String>> reincidencias = {};

    for (var r in _reportesFiltrados) {
      String sku = r['sku']?.toString() ?? 'SIN SKU';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[sku] = (conteo[sku] ?? 0) + cant;
      hlConteo[sku] = (hlConteo[sku] ?? 0) + hlVal;
      costos[sku] = (costos[sku] ?? 0) + costo;
      reincidencias.putIfAbsent(sku, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Top SKUs con mayor Rotura',
      columnas: const ['SKU', 'CANTIDAD', 'TOTAL HL', 'REINCIDENCIA', 'VALOR TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.0),
        4: FlexColumnWidth(1.4),
      },
      filas: ordenados.map((e) {
        double val = costos[e.key] ?? 0;
        int rein = reincidencias[e.key]?.length ?? 1;
        double hlSku = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(hlSku.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('\$ ${_formatearMoneda(val)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
        ];
      }).toList(),
    );
  }

  Widget _buildTablaEscenario() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, double> costos = {};
    Map<String, Set<String>> reincidencias = {};

    for (var r in _reportesFiltrados) {
      String esc = r['escenario']?.toString() ?? 'Sin Escenario';
      if (esc.trim().isEmpty || esc.toUpperCase() == 'NULL') esc = 'Sin Escenario';

      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[esc] = (conteo[esc] ?? 0) + cant;
      hlConteo[esc] = (hlConteo[esc] ?? 0) + hlVal;
      costos[esc] = (costos[esc] ?? 0) + costo;
      reincidencias.putIfAbsent(esc, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por Escenario',
      columnas: const ['ESCENARIO', 'CANTIDAD', 'TOTAL HL', 'REINCIDENCIA', 'VALOR TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.0),
        4: FlexColumnWidth(1.4),
      },
      filas: ordenados.map((e) {
        double val = costos[e.key] ?? 0;
        int rein = reincidencias[e.key]?.length ?? 1;
        double hlEsc = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(hlEsc.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('\$ ${_formatearMoneda(val)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
        ];
      }).toList(),
    );
  }

  Widget _buildTablaSupervisor() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, double> costos = {};
    Map<String, Set<String>> reincidencias = {};

    for (var r in _reportesFiltrados) {
      String s = r['supervisor']?.toString() ?? 'SIN SUPERVISOR';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double costo = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[s] = (conteo[s] ?? 0) + cant;
      hlConteo[s] = (hlConteo[s] ?? 0) + hlVal;
      costos[s] = (costos[s] ?? 0) + costo;
      reincidencias.putIfAbsent(s, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por Supervisor',
      columnas: const ['SUPERVISOR', 'CANTIDAD', 'TOTAL HL', 'REINCIDENCIA', 'VALOR TOTAL'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(1.2),
        3: FlexColumnWidth(1.0),
        4: FlexColumnWidth(1.4),
      },
      filas: ordenados.map((e) {
        double val = costos[e.key] ?? 0;
        int rein = reincidencias[e.key]?.length ?? 1;
        double hlSup = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(hlSup.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
          Text('\$ ${_formatearMoneda(val)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
        ];
      }).toList(),
    );
  }

  Widget _buildTablaTurno() {
    Map<String, int> conteo = {};
    Map<String, double> hlConteo = {};
    Map<String, Set<String>> reincidencias = {};

    for (var r in _reportesFiltrados) {
      String t = r['turno']?.toString() ?? 'SIN TURNO';
      int cant = double.tryParse(r['cantidad']?.toString() ?? '1')?.toInt() ?? 1;
      double hlVal = _parseHl(r['hl_total'] ?? r['hl']);

      conteo[t] = (conteo[t] ?? 0) + cant;
      hlConteo[t] = (hlConteo[t] ?? 0) + hlVal;
      reincidencias.putIfAbsent(t, () => {}).add(r['id']?.toString() ?? '');
    }

    var ordenados = conteo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _buildCardTabla(
      titulo: 'Roturas por Turno',
      columnas: const ['TURNO', 'ROTURAS', 'TOTAL HL', 'REINCIDENCIAS'],
      columnWidths: const {
        0: FlexColumnWidth(2.0),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1.2),
      },
      filas: ordenados.map((e) {
        int rein = reincidencias[e.key]?.length ?? 1;
        double hlTur = hlConteo[e.key] ?? 0.0;

        return [
          Text(e.key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          Text('${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
          Text(hlTur.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal)),
          Text('$rein', style: const TextStyle(fontSize: 10)),
        ];
      }).toList(),
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.grey),
        textAlign: TextAlign.left,
      ),
    );
  }

  Widget _dataCell(String text, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? Colors.black87,
          height: 1.3,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

  Widget _buildTablaDetalleCompleto() {
    return _buildCardBase(
      titulo: 'Detalle Completo Roturas',
      actionRight: ElevatedButton.icon(
        onPressed: _descargarExcel,
        icon: const Icon(Icons.download_rounded, size: 14),
        label: const Text('EXCEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: const Size(0, 32),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.5),
              3: FlexColumnWidth(1.0),
              4: FlexColumnWidth(1.2),
              5: FlexColumnWidth(1.2),
              6: FlexColumnWidth(0.8),
              7: FlexColumnWidth(0.9),
              8: FlexColumnWidth(1.6),
              9: FlexColumnWidth(2.8),
              10: FlexColumnWidth(1.2),
              11: FlexColumnWidth(1.2),
              12: FlexColumnWidth(1.2),
              13: FlexColumnWidth(1.5),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(
                    color: Color(0xFFF8F9FA),
                    border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0)))
                ),
                children: [
                  _headerCell('FECHA'),
                  _headerCell('SUPERVISOR'),
                  _headerCell('PERSONAL INVOLUCRADO'),
                  _headerCell('ZONA'),
                  _headerCell('UBICACIÓN'),
                  _headerCell('SKU'),
                  _headerCell('CANTIDAD'),
                  _headerCell('HL TOTAL'),
                  _headerCell('CAUSAL'),
                  _headerCell('OBSERVACIÓN'),
                  _headerCell('CONCILIADOR'),
                  _headerCell('PRECIO BAJA TOTAL'),
                  _headerCell('PRECIO BAJA FULL PRICE'),
                  _headerCell('EVIDENCIAS'),
                ],
              ),
              ..._reportesFiltrados.take(100).map((r) {
                String rawF = r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString() ?? '';
                String fecha = rawF.isNotEmpty ? rawF.split('T')[0].split(' ')[0] : 'N/A';
                String supervisor = r['supervisor']?.toString() ?? 'N/A';
                String personal = r['personal']?.toString() ?? r['reportante']?.toString() ?? 'N/A';
                String zona = r['zona']?.toString() ?? 'N/A';
                String ubicacion = r['ubicacion']?.toString() ?? 'N/A';
                String sku = r['sku']?.toString() ?? 'N/A';
                int cantidad = double.tryParse(r['cantidad']?.toString() ?? '0')?.toInt() ?? 0;
                double hlVal = _parseHl(r['hl_total'] ?? r['hl']);
                String causal = r['causal']?.toString() ?? 'N/A';
                String obs = r['descripcion']?.toString() ?? r['observacion']?.toString() ?? 'Sin observación';
                String conciliador = r['conciliador']?.toString() ?? 'N/A';

                double costoBaja = double.tryParse(r['costo_total_baja']?.toString() ?? '0') ?? 0;
                double costoFull = double.tryParse(r['costo_total_full_price']?.toString() ?? '0') ?? 0;

                String? urlFirma = r['firma_conciliador']?.toString() ?? r['firma']?.toString() ?? r['evidencia_firma']?.toString() ?? r['url_firma']?.toString();
                String? urlEvento = r['evidencia_evento']?.toString();
                String? urlCausante = r['evidencia_causante']?.toString() ?? r['evidencia_condicion']?.toString();

                return TableRow(
                    decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5)))
                    ),
                    children: [
                      _dataCell(fecha),
                      _dataCell(supervisor),
                      _dataCell(personal, isBold: true),
                      _dataCell(zona),
                      _dataCell(ubicacion),
                      _dataCell(sku, isBold: true),
                      _dataCell('$cantidad', isBold: true, color: Colors.red),
                      _dataCell(hlVal.toStringAsFixed(3), isBold: true, color: Colors.teal.shade800),
                      _dataCell(causal),
                      _dataCell(obs),
                      _dataCell(conciliador),
                      _dataCell('\$ ${_formatearMoneda(costoBaja)}', isBold: true, color: Colors.orange.shade800),
                      _dataCell('\$ ${_formatearMoneda(costoFull)}', isBold: true, color: Colors.green),

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 2.0),
                        child: Wrap(
                          spacing: 2,
                          runSpacing: 2,
                          alignment: WrapAlignment.start,
                          children: [
                            _buildAccionButton('Ver Firma', Icons.draw_rounded, urlFirma),
                            _buildAccionButton('Ver Foto Evento', Icons.broken_image_rounded, urlEvento),
                            _buildAccionButton('Ver Foto Causante', Icons.person_search_rounded, urlCausante),
                          ],
                        ),
                      ),
                    ]
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccionButton(String tooltip, IconData icon, String? rawUrl) {
    String urlLimpia = (rawUrl ?? '').trim();
    bool hasUrl = urlLimpia.isNotEmpty && urlLimpia.toLowerCase() != 'null' && urlLimpia != '[NULL]';

    return Container(
      decoration: BoxDecoration(
        color: hasUrl ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hasUrl ? Colors.blue.shade200 : Colors.transparent),
      ),
      child: IconButton(
        icon: Icon(icon, color: hasUrl ? Colors.blue.shade700 : Colors.grey.shade400, size: 14),
        tooltip: tooltip,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        onPressed: hasUrl ? () {
          String linkFinal = urlLimpia;
          if (!linkFinal.startsWith('http') && !linkFinal.contains('Firma_Registrada')) {
            linkFinal = 'https://plantatocancipa.site/uploads/firma_conciliador/$linkFinal';
          }
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
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(30.0),
                        child: Text('La firma o imagen no es un enlace válido o está en formato de texto.', style: TextStyle(color: Colors.red)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardBase({required String titulo, Widget? actionRight, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
              if (actionRight != null) actionRight,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildCardTabla({
    required String titulo,
    required List<String> columnas,
    required List<List<Widget>> filas,
    Map<int, TableColumnWidth>? columnWidths,
  }) {
    return _buildCardBase(
      titulo: titulo,
      child: SizedBox(
        height: 200,
        child: SingleChildScrollView(
          child: Table(
            columnWidths: columnWidths ?? const {
              0: FlexColumnWidth(2.0),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.4),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1.5))),
                children: columnas
                    .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(c, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                )).toList(),
              ),
              ...filas.map((f) => TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5)))),
                children: f
                    .map((w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: w,
                )).toList(),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardTablaAction({required String titulo, required List<String> columnas, required List<List<Widget>> filas}) {
    return _buildCardBase(
      titulo: titulo,
      child: SizedBox(
        height: 220,
        child: SingleChildScrollView(
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(1.1),
              1: FlexColumnWidth(1.4),
              2: FlexColumnWidth(0.8),
              3: FlexColumnWidth(0.9),
              4: FlexColumnWidth(1.7),
              5: FlexColumnWidth(0.9),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1.5))),
                children: columnas.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(c, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                )).toList(),
              ),
              ...filas.map((f) => TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5)))),
                children: f.map((w) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: w,
                )).toList(),
              )),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearMoneda(double valor) {
    return valor.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }

  Widget _buildBannerError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_mensajeError!, style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.bold))),
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

class EvolucionDiariaChart extends StatelessWidget {
  final List<Map<String, dynamic>> reportes;
  final DateTime fechaDesde;
  final DateTime fechaHasta;

  const EvolucionDiariaChart({
    super.key,
    required this.reportes,
    required this.fechaDesde,
    required this.fechaHasta,
  });

  @override
  Widget build(BuildContext context) {
    Map<int, double> conteoDias = {};

    for (var r in reportes) {
      String? rawFecha = r['fecha_evento']?.toString() ?? r['timestamp_registro']?.toString();
      if (rawFecha != null && rawFecha.isNotEmpty) {
        String soloFecha = rawFecha.split('T')[0].split(' ')[0];
        DateTime? dt = DateTime.tryParse(soloFecha);
        if (dt != null) {
          double cant = double.tryParse(r['cantidad']?.toString() ?? '1') ?? 1;
          conteoDias[dt.day] = (conteoDias[dt.day] ?? 0) + cant;
        }
      }
    }

    List<int> dias = [];
    List<double> valores = [];

    int totalDias = fechaHasta.difference(fechaDesde).inDays + 1;
    if (totalDias < 1) totalDias = 30;

    for (int i = 0; i < min(totalDias, 31); i++) {
      DateTime curr = fechaDesde.add(Duration(days: i));
      dias.add(curr.day);
      valores.add(conteoDias[curr.day] ?? 0);
    }

    if (valores.isEmpty) {
      return const Center(child: Text('Sin datos en el rango seleccionado', style: TextStyle(fontSize: 11, color: Colors.grey)));
    }

    return CustomPaint(
      painter: _SmoothLineChartPainter(dias: dias, valores: valores),
      child: Container(),
    );
  }
}

class _SmoothLineChartPainter extends CustomPainter {
  final List<int> dias;
  final List<double> valores;

  _SmoothLineChartPainter({required this.dias, required this.valores});

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.isEmpty) return;

    double maxVal = valores.reduce(max);
    if (maxVal == 0) maxVal = 100;

    double paddingLeft = 30;
    double paddingBottom = 20;
    double width = size.width - paddingLeft;
    double height = size.height - paddingBottom;

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 0.8;

    for (int i = 0; i <= 4; i++) {
      double y = height - (i * (height / 4));
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width, y), gridPaint);

      TextPainter tp = TextPainter(
        text: TextSpan(text: '${(maxVal / 4 * i).toInt()}', style: TextStyle(fontSize: 8, color: Colors.grey.shade500)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(5, y - 5));
    }

    double stepX = width / (valores.length > 1 ? valores.length - 1 : 1);

    List<Offset> points = [];
    for (int i = 0; i < valores.length; i++) {
      double x = paddingLeft + (i * stepX);
      double y = height - ((valores[i] / maxVal) * (height - 20));
      points.add(Offset(x, y));

      TextPainter tp = TextPainter(
        text: TextSpan(text: dias[i].toString().padLeft(2, '0'), style: TextStyle(fontSize: 8, color: Colors.grey.shade600)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - 5, height + 4));
    }

    Path path = Path();
    Path fillPath = Path();

    path.moveTo(points[0].dx, points[0].dy);
    fillPath.moveTo(points[0].dx, height);
    fillPath.lineTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      double p0x = points[i].dx;
      double p0y = points[i].dy;
      double p1x = points[i + 1].dx;
      double p1y = points[i + 1].dy;

      double controlX1 = p0x + (p1x - p0x) / 2;
      double controlY1 = p0y;
      double controlX2 = p0x + (p1x - p0x) / 2;
      double controlY2 = p1y;

      path.cubicTo(controlX1, controlY1, controlX2, controlY2, p1x, p1y);
      fillPath.cubicTo(controlX1, controlY1, controlX2, controlY2, p1x, p1y);
    }

    fillPath.lineTo(points.last.dx, height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFF36F21).withOpacity(0.25), const Color(0xFFF36F21).withOpacity(0.01)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFFF36F21)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFFF36F21);
    final dotBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < points.length; i++) {
      if (valores[i] > 0) {
        canvas.drawCircle(points[i], 4, dotPaint);
        canvas.drawCircle(points[i], 4, dotBorder);

        TextPainter tp = TextPainter(
          text: TextSpan(text: '${valores[i].toInt()}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFD84315))),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(points[i].dx - (tp.width / 2), points[i].dy - 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DonutChartWidget extends StatelessWidget {
  final Map<String, double> datos;
  final List<Color> colores;

  const DonutChartWidget({super.key, required this.datos, required this.colores});

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) {
      return const Center(child: Text('Sin datos', style: TextStyle(fontSize: 10, color: Colors.grey)));
    }

    double total = datos.values.fold(0, (s, item) => s + item);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: CustomPaint(
            painter: _DonutPainter(datos: datos, colores: colores, total: total),
            child: Container(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: datos.keys.toList().asMap().entries.map((entry) {
              int idx = entry.key;
              String label = entry.value;
              Color color = colores[idx % colores.length];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.rectangle, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
    double radius = min(size.width, size.height) / 2 - 8;

    final paintArc = Paint()..style = PaintingStyle.fill;

    int idx = 0;
    datos.forEach((key, val) {
      if (val > 0) {
        double sweepAngle = (val / total) * 2 * pi;
        paintArc.color = colores[idx % colores.length];

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          true,
          paintArc,
        );

        double middleAngle = startAngle + (sweepAngle / 2);
        double textX = center.dx + (radius * 0.65) * cos(middleAngle);
        double textY = center.dy + (radius * 0.65) * sin(middleAngle);

        double pct = (val / total) * 100;
        if (pct >= 4) {
          TextPainter tp = TextPainter(
            text: TextSpan(text: '${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
            textDirection: TextDirection.ltr,
          );
          tp.layout();
          tp.paint(canvas, Offset(textX - (tp.width / 2), textY - (tp.height / 2)));
        }

        startAngle += sweepAngle;
      }
      idx++;
    });

    final centerCircle = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.5, centerCircle);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}