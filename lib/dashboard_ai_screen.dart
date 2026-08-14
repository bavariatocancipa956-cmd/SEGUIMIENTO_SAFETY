import 'dart:convert';
import 'dart:math';
import 'dart:async'; // 👈 Necesario para el Timer del Modo TV
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'api_service.dart';

class DashboardAiScreen extends StatefulWidget {
  final Map<String, dynamic>? datosEmpleado;
  final VoidCallback? onToggleSidebar;

  const DashboardAiScreen({
    super.key,
    this.datosEmpleado,
    this.onToggleSidebar,
  });

  @override
  State<DashboardAiScreen> createState() => _DashboardAiScreenState();
}

class _DashboardAiScreenState extends State<DashboardAiScreen> {
  bool _isLoading = true;

  List<Map<String, dynamic>> _rawRegistros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  // Filtros
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _turnoFiltro = 'Todos';
  String _supervisorFiltro = 'Todos';
  String _operarioFiltro = 'Todos';
  String _origenFiltro = 'Todos'; // 👈 NUEVO
  String _placaFiltro = 'Todos';  // 👈 NUEVO

  List<String> _listaTurnos = ['Todos'];
  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaOperarios = ['Todos'];
  List<String> _listaOrigenes = ['Todos']; // 👈 NUEVO
  List<String> _listaPlacas = ['Todos'];   // 👈 NUEVO

  // Estado Modo TV
  bool _isTvMode = false;
  Timer? _tvTimer;

  // KPIs Generales
  int _totalUnidadesRev = 0;
  double _totalEstibasRev = 0.0;
  int _totalAverias = 0;
  double _promedioProductividad = 0.0;
  double _promedioPorcentajeAi = 0.0;

  // Agrupaciones para tablas y gráficos
  Map<String, double> _productividadPorDia = {};
  Map<String, double> _porcentajeAiPorDia = {};
  Map<String, double> _productividadPorMes = {};
  Map<String, double> _productividadPorOperario = {};
  Map<String, Map<String, dynamic>> _resumenTurno = {};
  Map<String, Map<String, dynamic>> _resumenOperario = {};
  Map<String, Map<String, dynamic>> _resumenOrigen = {};
  Map<String, double> _distribucionAverias = {};

  // Variables auxiliares para los defectos
  int _sumOtrasCompanias = 0;
  int _sumRotas = 0;
  int _sumMalClasificadas = 0;
  int _sumCuerposExtranos = 0;
  int _sumExtraSucias = 0;
  int _sumScoofing = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fechaDesde = DateTime(now.year, now.month, 1);
    _fechaHasta = now;
    _cargarDatos();
  }

  @override
  void dispose() {
    _tvTimer?.cancel(); // 👈 IMPORTANTE: Limpiar el timer si se sale de la pantalla
    super.dispose();
  }

  // 🛠️ Formateadores
  String _fmtInt(num valor) {
    String str = valor.toString();
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
  }

  String _fmtFecha(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _obtenerNombreMes(String key) {
    try {
      final partes = key.split('-');
      if (partes.length == 2) {
        int anio = int.parse(partes[0]);
        int mes = int.parse(partes[1]);
        const meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
        if (mes >= 1 && mes <= 12) return '${meses[mes]} $anio';
      }
    } catch (_) {}
    return key;
  }

  int _pInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;
  double _pDouble(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;

  Future<void> _cargarDatos() async {
    if (!_isTvMode) setState(() => _isLoading = true);
    try {
      final items = await ApiService.consultarTabla(
        esquema: 'revision_ai',
        tabla: 'productividad_ai',
      );

      _rawRegistros = List<Map<String, dynamic>>.from(items);

      final setTurnos = <String>{'Todos'};
      final setSupervisores = <String>{'Todos'};
      final setOperarios = <String>{'Todos'};
      final setOrigenes = <String>{'Todos'};
      final setPlacas = <String>{'Todos'};

      for (var r in _rawRegistros) {
        final t = (r['turno'] ?? '').toString().trim();
        final s = (r['supervisor'] ?? '').toString().trim();
        final o = (r['operario'] ?? '').toString().trim();
        final ori = (r['origen_cd'] ?? '').toString().trim();
        final pla = (r['vh_placa'] ?? '').toString().trim().toUpperCase();

        if (t.isNotEmpty) setTurnos.add(t);
        if (s.isNotEmpty) setSupervisores.add(s);
        if (o.isNotEmpty) setOperarios.add(o);
        if (ori.isNotEmpty) setOrigenes.add(ori);
        if (pla.isNotEmpty) setPlacas.add(pla);
      }

      _listaTurnos = setTurnos.toList()..sort();
      _listaSupervisores = setSupervisores.toList()..sort();
      _listaOperarios = setOperarios.toList()..sort();
      _listaOrigenes = setOrigenes.toList()..sort();
      _listaPlacas = setPlacas.toList()..sort();

      _aplicarFiltrosYCalculos();
    } catch (e) {
      debugPrint('Error cargando dashboard AI: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _aplicarFiltrosYCalculos() {
    _registrosFiltrados = _rawRegistros.where((r) {
      final fechaStr = (r['fecha_reporte'] ?? '').toString();
      if (fechaStr.length >= 10) {
        final DateTime? f = DateTime.tryParse(fechaStr.substring(0, 10));
        if (f != null) {
          if (_fechaDesde != null && f.isBefore(_fechaDesde!)) return false;
          if (_fechaHasta != null && f.isAfter(_fechaHasta!.add(const Duration(days: 1)))) return false;
        }
      }

      final t = (r['turno'] ?? '').toString().trim();
      if (_turnoFiltro != 'Todos' && t != _turnoFiltro) return false;

      final s = (r['supervisor'] ?? '').toString().trim();
      if (_supervisorFiltro != 'Todos' && s != _supervisorFiltro) return false;

      final o = (r['operario'] ?? '').toString().trim();
      if (_operarioFiltro != 'Todos' && o != _operarioFiltro) return false;

      final ori = (r['origen_cd'] ?? '').toString().trim();
      if (_origenFiltro != 'Todos' && ori != _origenFiltro) return false;

      final pla = (r['vh_placa'] ?? '').toString().trim().toUpperCase();
      if (_placaFiltro != 'Todos' && pla != _placaFiltro) return false;

      return true;
    }).toList();

    _totalUnidadesRev = 0;
    _totalAverias = 0;
    _totalEstibasRev = 0.0;
    _sumOtrasCompanias = 0;
    _sumRotas = 0;
    _sumMalClasificadas = 0;
    _sumCuerposExtranos = 0;
    _sumExtraSucias = 0;
    _sumScoofing = 0;

    _productividadPorDia.clear();
    _porcentajeAiPorDia.clear();
    _productividadPorMes.clear();
    _productividadPorOperario.clear();
    _resumenTurno.clear();
    _resumenOperario.clear();
    _resumenOrigen.clear();
    _distribucionAverias.clear();

    Map<String, List<double>> prodDiaMap = {};
    Map<String, List<double>> aiDiaMap = {};
    Map<String, List<double>> prodMesMap = {};

    double sumProdGlobal = 0.0, sumAiGlobal = 0.0;
    int contProdGlobal = 0, contAiGlobal = 0;

    for (var r in _registrosFiltrados) {
      final unidades = _pInt(r['cajas']);
      final averias = _pInt(r['unidades_mal_estado']);

      final prod = _pDouble(r['productividad']) * 100;
      final ai = _pDouble(r['%ai']);

      final turno = (r['turno'] ?? 'N/A').toString().trim();
      final operario = (r['operario'] ?? 'N/A').toString().trim();
      final origen = (r['origen_cd'] ?? 'N/A').toString().trim();
      String fechaStr = (r['fecha_reporte'] ?? '').toString();

      _totalUnidadesRev += unidades;
      _totalAverias += averias;

      _sumOtrasCompanias += _pInt(r['unidades_otras_companias']);
      _sumRotas += _pInt(r['unidades_rotas_botellas']);
      _sumMalClasificadas += _pInt(r['unidades_mal_clasificadas_botellas']);
      _sumCuerposExtranos += _pInt(r['unidades_con_cuerpos_extranos_botellas'] ?? r['unidades_con_cuerpos_extranos_bote']);
      _sumExtraSucias += _pInt(r['unidades_con_extrasucio_botellas']);
      _sumScoofing += _pInt(r['unidades_con_scoofing_botellas']);

      if (prod > 0) {
        sumProdGlobal += prod;
        contProdGlobal++;
      }
      if (ai > 0) {
        sumAiGlobal += ai;
        contAiGlobal++;
      }

      if (fechaStr.length >= 10) {
        final diaLabel = fechaStr.substring(8, 10);
        final mesKey = fechaStr.substring(0, 7);

        if (prod > 0) prodDiaMap.putIfAbsent(diaLabel, () => <double>[]).add(prod);
        if (ai > 0) aiDiaMap.putIfAbsent(diaLabel, () => <double>[]).add(ai);
        if (prod > 0) prodMesMap.putIfAbsent(mesKey, () => <double>[]).add(prod);
      }

      // Turnos
      if (!_resumenTurno.containsKey(turno)) {
        _resumenTurno[turno] = {'unidades': 0, 'averias': 0, 'prodList': <double>[], 'aiList': <double>[]};
      }
      _resumenTurno[turno]!['unidades'] += unidades;
      _resumenTurno[turno]!['averias'] += averias;
      if (prod > 0) (_resumenTurno[turno]!['prodList'] as List<double>).add(prod);
      if (ai > 0) (_resumenTurno[turno]!['aiList'] as List<double>).add(ai);

      // Operarios
      if (!_resumenOperario.containsKey(operario)) {
        _resumenOperario[operario] = {'unidades': 0, 'averias': 0, 'prodList': <double>[]};
      }
      _resumenOperario[operario]!['unidades'] += unidades;
      _resumenOperario[operario]!['averias'] += averias;
      if (prod > 0) (_resumenOperario[operario]!['prodList'] as List<double>).add(prod);

      // Agrupación por Origen
      if (!_resumenOrigen.containsKey(origen)) {
        _resumenOrigen[origen] = {'unidades': 0, 'averias': 0};
      }
      _resumenOrigen[origen]!['unidades'] += unidades;
      _resumenOrigen[origen]!['averias'] += averias;
    }

    _totalEstibasRev = _totalUnidadesRev > 0 ? (_totalUnidadesRev / 30) / 45 : 0.0;

    _promedioProductividad = contProdGlobal > 0 ? sumProdGlobal / contProdGlobal : 0.0;
    _promedioPorcentajeAi = contAiGlobal > 0 ? sumAiGlobal / contAiGlobal : 0.0;

    prodDiaMap.forEach((k, list) => _productividadPorDia[k] = list.fold<double>(0.0, (a, b) => a + b) / list.length);
    aiDiaMap.forEach((k, list) => _porcentajeAiPorDia[k] = list.fold<double>(0.0, (a, b) => a + b) / list.length);
    prodMesMap.forEach((k, list) => _productividadPorMes[k] = list.fold<double>(0.0, (a, b) => a + b) / list.length);

    _resumenOperario.forEach((k, v) {
      List<double> pList = v['prodList'];
      if (pList.isNotEmpty) {
        _productividadPorOperario[k] = pList.fold<double>(0.0, (a, b) => a + b) / pList.length;
      }
    });

    if (_sumOtrasCompanias > 0) _distribucionAverias['Otras Compañías'] = _sumOtrasCompanias.toDouble();
    if (_sumRotas > 0) _distribucionAverias['Rotas'] = _sumRotas.toDouble();
    if (_sumMalClasificadas > 0) _distribucionAverias['Mal Clasificadas'] = _sumMalClasificadas.toDouble();
    if (_sumCuerposExtranos > 0) _distribucionAverias['Cuerpos Extraños'] = _sumCuerposExtranos.toDouble();
    if (_sumExtraSucias > 0) _distribucionAverias['Extra Sucias'] = _sumExtraSucias.toDouble();
    if (_sumScoofing > 0) _distribucionAverias['Scoofing'] = _sumScoofing.toDouble();
  }

  Future<void> _seleccionarFecha(bool esDesde) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: esDesde ? (_fechaDesde ?? DateTime.now()) : (_fechaHasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (esDesde) _fechaDesde = picked;
        else _fechaHasta = picked;
        _aplicarFiltrosYCalculos();
      });
    }
  }

  // 👈 FUNCIÓN PARA DESCARGAR EL REPORTE EN CSV / EXCEL
  void _descargarReporteExcel() {
    if (_registrosFiltrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar'), backgroundColor: Colors.orange),
      );
      return;
    }

    String csvData = "FECHA,TURNO,SUPERVISOR,OPERARIO,ORIGEN,PLACA,SKU,UNIDADES REVISADAS,ESTIBAS REVISADAS,AVERIAS,% AI (Averías),PRODUCTIVIDAD\n";

    for (var r in _registrosFiltrados) {
      final fechaStr = (r['fecha_reporte'] ?? '').toString().split('T')[0];
      final turno = (r['turno'] ?? '').toString();
      final supervisor = (r['supervisor'] ?? '').toString();
      final operario = (r['operario'] ?? '').toString();
      final origen = (r['origen_cd'] ?? '').toString();
      final placa = (r['vh_placa'] ?? '').toString();
      final sku = (r['sku'] ?? '').toString();

      final int uni = _pInt(r['cajas']);
      final double estibasCalc = uni > 0 ? (uni / 30) / 45 : 0.0;
      final int averias = _pInt(r['unidades_mal_estado']);
      final double ai = _pDouble(r['%ai']);
      final double prod = _pDouble(r['productividad']) * 100;

      csvData += '"$fechaStr","$turno","$supervisor","$operario","$origen","$placa","$sku","$uni","${estibasCalc.toStringAsFixed(2)}","$averias","${ai.toStringAsFixed(2)}%","${prod.toStringAsFixed(2)}%"\n';
    }

    final bytes = utf8.encode(csvData);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.document.createElement('a') as html.AnchorElement
      ..href = url
      ..style.display = 'none'
      ..download = 'Reporte_Productividad_AI_${DateTime.now().millisecondsSinceEpoch}.csv';

    html.document.body!.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  // 👈 FUNCIÓN PARA EL MODO TV
  void _toggleTvMode() {
    setState(() {
      _isTvMode = !_isTvMode;
      if (_isTvMode) {
        _tvTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
          _cargarDatos();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📺 Modo TV Activado: Refresco en vivo cada 15s.'), backgroundColor: Colors.green),
        );
      } else {
        _tvTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modo TV Desactivado'), backgroundColor: Colors.orange),
        );
      }
    });
  }

  // 👈 FUNCIÓN PARA MOSTRAR GALERÍA DE FOTOS EVIDENCIA
  void _mostrarGaleriaFotos() {
    // Buscar registros filtrados que sí tengan foto
    final fotos = _registrosFiltrados
        .where((r) => r['foto_evidencia'] != null && r['foto_evidencia'].toString().trim().isNotEmpty)
        .map((r) => r['foto_evidencia'].toString())
        .toList();

    if (fotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay fotos de evidencia en los registros filtrados.'), backgroundColor: Colors.orange),
      );
      return;
    }

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('📸 Evidencias Fotográficas (${fotos.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          content: SizedBox(
            width: 800,
            height: 500,
            child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.0,
                ),
                itemCount: fotos.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () {
                      // Abrir foto en grande
                      showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: InteractiveViewer(child: Image.network(fotos[index], fit: BoxFit.contain)),
                          )
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        fotos[index],
                        fit: BoxFit.cover,
                        errorBuilder: (_,__,___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                      ),
                    ),
                  );
                }
            ),
          ),
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBarraFiltrosWeb(),
            const SizedBox(height: 16),
            _buildTarjetasKPIWeb(),
            const SizedBox(height: 16),
            _buildFilaGraficosPrincipales(),
            const SizedBox(height: 16),
            _buildFilaTablasAgrupadas(),
            const SizedBox(height: 16),
            _buildFilaTablaDefectosYGraficos(),
            const SizedBox(height: 16),
            _buildTablaHistorialCompleto(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraFiltrosWeb() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildFiltroFecha('DESDE', _fechaDesde, () => _seleccionarFecha(true)),
          _buildFiltroFecha('HASTA', _fechaHasta, () => _seleccionarFecha(false)),
          _buildSelectorDropdown('TURNO', _turnoFiltro, _listaTurnos, (v) => setState(() { _turnoFiltro = v!; _aplicarFiltrosYCalculos(); })),
          _buildSelectorDropdown('SUPERVISOR', _supervisorFiltro, _listaSupervisores, (v) => setState(() { _supervisorFiltro = v!; _aplicarFiltrosYCalculos(); })),
          _buildSelectorDropdown('OPERARIO', _operarioFiltro, _listaOperarios, (v) => setState(() { _operarioFiltro = v!; _aplicarFiltrosYCalculos(); })),
          _buildSelectorDropdown('ORIGEN', _origenFiltro, _listaOrigenes, (v) => setState(() { _origenFiltro = v!; _aplicarFiltrosYCalculos(); })), // 👈 NUEVO FILTRO
          _buildSelectorDropdown('PLACA', _placaFiltro, _listaPlacas, (v) => setState(() { _placaFiltro = v!; _aplicarFiltrosYCalculos(); })), // 👈 NUEVO FILTRO

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.filter_list_rounded, size: 16),
            label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => setState(() => _aplicarFiltrosYCalculos()),
          ),

          // 👈 BOTÓN FOTO
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.photo_library_rounded, size: 16),
            label: const Text('FOTOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: _mostrarGaleriaFotos,
          ),

          // 👈 BOTÓN MODO TV
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTvMode ? Colors.red.shade600 : const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(_isTvMode ? Icons.stop_circle_rounded : Icons.tv_rounded, size: 16),
            label: Text(_isTvMode ? 'SALIR TV' : 'TV', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: _toggleTvMode,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroFecha(String label, DateTime? fecha, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(8), color: Colors.white),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fecha != null ? _fmtFecha(fecha) : 'Seleccionar',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorDropdown(String label, String valor, List<String> opciones, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        Container(
          width: 140, // 👈 Limitamos el ancho para que quepan todos los filtros
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(8), color: Colors.white),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: opciones.contains(valor) ? valor : opciones.first,
              isExpanded: true,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              items: opciones.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetasKPIWeb() {
    return LayoutBuilder(builder: (context, constraints) {
      double w = (constraints.maxWidth - 40) / 5;
      if (w < 140) w = (constraints.maxWidth - 10) / 2;

      final Color colorProd = _promedioProductividad >= 100.0 ? const Color(0xFF00C853) : const Color(0xFFE53935);

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildKPICardWeb('ESTIBAS REVISADAS', _totalEstibasRev.toStringAsFixed(2), const Color(0xFF8B5CF6), Icons.layers_outlined, w),
          _buildKPICardWeb('UNIDADES REVISADAS', _fmtInt(_totalUnidadesRev), const Color(0xFF1E88E5), Icons.inventory_2_outlined, w),
          _buildKPICardWeb('UNIDADES MAL ESTADO', _fmtInt(_totalAverias), const Color(0xFFE53935), Icons.broken_image_outlined, w),
          _buildKPICardWeb('PROMEDIO % AI', '${_promedioPorcentajeAi.toStringAsFixed(2)}%', const Color(0xFFD81B60), Icons.warning_amber_rounded, w),
          _buildKPICardWeb('PROM. PRODUCTIVIDAD', '${_promedioProductividad.toStringAsFixed(2)}%', colorProd, Icons.speed_outlined, w),
        ],
      );
    });
  }

  Widget _buildKPICardWeb(String titulo, String valor, Color color, IconData icono, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF718096)), overflow: TextOverflow.ellipsis)),
              Icon(icono, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 10),
          Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildFilaGraficosPrincipales() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 1000;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCardGraficoLinea('Productividad Diaria (%)', _productividadPorDia, const Color(0xFF00C853))),
          const SizedBox(width: 16),
          Expanded(child: _buildCardGraficoLinea('Evolución % AI Averías (%)', _porcentajeAiPorDia, const Color(0xFFD81B60))),
          const SizedBox(width: 16),
          Expanded(child: _buildCardGraficoBarrasMes('Productividad Promedio x Mes', _productividadPorMes)),
        ],
      )
          : Column(
        children: [
          _buildCardGraficoLinea('Productividad Diaria (%)', _productividadPorDia, const Color(0xFF00C853)),
          const SizedBox(height: 16),
          _buildCardGraficoLinea('Evolución % AI Averías (%)', _porcentajeAiPorDia, const Color(0xFFD81B60)),
          const SizedBox(height: 16),
          _buildCardGraficoBarrasMes('Productividad Promedio x Mes', _productividadPorMes),
        ],
      );
    });
  }

  Widget _buildCardGraficoLinea(String titulo, Map<String, double> datos, Color colorLinea) {
    final keys = datos.keys.toList()..sort();
    final values = keys.map((k) => datos[k]!).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        children: [
          Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: datos.isEmpty
                ? const Center(child: Text('Sin datos', style: TextStyle(color: Colors.grey, fontSize: 11)))
                : CustomPaint(
              size: const Size(double.infinity, 200),
              painter: LineChartPainter(keys: keys, values: values, color: colorLinea),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGraficoBarrasMes(String titulo, Map<String, double> datos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        children: [
          Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: datos.isEmpty
                ? const Center(child: Text('Sin datos', style: TextStyle(color: Colors.grey, fontSize: 11)))
                : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: datos.entries.map((e) {
                final val = e.value;
                final col = val >= 100.0 ? const Color(0xFF00C853) : const Color(0xFFE53935);
                final alturaBarra = (val / (val > 150 ? val * 1.2 : 150.0)) * 150.0;
                final nombreMes = _obtenerNombreMes(e.key);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${val.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: col)),
                    const SizedBox(height: 6),
                    Container(
                      width: 60,
                      height: min(150, max(15, alturaBarra)),
                      decoration: BoxDecoration(color: col, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                    ),
                    const SizedBox(height: 10),
                    Text(nombreMes, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilaTablasAgrupadas() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 1100;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _buildTablaEstandar('Resumen por Turno', _buildCuerpoTablaTurno())),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: _buildTablaEstandar('Rendimiento Operario', _buildCuerpoTablaOperario())),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: _buildTablaEstandar('Resumen por Origen', _buildCuerpoTablaOrigen())),
        ],
      )
          : Column(
        children: [
          _buildTablaEstandar('Resumen por Turno', _buildCuerpoTablaTurno()),
          const SizedBox(height: 16),
          _buildTablaEstandar('Rendimiento Operario', _buildCuerpoTablaOperario()),
          const SizedBox(height: 16),
          _buildTablaEstandar('Resumen por Origen', _buildCuerpoTablaOrigen()),
        ],
      );
    });
  }

  Widget _buildFilaTablaDefectosYGraficos() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 900;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: _buildTablaEstandar('Detalle de Defectos (% Sobre Averías)', _buildCuerpoTablaDetalleDefectos(), height: 340)),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: _buildCardAnilloCalidad(height: 340)),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: _buildCardAnilloDefectos(height: 340)),
        ],
      )
          : Column(
        children: [
          _buildTablaEstandar('Detalle de Defectos (% Sobre Averías)', _buildCuerpoTablaDetalleDefectos(), height: 340),
          const SizedBox(height: 16),
          _buildCardAnilloCalidad(height: 340),
          const SizedBox(height: 16),
          _buildCardAnilloDefectos(height: 340),
        ],
      );
    });
  }

  Widget _buildTablaEstandar(String titulo, Widget tabla, {double height = 340}) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(child: SizedBox(width: double.infinity, child: tabla)),
          ),
        ],
      ),
    );
  }

  Widget _buildCuerpoTablaTurno() {
    var ordenados = _resumenTurno.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return DataTable(
      columnSpacing: 10,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      columns: const [
        DataColumn(label: Text('TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('UNIDADES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('AVERÍAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('% AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
      ],
      rows: ordenados.map((e) {
        final listA = e.value['aiList'] as List<double>;
        final avgA = listA.isEmpty ? 0.0 : (listA.fold<double>(0.0, (a, b) => a + b) / listA.length);

        return DataRow(cells: [
          DataCell(Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
            child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF3730A3))),
          )),
          DataCell(Text(_fmtInt(e.value['unidades']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          DataCell(Text(_fmtInt(e.value['averias']), style: const TextStyle(fontSize: 11, color: Color(0xFFE53935)))),
          DataCell(Text('${avgA.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)))),
        ]);
      }).toList(),
    );
  }

  Widget _buildCuerpoTablaOperario() {
    var ordenados = _resumenOperario.entries.toList()..sort((a, b) {
      final listA = a.value['prodList'] as List<double>;
      final listB = b.value['prodList'] as List<double>;
      final avgA = listA.isEmpty ? 0.0 : (listA.fold<double>(0.0, (x, y) => x + y) / listA.length);
      final avgB = listB.isEmpty ? 0.0 : (listB.fold<double>(0.0, (x, y) => x + y) / listB.length);
      return avgB.compareTo(avgA);
    });

    return DataTable(
      columnSpacing: 10,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      columns: const [
        DataColumn(label: Text('OPERARIO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('UNIDADES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('ESTIBAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('PROD.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
      ],
      rows: ordenados.take(15).map((e) {
        final listP = e.value['prodList'] as List<double>;
        final avgP = listP.isEmpty ? 0.0 : (listP.fold<double>(0.0, (x, y) => x + y) / listP.length);
        final double estibasCalculadas = (e.value['unidades'] / 30) / 45;

        return DataRow(cells: [
          DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
          DataCell(Text(_fmtInt(e.value['unidades']), style: const TextStyle(fontSize: 11))),
          DataCell(Text(estibasCalculadas.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold))),
          DataCell(Text('${avgP.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: avgP >= 100 ? const Color(0xFF00C853) : const Color(0xFFE53935)))),
        ]);
      }).toList(),
    );
  }

  Widget _buildCuerpoTablaOrigen() {
    var ordenados = _resumenOrigen.entries.toList()..sort((a, b) {
      return (b.value['unidades'] as int).compareTo(a.value['unidades'] as int);
    });

    return DataTable(
      columnSpacing: 10,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      columns: const [
        DataColumn(label: Text('ORIGEN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('REVISADAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('MAL ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('% AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
      ],
      rows: ordenados.take(15).map((e) {
        int unid = e.value['unidades'];
        int aver = e.value['averias'];
        double pct = unid > 0 ? (aver / unid) * 100 : 0.0;

        return DataRow(cells: [
          DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 1)),
          DataCell(Text(_fmtInt(unid), style: const TextStyle(fontSize: 11))),
          DataCell(Text(_fmtInt(aver), style: const TextStyle(fontSize: 11, color: Color(0xFFE53935)))),
          DataCell(Text('${pct.toStringAsFixed(2)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)))),
        ]);
      }).toList(),
    );
  }

  Widget _buildCuerpoTablaDetalleDefectos() {
    List<Map<String, dynamic>> defectos = [
      {'nombre': 'Otras Compañías', 'total': _sumOtrasCompanias},
      {'nombre': 'Rotas', 'total': _sumRotas},
      {'nombre': 'Mal Clasificadas', 'total': _sumMalClasificadas},
      {'nombre': 'Cuerpos Extraños', 'total': _sumCuerposExtranos},
      {'nombre': 'Extra Sucias', 'total': _sumExtraSucias},
      {'nombre': 'Scoofing', 'total': _sumScoofing},
    ];

    defectos.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    int totalDefectosDetectados = defectos.fold(0, (sum, item) => sum + (item['total'] as int));

    List<DataRow> filas = defectos.map((d) {
      int totalDefecto = d['total'];
      double pctGeneral = totalDefectosDetectados > 0 ? (totalDefecto / totalDefectosDetectados) * 100 : 0.0;

      return DataRow(cells: [
        DataCell(Text(d['nombre'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF1E293B)))),
        DataCell(Text(_fmtInt(totalDefecto), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        DataCell(Text('${pctGeneral.toStringAsFixed(2)}%', style: const TextStyle(fontSize: 11, color: Color(0xFFE53935), fontWeight: FontWeight.bold))),
      ]);
    }).toList();

    filas.add(
        DataRow(
            color: WidgetStateProperty.all(const Color(0xFFFFEBEE)),
            cells: [
              const DataCell(Text('TOTAL AVERÍAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFE53935)))),
              DataCell(Text(_fmtInt(totalDefectosDetectados), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE53935)))),
              const DataCell(Text('100.00%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE53935)))),
            ]
        )
    );

    return DataTable(
      columnSpacing: 10,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFFFF5F5)),
      columns: const [
        DataColumn(label: Text('DEFECTO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFFE53935)))),
        DataColumn(label: Text('TOTAL UNID.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFFE53935)))),
        DataColumn(label: Text('% SOBRE AVERÍAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFFE53935)))),
      ],
      rows: filas,
    );
  }

  Widget _buildCardAnilloCalidad({double height = 340}) {
    int unidadesBuenas = _totalUnidadesRev - _totalAverias;
    if (unidadesBuenas < 0) unidadesBuenas = 0;

    final double pctBuenas = _totalUnidadesRev > 0 ? (unidadesBuenas / _totalUnidadesRev) * 100 : 0.0;
    final double pctDefectos = _totalUnidadesRev > 0 ? (_totalAverias / _totalUnidadesRev) * 100 : 0.0;

    return Container(
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        children: [
          const Text('Distribución General de Calidad', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(180, 180),
                  painter: DonutChartPainter(
                    secciones: [
                      DonutSegment(porcentaje: pctBuenas, color: const Color(0xFF00C853)),
                      DonutSegment(porcentaje: pctDefectos, color: const Color(0xFFE53935)),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${pctDefectos.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFE53935))),
                    const Text('Averías', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLeyendaAnillo('Buen Estado', const Color(0xFF00C853)),
              const SizedBox(width: 30),
              _buildLeyendaAnillo('Averías', const Color(0xFFE53935)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardAnilloDefectos({double height = 340}) {
    final colores = [const Color(0xFFD81B60), const Color(0xFFF59E0B), const Color(0xFF3B82F6), const Color(0xFF8B5CF6), const Color(0xFF10B981), const Color(0xFF00BCD4)];

    return Container(
      height: height,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        children: [
          const Text('Averías (Distribución Interna)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          Expanded(
            child: DonutChartWidget(datos: _distribucionAverias, colores: colores),
          ),
        ],
      ),
    );
  }

  Widget _buildLeyendaAnillo(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
      ],
    );
  }

  Widget _buildTablaHistorialCompleto() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Historial Completo (Detalle AI)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              ElevatedButton.icon(
                onPressed: _descargarReporteExcel,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Descargar CSV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 400,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: _registrosFiltrados.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No hay registros en este rango', style: TextStyle(color: Colors.grey))))
                  : Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.0), // FECHA
                  1: FlexColumnWidth(0.6), // TURNO
                  2: FlexColumnWidth(1.2), // SUPERVISOR
                  3: FlexColumnWidth(1.2), // OPERARIO
                  4: FlexColumnWidth(1.2), // ORIGEN
                  5: FlexColumnWidth(1.5), // SKU
                  6: FlexColumnWidth(0.8), // UNIDADES
                  7: FlexColumnWidth(0.8), // ESTIBAS
                  8: FlexColumnWidth(0.8), // AVERIAS
                  9: FlexColumnWidth(0.8), // % AI
                  10: FlexColumnWidth(0.9), // PRODUCTIVIDAD
                },
                border: TableBorder(
                  horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF8FAFC)),
                    children: [
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('FECHA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('SUPERVISOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('OPERARIO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('ORIGEN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('SKU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('UNIDADES', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('ESTIBAS', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('AVERÍAS', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('% AI', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('PRODUCT.', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Color(0xFF64748B)))),
                    ],
                  ),
                  ..._registrosFiltrados.take(150).map((r) {
                    final fechaStr = (r['fecha_reporte'] ?? '').toString().split('T')[0];
                    final origen = (r['origen_cd'] ?? '').toString();
                    final int uni = _pInt(r['cajas']);
                    final double estibasCalc = uni > 0 ? (uni / 30) / 45 : 0.0;
                    final double ai = _pDouble(r['%ai']);
                    final prod = _pDouble(r['productividad']) * 100;

                    return TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text(fechaStr, style: const TextStyle(fontSize: 10, color: Color(0xFF1E293B)))),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                              child: Text((r['turno'] ?? '').toString(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                            ),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text((r['supervisor'] ?? '').toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text((r['operario'] ?? '').toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text(origen, style: const TextStyle(fontSize: 10, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text((r['sku'] ?? '').toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF1E293B)), overflow: TextOverflow.ellipsis)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text(_fmtInt(uni), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text(estibasCalc.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text(_fmtInt(r['unidades_mal_estado'] ?? 0), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Color(0xFFE53935)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('${ai.toStringAsFixed(2)}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD81B60)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('${prod.toStringAsFixed(1)}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: prod >= 100 ? const Color(0xFF00C853) : const Color(0xFFE53935)))),
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
}

// ==========================================
// 🎨 PAINTERS VECTORIALES PERSONALIZADOS
// ==========================================
class LineChartPainter extends CustomPainter {
  final List<String> keys;
  final List<double> values;
  final Color color;
  final bool isPorcentaje;

  LineChartPainter({required this.keys, required this.values, required this.color, this.isPorcentaje = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paintLine = Paint()..color = color..strokeWidth = 2.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final maxV = values.reduce(max) < 100 ? 110 : values.reduce(max) * 1.1;
    final minV = values.reduce(min) > 0 ? 0.0 : values.reduce(min);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final stepX = size.width / (values.length > 1 ? values.length - 1 : 1);
    final path = Path();
    List<Offset> points = [];

    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normY = (values[i] - minV) / range;
      final y = size.height - 25 - (normY * (size.height - 40));
      points.add(Offset(x, y));
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }

    canvas.drawPath(path, paintLine);
    TextPainter tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, Paint()..color = color);

      tp.text = TextSpan(text: values[i].toStringAsFixed(1) + (isPorcentaje ? '%' : ''), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color));
      tp.layout();
      tp.paint(canvas, Offset(points[i].dx - tp.width / 2, points[i].dy - 16));

      if (i < keys.length) {
        tp.text = TextSpan(text: keys[i], style: const TextStyle(fontSize: 9, color: Color(0xFF718096)));
        tp.layout();
        tp.paint(canvas, Offset(points[i].dx - tp.width / 2, size.height - 12));
      }
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DonutSegment {
  final double porcentaje;
  final Color color;
  DonutSegment({required this.porcentaje, required this.color});
}

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
        Expanded(flex: 5, child: CustomPaint(painter: DonutChartPainter(secciones: _construirSecciones(datos, total)), child: Container())),
        const SizedBox(width: 20),
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: datos.keys.toList().asMap().entries.map((entry) {
              int idx = entry.key;
              double pct = (datos[entry.value]! / total) * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: colores[idx % colores.length], borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${entry.value} (${pct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }).toList(),
          ),
        )
      ],
    );
  }

  List<DonutSegment> _construirSecciones(Map<String, double> datos, double total) {
    List<DonutSegment> lista = [];
    int idx = 0;
    datos.forEach((k, v) {
      lista.add(DonutSegment(porcentaje: (v / total) * 100, color: colores[idx % colores.length]));
      idx++;
    });
    return lista;
  }
}

class DonutChartPainter extends CustomPainter {
  final List<DonutSegment> secciones;
  DonutChartPainter({required this.secciones});

  @override
  void paint(Canvas canvas, Size size) {
    if (secciones.isEmpty) return;
    double startAngle = -pi / 2;
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = min(size.width, size.height) / 2 - 10;
    final paintArc = Paint()..style = PaintingStyle.stroke..strokeWidth = 24.0;

    for (var seg in secciones) {
      double sweepAngle = (seg.porcentaje / 100.0) * 2 * pi;
      paintArc.color = seg.color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - 12), startAngle, sweepAngle, false, paintArc);

      if (seg.porcentaje >= 5) {
        double middleAngle = startAngle + (sweepAngle / 2);
        double textX = center.dx + (radius * 0.70) * cos(middleAngle);
        double textY = center.dy + (radius * 0.70) * sin(middleAngle);
        TextPainter tp = TextPainter(text: TextSpan(text: '${seg.porcentaje.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(textX - (tp.width / 2), textY - (tp.height / 2)));
      }
      startAngle += sweepAngle;
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}