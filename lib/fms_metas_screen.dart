import 'package:flutter/material.dart';
import 'api_service.dart';

class FmsMetasScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const FmsMetasScreen({super.key, this.onToggleSidebar});

  @override
  State<FmsMetasScreen> createState() => _FmsMetasScreenState();
}

class _FmsMetasScreenState extends State<FmsMetasScreen> {
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _isLoading = true;
  String _errorMessage = '';

  List<Map<String, dynamic>> _metas = [];

  final List<String> _nombresMeses = [
    'ENERO',
    'FEBRERO',
    'MARZO',
    'ABRIL',
    'MAYO',
    'JUNIO',
    'JULIO',
    'AGOSTO',
    'SEPTIEMBRE',
    'OCTUBRE',
    'NOVIEMBRE',
    'DICIEMBRE'
  ];

  final List<int> _aniosDisponibles = [2024, 2025, 2026, 2027, 2028, 2029, 2030];

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  Future<void> _cargarDatosBD() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final resultados = await ApiService.consultarTabla(
        esquema: 'fms',
        tabla: 'fms_metas',
      );

      setState(() {
        _metas = resultados.map((e) => Map<String, dynamic>.from(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al consultar metas FMS: $e';
        _isLoading = false;
      });
    }
  }

  String _normalizarEvento(String raw) {
    String ev = raw.toUpperCase().trim();
    if (ev.contains('ACELERAC')) return 'ACELERACION';
    if (ev.contains('IMPACTO')) return 'IMPACTOS';
    if (ev.contains('FRENAD')) return 'FRENADAS';
    return ev;
  }

  String _normalizarArea(String raw) {
    String a = raw.toUpperCase().trim();
    if (a.contains('LINEA')) return 'LINEAS';
    if (a == 'T1') return 'T1';
    if (a.contains('T2') || a.contains('KA')) return 'T2 - KA';
    if (a.contains('REPROCESO')) return 'REPROCESOS';
    if (a.contains('MAQUILA')) return 'MAQUILA';
    if (a.contains('ALMACEN') || a.contains('BODEGA')) return 'ALMACEN';
    return a;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Text(
            _errorMessage,
            style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final metasDelMes = _metas.where((m) {
      int a = int.tryParse(m['anio']?.toString() ?? '0') ?? 0;
      int me = int.tryParse(m['mes']?.toString() ?? '0') ?? 0;
      return a == _anioSeleccionado && me == _mesSeleccionado;
    }).toList();

    List<String> ordenEventos = ['ACELERACION', 'IMPACTOS', 'FRENADAS'];
    List<String> ordenAreas = ['LINEAS', 'T1', 'T2 - KA', 'REPROCESOS', 'MAQUILA', 'ALMACEN'];

    // Cálculos para tarjetas KPI del mes seleccionado
    Map<String, int> metaGeneralPorEvento = {};
    Map<String, int> acumuladoPorEvento = {};

    for (var ev in ordenEventos) {
      final metasEv = metasDelMes.where((m) => _normalizarEvento(m['evento']?.toString() ?? '') == ev).toList();
      int mGen = metasEv.isNotEmpty ? (int.tryParse(metasEv.first['meta_general']?.toString() ?? '0') ?? 0) : 0;
      int acEv = 0;

      for (var area in ordenAreas) {
        final metaItem = metasEv.firstWhere(
              (m) => _normalizarArea(m['area']?.toString() ?? '') == area,
          orElse: () => {'acomulado': 0},
        );
        acEv += int.tryParse(metaItem['acomulado']?.toString() ?? '0') ?? 0;
      }

      metaGeneralPorEvento[ev] = mGen;
      acumuladoPorEvento[ev] = acEv;
    }

    int totalMetaGeneral = metaGeneralPorEvento.values.fold(0, (sum, val) => sum + val);
    int totalAcumuladoGeneral = acumuladoPorEvento.values.fold(0, (sum, val) => sum + val);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -----------------------------------------------------------------
            // 1. HEADER SUPERIOR CON FILTRO DE MES Y AÑO
            // -----------------------------------------------------------------
            _buildHeaderConFiltros(),
            const SizedBox(height: 24),

            // -----------------------------------------------------------------
            // 2. TARJETAS KPI RESUMEN
            // -----------------------------------------------------------------
            _buildSeccionTarjetasKpi(metaGeneralPorEvento, acumuladoPorEvento, totalMetaGeneral, totalAcumuladoGeneral),
            const SizedBox(height: 28),

            // -----------------------------------------------------------------
            // 3. LAS 3 TABLAS INDEPENDIENTES (SIN PROYECCIÓN)
            // -----------------------------------------------------------------
            ...ordenEventos.map((evento) {
              final metasEvento = metasDelMes.where((m) => _normalizarEvento(m['evento']?.toString() ?? '') == evento).toList();
              int metaGeneral = metaGeneralPorEvento[evento] ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 28.0),
                child: _buildTablaEvento(
                  evento: evento,
                  metaGeneral: metaGeneral,
                  metasEvento: metasEvento,
                  ordenAreas: ordenAreas,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📌 HEADER SUPERIOR CON CONTROLES DESPLEGABLES DE MES Y AÑO
  // ---------------------------------------------------------------------------
  Widget _buildHeaderConFiltros() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onToggleSidebar != null)
                IconButton(
                  icon: const Icon(Icons.menu_rounded, color: Colors.black87),
                  onPressed: widget.onToggleSidebar,
                ),
              const SizedBox(width: 8),
              const Text(
                'CUMPLIMIENTO METAS FMS',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              // DROPDOWN SELECCIÓN DE MES
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _mesSeleccionado,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0F172A)),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem<int>(
                        value: index + 1,
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF2563EB)),
                            const SizedBox(width: 8),
                            Text(_nombresMeses[index]),
                          ],
                        ),
                      );
                    }),
                    onChanged: (nuevoMes) {
                      if (nuevoMes != null) {
                        setState(() {
                          _mesSeleccionado = nuevoMes;
                        });
                      }
                    },
                  ),
                ),
              ),

              // DROPDOWN SELECCIÓN DE AÑO
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _anioSeleccionado,
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0F172A)),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
                    items: _aniosDisponibles.map((anio) {
                      return DropdownMenuItem<int>(
                        value: anio,
                        child: Text('$anio'),
                      );
                    }).toList(),
                    onChanged: (nuevoAnio) {
                      if (nuevoAnio != null) {
                        setState(() {
                          _anioSeleccionado = nuevoAnio;
                        });
                      }
                    },
                  ),
                ),
              ),

              // BOTÓN RECARGAR
              ElevatedButton.icon(
                onPressed: _cargarDatosBD,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('ACTUALIZAR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💳 TARJETAS KPI RESUMEN
  // ---------------------------------------------------------------------------
  Widget _buildSeccionTarjetasKpi(
      Map<String, int> metaGeneral,
      Map<String, int> acumulados,
      int totalMeta,
      int totalAcumulado,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool esAncho = constraints.maxWidth > 900;

        List<Widget> listaTarjetas = [
          _buildTarjetaCard(
            titulo: 'ACELERACIÓN',
            acumulado: acumulados['ACELERACION'] ?? 0,
            meta: metaGeneral['ACELERACION'] ?? 1,
            icono: Icons.speed_rounded,
          ),
          _buildTarjetaCard(
            titulo: 'IMPACTOS',
            acumulado: acumulados['IMPACTOS'] ?? 0,
            meta: metaGeneral['IMPACTOS'] ?? 1,
            icono: Icons.warning_amber_rounded,
          ),
          _buildTarjetaCard(
            titulo: 'FRENADAS',
            acumulado: acumulados['FRENADAS'] ?? 0,
            meta: metaGeneral['FRENADAS'] ?? 1,
            icono: Icons.do_not_disturb_on_rounded,
          ),
          _buildTarjetaCard(
            titulo: 'TOTAL GENERAL',
            acumulado: totalAcumulado,
            meta: totalMeta,
            icono: Icons.analytics_rounded,
          ),
        ];

        if (esAncho) {
          return Row(
            children: listaTarjetas
                .map((t) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: t)))
                .toList(),
          );
        } else {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: listaTarjetas
                .map((t) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: t))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildTarjetaCard({
    required String titulo,
    required int acumulado,
    required int meta,
    required IconData icono,
  }) {
    bool esExcedido = acumulado > meta;
    double porcentaje = meta > 0 ? (acumulado / meta) * 100 : 0.0;

    Color colorPrincipal = esExcedido ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    Color colorFondoBadge = esExcedido ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorPrincipal.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colorPrincipal.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icono, size: 20, color: const Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Text(
                    titulo,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: colorFondoBadge, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${porcentaje.toStringAsFixed(0)}%',
                  style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$acumulado', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: colorPrincipal)),
              Text(' / $meta', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (porcentaje / 100).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(colorPrincipal),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 TABLA INDEPENDIENTE POR EVENTO (SIN COLUMNA PROYECCIÓN)
  // ---------------------------------------------------------------------------
  Widget _buildTablaEvento({
    required String evento,
    required int metaGeneral,
    required List<Map<String, dynamic>> metasEvento,
    required List<String> ordenAreas,
  }) {
    int sumaMetaArea = 0;
    int sumaAcumulado = 0;

    List<TableRow> filas = [];

    // CABECERA DE LA TABLA (SIN PROYECCIÓN)
    filas.add(
      const TableRow(
        decoration: BoxDecoration(color: Color(0xFF1E293B)),
        children: [
          Padding(
            padding: EdgeInsets.all(14),
            child: Text('ÁREA', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white, letterSpacing: 0.5)),
          ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Text('META ÁREA', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white, letterSpacing: 0.5)),
          ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Text('ACTUALES', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white, letterSpacing: 0.5)),
          ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Text('% INCUMPL.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white, letterSpacing: 0.5)),
          ),
        ],
      ),
    );

    // FILAS POR ÁREA
    for (var area in ordenAreas) {
      final metaItem = metasEvento.firstWhere(
            (m) => _normalizarArea(m['area']?.toString() ?? '') == area,
        orElse: () => {'meta_area': 0, 'acomulado': 0, 'metas%': 0},
      );

      int metaArea = int.tryParse(metaItem['meta_area']?.toString() ?? '0') ?? 0;
      int acumulado = int.tryParse(metaItem['acomulado']?.toString() ?? '0') ?? 0;

      double pctBaseBD = double.tryParse(metaItem['metas%']?.toString() ?? '0') ?? 0.0;
      double pctIncumplimiento = metaArea > 0 ? (acumulado / metaArea) : pctBaseBD;

      sumaMetaArea += metaArea;
      sumaAcumulado += acumulado;

      bool esExcedido = acumulado > metaArea;
      Color colorCelda = esExcedido ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);
      Color colorTexto = esExcedido ? const Color(0xFF991B1B) : const Color(0xFF166534);

      filas.add(
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(area, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF334155))),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('$metaArea', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Container(
              color: colorCelda,
              padding: const EdgeInsets.all(12),
              child: Text(
                '$acumulado',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: colorTexto),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${(pctIncumplimiento * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: colorTexto),
              ),
            ),
          ],
        ),
      );
    }

    // FILA TOTAL
    double pctTotal = sumaMetaArea > 0 ? (sumaAcumulado / sumaMetaArea) : 0.0;
    bool esTotalExcedido = sumaAcumulado > sumaMetaArea;
    Color colorTotalTexto = esTotalExcedido ? const Color(0xFF991B1B) : const Color(0xFF166534);

    filas.add(
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFE2E8F0)),
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('TOTAL', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A))),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('$sumaMetaArea', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('$sumaAcumulado', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: colorTotalTexto)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '${(pctTotal * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: colorTotalTexto),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BANNER DE ENCABEZADO DE CADA EVENTO
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  evento,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF60A5FA).withOpacity(0.4)),
                  ),
                  child: Text(
                    'META GENERAL: $metaGeneral',
                    style: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            child: Table(
              border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 1),
              columnWidths: const {
                0: FlexColumnWidth(2.2), // ÁREA
                1: FlexColumnWidth(1.8), // META ÁREA
                2: FlexColumnWidth(2.0), // ACTUALES
                3: FlexColumnWidth(2.0), // % INCUMPLIMIENTO
              },
              children: filas,
            ),
          ),
        ],
      ),
    );
  }
}