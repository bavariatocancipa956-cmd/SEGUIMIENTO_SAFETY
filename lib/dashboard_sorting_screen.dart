import 'dart:math';
import 'package:flutter/material.dart';
import 'api_service.dart';

class DashboardSortingScreen extends StatefulWidget {
  final Map<String, dynamic>? datosEmpleado;
  final VoidCallback? onToggleSidebar;

  const DashboardSortingScreen({
    super.key,
    this.datosEmpleado,
    this.onToggleSidebar,
  });

  @override
  State<DashboardSortingScreen> createState() => _DashboardSortingScreenState();
}

class _DashboardSortingScreenState extends State<DashboardSortingScreen> {
  bool _isLoading = true;

  List<Map<String, dynamic>> _rawRegistros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  // Filtros
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _turnoFiltro = 'Todos';
  String _supervisorFiltro = 'Todos';
  String _skuFiltro = 'Todos';

  List<String> _listaTurnos = ['Todos'];
  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaSKUs = ['Todos'];

  // KPIs
  double _totalEstibasRev = 0.0;
  int _totalUnidadesRev = 0;
  int _totalBuenEstado = 0;
  int _totalDefectuosas = 0;
  double _tasaDefectos = 0.0;
  double _promedioProductividad = 0.0;

  // Agrupaciones para tablas y gráficos
  Map<String, double> _estibasPorDia = {};
  Map<String, double> _productividadPorDia = {};
  Map<String, double> _productividadPorMes = {};
  Map<String, Map<String, dynamic>> _resumenTurno = {};
  Map<String, Map<String, dynamic>> _resumenAuxiliar = {};
  Map<String, int> _causalesDefectos = {};
  Map<String, Map<String, dynamic>> _resumenSKU = {};
  Map<String, Map<String, dynamic>> _resumenDefectos = {};
  Map<String, int> _unidadesPorSKUTop = {};
  Map<String, int> _defectosPorTipo = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fechaDesde = DateTime(now.year, now.month, 1);
    _fechaHasta = now;
    _cargarDatos();
  }

  // 🛠️ Formateadores de números y meses
  String _fmtInt(num valor) {
    String str = valor.toString();
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
  }

  String _fmtDec(double valor) {
    String str = valor.toStringAsFixed(2).replaceAll('.', ',');
    List<String> partes = str.split(',');
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    partes[0] = partes[0].replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return partes.join(',');
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
        const meses = [
          '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
          'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
        ];
        if (mes >= 1 && mes <= 12) {
          return '${meses[mes]} $anio';
        }
      }
    } catch (_) {}
    return key;
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      final items = await ApiService.consultarTabla(
        esquema: 'sorting',
        tabla: 'sorting_productivida',
      );

      _rawRegistros = List<Map<String, dynamic>>.from(items);

      final setTurnos = <String>{'Todos'};
      final setSupervisores = <String>{'Todos'};
      final setSKUs = <String>{'Todos'};

      for (var r in _rawRegistros) {
        final t = (r['turno'] ?? '').toString().trim();
        final s = (r['supervisor'] ?? '').toString().trim();
        final tipo = (r['tipo'] ?? '').toString().trim();

        if (t.isNotEmpty) setTurnos.add(t);
        if (s.isNotEmpty) setSupervisores.add(s);
        if (tipo.isNotEmpty && !_esDefecto(tipo)) {
          setSKUs.add(tipo);
        }
      }

      _listaTurnos = setTurnos.toList()..sort();
      _listaSupervisores = setSupervisores.toList()..sort();
      _listaSKUs = setSKUs.toList()..sort();

      _aplicarFiltrosYCalculos();
    } catch (e) {
      debugPrint('Error cargando dashboard sorting: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _esDefecto(String tipo) {
    final t = tipo.toLowerCase();
    return t.contains('unidades') ||
        t.contains('scuffing') ||
        t.contains('despicadas') ||
        t.contains('marcas') ||
        t.contains('extraño') ||
        t.contains('mezcladas');
  }

  void _aplicarFiltrosYCalculos() {
    _registrosFiltrados = _rawRegistros.where((r) {
      final fechaStr = (r['fecha'] ?? '').toString().substring(0, 10);
      final DateTime? f = DateTime.tryParse(fechaStr);

      if (f != null) {
        if (_fechaDesde != null && f.isBefore(_fechaDesde!)) return false;
        if (_fechaHasta != null && f.isAfter(_fechaHasta!.add(const Duration(days: 1)))) return false;
      }

      final t = (r['turno'] ?? '').toString().trim();
      if (_turnoFiltro != 'Todos' && t != _turnoFiltro) return false;

      final s = (r['supervisor'] ?? '').toString().trim();
      if (_supervisorFiltro != 'Todos' && s != _supervisorFiltro) return false;

      final tipo = (r['tipo'] ?? '').toString().trim();
      if (_skuFiltro != 'Todos' && tipo != _skuFiltro) return false;

      return true;
    }).toList();

    _totalEstibasRev = 0.0;
    _totalUnidadesRev = 0;
    _totalBuenEstado = 0;
    _totalDefectuosas = 0;

    _estibasPorDia.clear();
    _productividadPorDia.clear();
    _productividadPorMes.clear();
    _resumenTurno.clear();
    _resumenAuxiliar.clear();
    _causalesDefectos.clear();
    _resumenSKU.clear();
    _resumenDefectos.clear();
    _unidadesPorSKUTop.clear();
    _defectosPorTipo.clear();

    Map<String, List<double>> prodDiaMap = {};
    Map<String, List<double>> prodMesMap = {};

    for (var r in _registrosFiltrados) {
      final cant = int.tryParse(r['cantidad']?.toString() ?? '0') ?? 0;
      final estibas = double.tryParse(r['estibas_revisadas']?.toString() ?? '0') ?? 0.0;
      final prod = double.tryParse(r['productividad']?.toString() ?? '0') ?? 0.0;
      final tipo = (r['tipo'] ?? 'Desconocido').toString().trim();
      final turno = (r['turno'] ?? 'N/A').toString().trim();
      final aux = (r['auxiliar'] ?? 'N/A').toString().trim();
      final causal = (r['causal'] ?? 'Ninguna').toString().trim();
      final fechaStr = (r['fecha'] ?? '').toString().substring(0, 10);

      _totalUnidadesRev += cant;
      _totalEstibasRev += estibas;

      final esDef = _esDefecto(tipo);
      if (esDef) {
        _totalDefectuosas += cant;
        _defectosPorTipo[tipo] = (_defectosPorTipo[tipo] ?? 0) + cant;
      } else {
        _totalBuenEstado += cant;
        _unidadesPorSKUTop[tipo] = (_unidadesPorSKUTop[tipo] ?? 0) + cant;
      }

      if (fechaStr.isNotEmpty) {
        final diaLabel = fechaStr.length >= 10 ? fechaStr.substring(8, 10) : fechaStr;
        _estibasPorDia[diaLabel] = (_estibasPorDia[diaLabel] ?? 0.0) + estibas;
        prodDiaMap.putIfAbsent(diaLabel, () => []).add(prod);

        final mesKey = fechaStr.length >= 7 ? fechaStr.substring(0, 7) : 'N/A';
        prodMesMap.putIfAbsent(mesKey, () => []).add(prod);
      }

      final causalKey = causal.isEmpty ? 'Ninguna' : causal;
      _causalesDefectos[causalKey] = (_causalesDefectos[causalKey] ?? 0) + cant;

      // Turnos
      if (!_resumenTurno.containsKey(turno)) {
        _resumenTurno[turno] = {
          'estibas': 0.0,
          'unidades': 0,
          'defectuosas': 0,
          'buenas': 0,
          'prodList': <double>[],
        };
      }
      _resumenTurno[turno]!['estibas'] += estibas;
      _resumenTurno[turno]!['unidades'] += cant;
      if (esDef) {
        _resumenTurno[turno]!['defectuosas'] += cant;
      } else {
        _resumenTurno[turno]!['buenas'] += cant;
      }
      (_resumenTurno[turno]!['prodList'] as List<double>).add(prod);

      // Auxiliares
      if (!_resumenAuxiliar.containsKey(aux)) {
        _resumenAuxiliar[aux] = {
          'estibas': 0.0,
          'unidades': 0,
          'defectuosas': 0,
          'buenas': 0,
          'prodList': <double>[],
        };
      }
      _resumenAuxiliar[aux]!['estibas'] += estibas;
      _resumenAuxiliar[aux]!['unidades'] += cant;
      if (esDef) {
        _resumenAuxiliar[aux]!['defectuosas'] += cant;
      } else {
        _resumenAuxiliar[aux]!['buenas'] += cant;
      }
      (_resumenAuxiliar[aux]!['prodList'] as List<double>).add(prod);

      // SKUs y Defectos
      if (esDef) {
        if (!_resumenDefectos.containsKey(tipo)) {
          _resumenDefectos[tipo] = {'unidades': 0, 'estibas': 0.0};
        }
        _resumenDefectos[tipo]!['unidades'] += cant;
        _resumenDefectos[tipo]!['estibas'] += estibas;
      } else {
        if (!_resumenSKU.containsKey(tipo)) {
          _resumenSKU[tipo] = {'unidades': 0, 'buenas': 0, 'estibas': 0.0};
        }
        _resumenSKU[tipo]!['unidades'] += cant;
        _resumenSKU[tipo]!['buenas'] += cant;
        _resumenSKU[tipo]!['estibas'] += estibas;
      }
    }

    _tasaDefectos = _totalUnidadesRev > 0 ? (_totalDefectuosas / _totalUnidadesRev) * 100 : 0.0;

    prodDiaMap.forEach((k, list) {
      _productividadPorDia[k] = list.isEmpty ? 0.0 : (list.reduce((a, b) => a + b) / list.length) * 100;
    });

    prodMesMap.forEach((k, list) {
      _productividadPorMes[k] = list.isEmpty ? 0.0 : (list.reduce((a, b) => a + b) / list.length) * 100;
    });

    double sumaProdTotal = 0.0;
    int countProd = 0;
    for (var r in _registrosFiltrados) {
      final p = double.tryParse(r['productividad']?.toString() ?? '0') ?? 0.0;
      if (p > 0) {
        sumaProdTotal += p;
        countProd++;
      }
    }
    _promedioProductividad = countProd > 0 ? (sumaProdTotal / countProd) * 100 : 0.0;
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
        if (esDesde) {
          _fechaDesde = picked;
        } else {
          _fechaHasta = picked;
        }
        _aplicarFiltrosYCalculos();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD81B60)))
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
            _buildFilaTablasTurnoYAuxiliar(),
            const SizedBox(height: 16),
            _buildFilaGraficosDistribucion(),
            const SizedBox(height: 16),
            _buildFilaGraficosSKUsYDefectos(),
            const SizedBox(height: 16),
            _buildFilaTablasSKUsYDefectos(),
            const SizedBox(height: 16),
            _buildTablaHistorialCompleto(),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildFiltroFecha('DESDE', _fechaDesde, () => _seleccionarFecha(true)),
          _buildFiltroFecha('HASTA', _fechaHasta, () => _seleccionarFecha(false)),
          _buildSelectorDropdown('TURNO', _turnoFiltro, _listaTurnos, (v) {
            setState(() {
              _turnoFiltro = v!;
              _aplicarFiltrosYCalculos();
            });
          }),
          _buildSelectorDropdown('SUPERVISOR', _supervisorFiltro, _listaSupervisores, (v) {
            setState(() {
              _supervisorFiltro = v!;
              _aplicarFiltrosYCalculos();
            });
          }),
          _buildSelectorDropdown('SKU', _skuFiltro, _listaSKUs, (v) {
            setState(() {
              _skuFiltro = v!;
              _aplicarFiltrosYCalculos();
            });
          }),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD81B60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            icon: const Icon(Icons.filter_list_rounded, size: 18),
            label: const Text('FILTRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
            onPressed: () => setState(() => _aplicarFiltrosYCalculos()),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF334155),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            icon: const Icon(Icons.camera_alt_rounded, size: 18),
            label: const Text('FOTO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () {},
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            icon: const Icon(Icons.tv_rounded, size: 18),
            label: const Text('TV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            onPressed: () {},
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
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: opciones.contains(valor) ? valor : opciones.first,
              isDense: false,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              items: opciones.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2️⃣ TARJETAS KPIS CON SEMÁFORO EN PRODUCTIVIDAD
  // ---------------------------------------------------------------------------
  Widget _buildTarjetasKPIWeb() {
    return LayoutBuilder(builder: (context, constraints) {
      double w = (constraints.maxWidth - 50) / 6;
      if (w < 160) w = (constraints.maxWidth - 20) / 2;

      final Color colorProd = _promedioProductividad >= 100.0 ? const Color(0xFF00C853) : const Color(0xFFE53935);

      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildKPICardWeb('ESTIBAS REVISADAS', _fmtDec(_totalEstibasRev), const Color(0xFF1E88E5), Icons.layers_outlined, w),
          _buildKPICardWeb('UNIDADES REVISADAS', _fmtInt(_totalUnidadesRev), const Color(0xFF1E88E5), Icons.inbox_outlined, w),
          _buildKPICardWeb('UNIDADES BUEN ESTADO', _fmtInt(_totalBuenEstado), const Color(0xFF00C853), Icons.check_circle_outline, w),
          _buildKPICardWeb('UNIDADES DEFECTUOSAS', _fmtInt(_totalDefectuosas), const Color(0xFFE53935), Icons.cancel_outlined, w),
          _buildKPICardWeb('TASA DEFECTOS (%)', '${_tasaDefectos.toStringAsFixed(2)}%', const Color(0xFFD81B60), Icons.pie_chart_outline, w),
          _buildKPICardWeb('PROM. PRODUCTIVIDAD', '${_promedioProductividad.toStringAsFixed(2)}%', colorProd, Icons.speed_outlined, w),
        ],
      );
    });
  }

  Widget _buildKPICardWeb(String titulo, String valor, Color color, IconData icono, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF718096)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icono, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3️⃣ FILA DE GRÁFICOS PRINCIPALES
  // ---------------------------------------------------------------------------
  Widget _buildFilaGraficosPrincipales() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 1000;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCardGraficoLinea('Estibas Revisadas por Día', _estibasPorDia, const Color(0xFF1E88E5), esProductividad: false)),
          const SizedBox(width: 16),
          Expanded(child: _buildCardGraficoLinea('Tendencia Diaria de Productividad (%)', _productividadPorDia, const Color(0xFF00C853), esProductividad: true)),
          const SizedBox(width: 16),
          Expanded(child: _buildCardGraficoBarrasMes('Productividad Promedio por Mes (%)', _productividadPorMes)),
        ],
      )
          : Column(
        children: [
          _buildCardGraficoLinea('Estibas Revisadas por Día', _estibasPorDia, const Color(0xFF1E88E5), esProductividad: false),
          const SizedBox(height: 16),
          _buildCardGraficoLinea('Tendencia Diaria de Productividad (%)', _productividadPorDia, const Color(0xFF00C853), esProductividad: true),
          const SizedBox(height: 16),
          _buildCardGraficoBarrasMes('Productividad Promedio por Mes (%)', _productividadPorMes),
        ],
      );
    });
  }

  Widget _buildCardGraficoLinea(String titulo, Map<String, double> datos, Color colorLinea, {bool esProductividad = false}) {
    final keys = datos.keys.toList();
    final values = datos.values.toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
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
              painter: LineChartPainter(keys: keys, values: values, color: colorLinea, esProductividad: esProductividad),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGraficoBarrasMes(String titulo, Map<String, double> datos) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
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
                final esCumplido = val >= 100.0;
                final col = esCumplido ? const Color(0xFF00C853) : const Color(0xFFE53935);
                final alturaBarra = (val / 200.0) * 150.0;
                final nombreMes = _obtenerNombreMes(e.key);

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${val.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: col)),
                    const SizedBox(height: 6),
                    Container(
                      width: 60,
                      height: min(150, max(15, alturaBarra)),
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
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

  // ---------------------------------------------------------------------------
  // 4️⃣ TABLAS: TURNO & RENDIMIENTO AUXILIAR (260px)
  // ---------------------------------------------------------------------------
  Widget _buildFilaTablasTurnoYAuxiliar() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 900;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTablaEstandar('Resumen Operativo por Turno', _buildCuerpoTablaTurno())),
          const SizedBox(width: 16),
          Expanded(child: _buildTablaEstandar('Rendimiento por Auxiliar', _buildCuerpoTablaAuxiliar())),
        ],
      )
          : Column(
        children: [
          _buildTablaEstandar('Resumen Operativo por Turno', _buildCuerpoTablaTurno()),
          const SizedBox(height: 16),
          _buildTablaEstandar('Rendimiento por Auxiliar', _buildCuerpoTablaAuxiliar()),
        ],
      );
    });
  }

  // ---------------------------------------------------------------------------
  // 7️⃣ TABLAS: SKU & DEFECTOS (260px)
  // ---------------------------------------------------------------------------
  Widget _buildFilaTablasSKUsYDefectos() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 900;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTablaEstandar('Resumen General por SKU', _buildCuerpoTablaSKU())),
          const SizedBox(width: 16),
          Expanded(child: _buildTablaEstandar('SKUs en Mal Estado (Defectos)', _buildCuerpoTablaDefectos(), tituloColor: const Color(0xFFE53935))),
        ],
      )
          : Column(
        children: [
          _buildTablaEstandar('Resumen General por SKU', _buildCuerpoTablaSKU()),
          const SizedBox(height: 16),
          _buildTablaEstandar('SKUs en Mal Estado (Defectos)', _buildCuerpoTablaDefectos(), tituloColor: const Color(0xFFE53935)),
        ],
      );
    });
  }

  Widget _buildTablaEstandar(String titulo, Widget tabla, {Color tituloColor = const Color(0xFF1E293B)}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: tituloColor)),
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            width: double.infinity,
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: tabla,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuerpoTablaTurno() {
    return DataTable(
      columnSpacing: 10,
      horizontalMargin: 8,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      dividerThickness: 0.5,
      columns: const [
        DataColumn(label: Text('TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('ESTIBAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('U. REVISADAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('DEFECTUOSAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('BUEN ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('PRODUCTIVIDAD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
      ],
      rows: _resumenTurno.entries.map((e) {
        final list = e.value['prodList'] as List<double>;
        final avgProd = list.isEmpty ? 0.0 : (list.reduce((a, b) => a + b) / list.length) * 100;
        final colProd = avgProd >= 100.0 ? const Color(0xFF00C853) : const Color(0xFFE53935);

        return DataRow(cells: [
          DataCell(Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
            child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF3730A3))),
          )),
          DataCell(Text(_fmtDec(e.value['estibas']), style: const TextStyle(fontSize: 11))),
          DataCell(Text(_fmtInt(e.value['unidades']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          DataCell(Text(_fmtInt(e.value['defectuosas']), style: const TextStyle(fontSize: 11, color: Color(0xFFE53935)))),
          DataCell(Text(_fmtInt(e.value['buenas']), style: const TextStyle(fontSize: 11, color: Color(0xFF00C853)))),
          DataCell(Text('${avgProd.toStringAsFixed(2)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colProd))),
        ]);
      }).toList(),
    );
  }

  Widget _buildCuerpoTablaAuxiliar() {
    return DataTable(
      columnSpacing: 10,
      horizontalMargin: 8,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      dividerThickness: 0.5,
      columns: const [
        DataColumn(label: Text('AUXILIAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('ESTIBAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('U. REVISADAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('DEFECTUOSAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('PRODUCTIVIDAD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
      ],
      rows: _resumenAuxiliar.entries.map((e) {
        final list = e.value['prodList'] as List<double>;
        final avgProd = list.isEmpty ? 0.0 : (list.reduce((a, b) => a + b) / list.length) * 100;
        final colProd = avgProd >= 100.0 ? const Color(0xFF00C853) : const Color(0xFFE53935);

        return DataRow(cells: [
          DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
          DataCell(Text(_fmtDec(e.value['estibas']), style: const TextStyle(fontSize: 11))),
          DataCell(Text(_fmtInt(e.value['unidades']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          DataCell(Text(_fmtInt(e.value['defectuosas']), style: const TextStyle(fontSize: 11, color: Color(0xFFE53935)))),
          DataCell(Text('${avgProd.toStringAsFixed(2)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colProd))),
        ]);
      }).toList(),
    );
  }

  Widget _buildCuerpoTablaSKU() {
    return DataTable(
      columnSpacing: 10,
      horizontalMargin: 8,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      dividerThickness: 0.5,
      columns: const [
        DataColumn(label: Text('SKU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('U. REVISADAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('TOTAL BUENAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
        DataColumn(label: Text('ESTIBAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
      ],
      rows: _resumenSKU.entries.map((e) {
        return DataRow(cells: [
          DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
          DataCell(Text(_fmtInt(e.value['unidades']), style: const TextStyle(fontSize: 11))),
          DataCell(Text(_fmtInt(e.value['buenas']), style: const TextStyle(fontSize: 11, color: Color(0xFF00C853), fontWeight: FontWeight.bold))),
          DataCell(Text(_fmtDec(e.value['estibas']), style: const TextStyle(fontSize: 11))),
        ]);
      }).toList(),
    );
  }

  Widget _buildCuerpoTablaDefectos() {
    return DataTable(
      columnSpacing: 10,
      horizontalMargin: 8,
      headingRowHeight: 38,
      dataRowHeight: 42,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFFFF5F5)),
      dividerThickness: 0.5,
      columns: const [
        DataColumn(label: Text('DEFECTO / MAL ESTADO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFFE53935)))),
        DataColumn(label: Text('UNIDADES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFFE53935)))),
        DataColumn(label: Text('ESTIBAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFFE53935)))),
      ],
      rows: _resumenDefectos.entries.map((e) {
        return DataRow(cells: [
          DataCell(Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFE53935)))),
          DataCell(Text(_fmtInt(e.value['unidades']), style: const TextStyle(fontSize: 11, color: Color(0xFFE53935), fontWeight: FontWeight.bold))),
          DataCell(Text(_fmtDec(e.value['estibas']), style: const TextStyle(fontSize: 11))),
        ]);
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // 5️⃣ GRÁFICOS DE ANILLO: DISTRIBUCIÓN DE CALIDAD & CAUSALES
  // ---------------------------------------------------------------------------
  Widget _buildFilaGraficosDistribucion() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 900;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCardAnilloCalidad()),
          const SizedBox(width: 16),
          Expanded(child: _buildCardAnilloCausales()),
        ],
      )
          : Column(
        children: [
          _buildCardAnilloCalidad(),
          const SizedBox(height: 16),
          _buildCardAnilloCausales(),
        ],
      );
    });
  }

  Widget _buildCardAnilloCalidad() {
    final double pctBuenas = _totalUnidadesRev > 0 ? (_totalBuenEstado / _totalUnidadesRev) * 100 : 0.0;
    final double pctDefectos = _totalUnidadesRev > 0 ? (_totalDefectuosas / _totalUnidadesRev) * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          const Text('Distribución General de Calidad', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
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
                    const Text('Defectos', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
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
              _buildLeyendaAnillo('Defectos', const Color(0xFFE53935)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardAnilloCausales() {
    final total = _causalesDefectos.values.fold(0, (a, b) => a + b);
    final colores = [
      const Color(0xFFD81B60),
      const Color(0xFFF59E0B),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFF10B981),
    ];

    List<DonutSegment> secciones = [];
    int indexColor = 0;
    _causalesDefectos.forEach((k, v) {
      final pct = total > 0 ? (v / total) * 100 : 0.0;
      secciones.add(DonutSegment(porcentaje: pct, color: colores[indexColor % colores.length]));
      indexColor++;
    });

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          const Text('Distribución de Defectos por Causal (%)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 200,
                  child: CustomPaint(
                    size: const Size(180, 180),
                    painter: DonutChartPainter(secciones: secciones),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _causalesDefectos.entries.map((e) {
                    final idx = _causalesDefectos.keys.toList().indexOf(e.key);
                    final col = colores[idx % colores.length];
                    final pct = total > 0 ? (e.value / total) * 100 : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis)),
                          Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
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

  // ---------------------------------------------------------------------------
  // 6️⃣ GRÁFICOS DE BARRAS: SKUS TOP & MAL ESTADO
  // ---------------------------------------------------------------------------
  Widget _buildFilaGraficosSKUsYDefectos() {
    return LayoutBuilder(builder: (context, constraints) {
      bool esAncho = constraints.maxWidth > 900;
      return esAncho
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCardGraficoBarrasSKU('Unidades Revisadas por SKU (Top 10)', _unidadesPorSKUTop, const Color(0xFFF59E0B))),
          const SizedBox(width: 16),
          Expanded(child: _buildCardGraficoBarrasSKU('Unidades por Mal Estado (Cantidades)', _defectosPorTipo, const Color(0xFFEF4444))),
        ],
      )
          : Column(
        children: [
          _buildCardGraficoBarrasSKU('Unidades Revisadas por SKU (Top 10)', _unidadesPorSKUTop, const Color(0xFFF59E0B)),
          const SizedBox(height: 16),
          _buildCardGraficoBarrasSKU('Unidades por Mal Estado (Cantidades)', _defectosPorTipo, const Color(0xFFEF4444)),
        ],
      );
    });
  }

  Widget _buildCardGraficoBarrasSKU(String titulo, Map<String, int> datos, Color colorBarra) {
    final listSorted = datos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top10 = listSorted.take(10).toList();
    final maxVal = top10.isNotEmpty ? top10.first.value : 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        children: [
          Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: top10.isEmpty
                ? const Center(child: Text('Sin datos', style: TextStyle(color: Colors.grey, fontSize: 11)))
                : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: top10.map((e) {
                final alt = (e.value / maxVal) * 140.0;
                final label = e.key.replaceAll('No. Unidades ', '').replaceAll('con ', '');

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_fmtInt(e.value), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    Container(
                      width: 36,
                      height: max(10.0, alt),
                      decoration: BoxDecoration(
                        color: colorBarra,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 50,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 9, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 8️⃣ HISTORIAL COMPLETO
  // ---------------------------------------------------------------------------
  Widget _buildTablaHistorialCompleto() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Historial Completo (Detalle)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
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
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(0.8),
                  2: FlexColumnWidth(2.5),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(1.5),
                  5: FlexColumnWidth(2.5),
                  6: FlexColumnWidth(1.0),
                  7: FlexColumnWidth(1.0),
                  8: FlexColumnWidth(2.0),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(color: Colors.grey.shade200, width: 1),
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF8FAFC)),
                    children: [
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('FECHA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('SUPERVISOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('AUXILIAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('CAUSAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('TIPO (SKU / DEFECTO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('CANT.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('ESTIBAS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8), child: Text('OBSERVACIONES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF64748B)))),
                    ],
                  ),
                  ..._registrosFiltrados.map((r) {
                    final tipo = (r['tipo'] ?? '').toString();
                    final esDef = _esDefecto(tipo);
                    final fechaStr = (r['fecha'] ?? '').toString().substring(0, 10);
                    final estibas = double.tryParse(r['estibas_revisadas']?.toString() ?? '0') ?? 0.0;

                    return TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text(fechaStr, style: const TextStyle(fontSize: 10, color: Color(0xFF1E293B)))),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                              child: Text((r['turno'] ?? '').toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                            ),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text((r['supervisor'] ?? '').toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF475569)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text((r['auxiliar'] ?? '').toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text((r['causal'] ?? '').toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF9333EA), fontWeight: FontWeight.bold))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text(tipo, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: esDef ? const Color(0xFFDC2626) : const Color(0xFF1E293B)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text(_fmtInt(r['cantidad'] ?? 0), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text(_fmtDec(estibas), style: const TextStyle(fontSize: 10, color: Color(0xFF475569)))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text((r['observacion'] ?? '-').toString(), style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)))),
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
  final bool esProductividad;

  LineChartPainter({
    required this.keys,
    required this.values,
    required this.color,
    this.esProductividad = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paintLine = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final maxV = values.reduce(max);
    final minV = values.reduce(min);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);

    final stepX = size.width / (values.length > 1 ? values.length - 1 : 1);
    final path = Path();

    List<Offset> points = [];

    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normY = (values[i] - minV) / range;
      final y = size.height - 25 - (normY * (size.height - 40));
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paintLine);

    TextPainter tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < points.length; i++) {
      Color colorP = color;
      if (esProductividad) {
        colorP = values[i] >= 100.0 ? const Color(0xFF00C853) : const Color(0xFFE53935);
      }

      final paintDot = Paint()..color = colorP;
      canvas.drawCircle(points[i], 4, paintDot);

      // Label del valor
      tp.text = TextSpan(
        text: values[i].toStringAsFixed(0) + (esProductividad ? '%' : ''),
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: colorP),
      );
      tp.layout();
      tp.paint(canvas, Offset(points[i].dx - tp.width / 2, points[i].dy - 14));

      // Label del eje X
      if (i < keys.length) {
        tp.text = TextSpan(
          text: keys[i],
          style: const TextStyle(fontSize: 8, color: Color(0xFF718096)),
        );
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

class DonutChartPainter extends CustomPainter {
  final List<DonutSegment> secciones;
  DonutChartPainter({required this.secciones});

  @override
  void paint(Canvas canvas, Size size) {
    if (secciones.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    double startAngle = -pi / 2;

    for (var seg in secciones) {
      final sweepAngle = (seg.porcentaje / 100.0) * 2 * pi;
      paint.color = seg.color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}