import 'package:flutter/material.dart';
import 'api_service.dart';

class FmsTendenciasOperadoresScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const FmsTendenciasOperadoresScreen({super.key, this.onToggleSidebar});

  @override
  State<FmsTendenciasOperadoresScreen> createState() => _FmsTendenciasOperadoresScreenState();
}

class _FmsTendenciasOperadoresScreenState extends State<FmsTendenciasOperadoresScreen> {
  // ---------------------------------------------------------------------------
  // 📅 FILTROS DE TENDENCIA
  // ---------------------------------------------------------------------------
  int _anoSeleccionado = DateTime.now().year;
  String _eventoSeleccionado = 'TODOS';
  String _filtroTextoOperador = '';

  // ---------------------------------------------------------------------------
  // 🔢 ESTADO DE ORDENAMIENTO (Por defecto: TOTAL de Mayor a Menor)
  // -1: Operador | 0..11: Enero..Diciembre | 12: Total General
  // ---------------------------------------------------------------------------
  int _columnaOrden = 12;
  bool _ordenAscendente = false;

  List<int> _listaAnos = [2024, 2025, 2026, 2027];
  List<String> _listaEventos = ['TODOS', 'ACELERACION', 'IMPACTOS', 'FRENADAS'];

  // ---------------------------------------------------------------------------
  // 🌐 ESTADOS DE BASE DE DATOS Y RENDIMIENTO OPTIMIZADO
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> _reportesFms = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // Variables cacheadas para evitar recálculos en el método build()
  List<String> _operadoresProcesados = [];
  Map<String, List<int>> _matrizBase = {};
  Map<String, int> _totalesOperadorBase = {};
  List<int> _totalesMesesBase = List<int>.filled(12, 0);
  int _granTotalBase = 0;
  String _mesPicoBase = 'N/A';
  int _maxMesValorBase = 0;

  final List<String> _meses = [
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

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  // ---------------------------------------------------------------------------
  // 🔌 CONSULTA A LA BASE DE DATOS
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

      Set<int> anosSet = {};
      for (var d in dataLista) {
        DateTime dt = d['fecha_dt'] as DateTime;
        anosSet.add(dt.year);
      }
      if (!anosSet.contains(DateTime.now().year)) {
        anosSet.add(DateTime.now().year);
      }
      List<int> anosOrdenados = anosSet.toList()..sort((a, b) => b.compareTo(a));

      _listaAnos = anosOrdenados;
      if (!_listaAnos.contains(_anoSeleccionado)) {
        _anoSeleccionado = _listaAnos.first;
      }
      _reportesFms = dataLista;

      // Llamamos al motor de procesamiento (él se encarga de quitar el _isLoading)
      _procesarMatrizBase();

    } catch (e) {
      setState(() {
        _errorMessage = 'Error al consultar tendencias FMS: $e';
        _isLoading = false;
      });
    }
  }

  String _normalizarEvento(String raw) {
    String ev = raw.toUpperCase().trim();
    ev = ev.replaceAll('Á', 'A').replaceAll('É', 'E').replaceAll('Í', 'I').replaceAll('Ó', 'O').replaceAll('Ú', 'U');
    if (ev.contains('ACELERACI')) return 'ACELERACION';
    if (ev.contains('IMPACTO')) return 'IMPACTOS';
    if (ev.contains('FRENAD')) return 'FRENADAS';
    return ev;
  }

  String _formatearFechaLimpia(dynamic fechaRaw) {
    if (fechaRaw == null) return '';
    String f = fechaRaw.toString().trim();
    if (f.contains('T')) return f.split('T')[0];
    if (f.contains(' ')) return f.split(' ')[0];
    return f;
  }

  // ---------------------------------------------------------------------------
  // 📊 MOTOR DE RENDIMIENTO: PROCESAR MATRIZ (Solo corre al cambiar dropdowns o BD)
  // ---------------------------------------------------------------------------
  void _procesarMatrizBase() {
    final reportesFiltrados = _reportesFms.where((item) {
      DateTime dt = item['fecha_dt'] as DateTime;
      if (dt.year != _anoSeleccionado) return false;

      // FILTRO ESTRICTO: Eliminar 'SIN ASIGNAR', 'SIN NOMBRE' o vacíos
      String op = (item['nombre'] ?? '').toString().trim().toUpperCase();
      if (op.isEmpty || op == 'SIN ASIGNAR' || op == 'SIN NOMBRE') return false;

      if (_eventoSeleccionado != 'TODOS') {
        String ev = _normalizarEvento(item['evento']?.toString() ?? '');
        if (ev != _eventoSeleccionado) return false;
      }
      return true;
    }).toList();

    Set<String> operadoresSet = {};
    for (var r in reportesFiltrados) {
      String op = (r['nombre'] ?? '').toString().trim().toUpperCase();
      operadoresSet.add(op);
    }
    List<String> todosOperadores = operadoresSet.toList();

    _matrizBase = {};
    _totalesOperadorBase = {};
    _totalesMesesBase = List<int>.filled(12, 0);
    _granTotalBase = 0;

    for (var op in todosOperadores) {
      _matrizBase[op] = List<int>.filled(12, 0);
      _totalesOperadorBase[op] = 0;
    }

    for (var r in reportesFiltrados) {
      String op = (r['nombre'] ?? '').toString().trim().toUpperCase();
      DateTime dt = r['fecha_dt'] as DateTime;
      int mesIdx = dt.month - 1;

      _matrizBase[op]![mesIdx]++;
      _totalesOperadorBase[op] = (_totalesOperadorBase[op] ?? 0) + 1;
      _totalesMesesBase[mesIdx]++;
      _granTotalBase++;
    }

    _maxMesValorBase = 0;
    _mesPicoBase = 'N/A';
    for (int m = 0; m < 12; m++) {
      if (_totalesMesesBase[m] > _maxMesValorBase) {
        _maxMesValorBase = _totalesMesesBase[m];
        _mesPicoBase = _meses[m];
      }
    }

    // Aplica la búsqueda y orden y actualiza la vista
    _aplicarBusquedaYOrden();
  }

  // ---------------------------------------------------------------------------
  // 🔍 MOTOR DE RENDIMIENTO: BÚSQUEDA Y ORDEN (Solo corre al tipear o hacer clic en cabeceras)
  // ---------------------------------------------------------------------------
  void _aplicarBusquedaYOrden() {
    List<String> operadoresActivos = _totalesOperadorBase.keys.where((op) {
      bool tieneEventos = (_totalesOperadorBase[op] ?? 0) > 0;
      bool coincideBusqueda = _filtroTextoOperador.isEmpty ||
          op.contains(_filtroTextoOperador.trim().toUpperCase());
      return tieneEventos && coincideBusqueda;
    }).toList();

    operadoresActivos.sort((a, b) {
      if (_columnaOrden == 12) {
        int valA = _totalesOperadorBase[a] ?? 0;
        int valB = _totalesOperadorBase[b] ?? 0;
        return _ordenAscendente ? valA.compareTo(valB) : valB.compareTo(valA);
      } else if (_columnaOrden >= 0 && _columnaOrden < 12) {
        int valA = _matrizBase[a]?[_columnaOrden] ?? 0;
        int valB = _matrizBase[b]?[_columnaOrden] ?? 0;
        return _ordenAscendente ? valA.compareTo(valB) : valB.compareTo(valA);
      } else {
        return _ordenAscendente ? a.compareTo(b) : b.compareTo(a);
      }
    });

    setState(() {
      _operadoresProcesados = operadoresActivos;
      _isLoading = false; // Finaliza la carga de UI
    });
  }

  void _cambiarOrden(int columna) {
    if (_columnaOrden == columna) {
      _ordenAscendente = !_ordenAscendente;
    } else {
      _columnaOrden = columna;
      _ordenAscendente = false;
    }
    _aplicarBusquedaYOrden();
  }

  // ---------------------------------------------------------------------------
  // 💬 VENTANA MODAL CON TABLA DE EVENTOS AL DAR CLIC
  // ---------------------------------------------------------------------------
  void _mostrarModalDetalleEventos({
    required String operador,
    int? mesIdx,
    required String periodoTexto,
  }) {
    final eventosDetalle = _reportesFms.where((item) {
      DateTime dt = item['fecha_dt'] as DateTime;
      if (dt.year != _anoSeleccionado) return false;

      // Misma lógica estricta para ignorar 'SIN ASIGNAR' en el modal
      String op = (item['nombre'] ?? '').toString().trim().toUpperCase();
      if (op.isEmpty || op == 'SIN ASIGNAR' || op == 'SIN NOMBRE') return false;

      if (operador != 'TOTAL GENERAL') {
        if (op != operador.trim().toUpperCase()) return false;
      }

      if (mesIdx != null) {
        if (dt.month != (mesIdx + 1)) return false;
      }

      if (_eventoSeleccionado != 'TODOS') {
        String ev = _normalizarEvento(item['evento']?.toString() ?? '');
        if (ev != _eventoSeleccionado) return false;
      }

      return true;
    }).toList();

    eventosDetalle.sort((a, b) {
      DateTime dtA = a['fecha_dt'] as DateTime;
      DateTime dtB = b['fecha_dt'] as DateTime;
      return dtB.compareTo(dtA);
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: 950,
            constraints: const BoxConstraints(maxHeight: 650),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.person_pin_rounded, color: Color(0xFFDC2626), size: 22),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Detalle de Eventos Registrados',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$operador • $periodoTexto • $_anoSeleccionado (${eventosDetalle.length} Registros)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 24),
                    ),
                  ],
                ),
                const Divider(height: 24, thickness: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: eventosDetalle.isEmpty
                      ? const Center(
                    child: Text(
                      'No se encontraron registros para este periodo.',
                      style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  )
                      : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: MaterialStateProperty.all(const Color(0xFF1E293B)),
                            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            columns: const [
                              DataColumn(label: Text('FECHA')),
                              DataColumn(label: Text('HORA')),
                              DataColumn(label: Text('OPERADOR')), // Cambiado a OPERADOR
                              DataColumn(label: Text('TIPO DE EVENTO')),
                              DataColumn(label: Text('MÁQUINA')),
                              DataColumn(label: Text('ÁREA')),
                            ],
                            rows: eventosDetalle.map((e) {
                              return DataRow(cells: [
                                DataCell(Text(_formatearFechaLimpia(e['fecha']))),
                                DataCell(Text(e['hora']?.toString() ?? '-')),
                                DataCell(Text(e['nombre']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))), // Extrae nombre del operador
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      e['evento']?.toString() ?? '-',
                                      style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ),
                                ),
                                DataCell(Text(e['maquina']?.toString() ?? '-')),
                                DataCell(Text(e['area']?.toString() ?? '-')),
                              ]);
                            }).toList(),
                          ),
                        ),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: Center(
          child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );
    }

    // Leemos los datos directamente de la caché optimizada
    final List<String> operadores = _operadoresProcesados;
    final Map<String, List<int>> matriz = _matrizBase;
    final Map<String, int> totalesOperador = _totalesOperadorBase;
    final List<int> totalesMeses = _totalesMesesBase;
    final int granTotal = _granTotalBase;
    final String mesPico = _mesPicoBase;
    final int maxMesValor = _maxMesValorBase;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBarraFiltros(),
            const SizedBox(height: 20),
            _buildKpisResumen(granTotal, operadores.length, mesPico, maxMesValor),
            const SizedBox(height: 20),
            _buildBarraConvenciones(operadores.length),
            const SizedBox(height: 16),
            if (operadores.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Center(
                  child: Text(
                    '🛡️ No hay operadores con incidentes registrados para el año y filtros seleccionados.',
                    style: TextStyle(fontSize: 15, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else
              _buildTablaTendencias(operadores, matriz, totalesOperador, totalesMeses, granTotal),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔍 1. BARRA SUPERIOR DE FILTROS
  // ---------------------------------------------------------------------------
  Widget _buildBarraFiltros() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AÑO EVALUADO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _anoSeleccionado,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                    items: _listaAnos.map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _anoSeleccionado = val;
                        _procesarMatrizBase(); // Dispara cálculo
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('TIPO DE EVENTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _eventoSeleccionado,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                    items: _listaEventos.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _eventoSeleccionado = val;
                        _procesarMatrizBase(); // Dispara cálculo
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(
            width: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('BUSCAR OPERADOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
                const SizedBox(height: 6),
                SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (val) {
                      _filtroTextoOperador = val;
                      _aplicarBusquedaYOrden(); // Búsqueda instantánea
                    },
                    decoration: InputDecoration(
                      hintText: 'Filtrar por nombre...',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626))),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _cargarDatosBD,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('ACTUALIZAR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📈 2. TARJETAS KPI RESUMEN
  // ---------------------------------------------------------------------------
  Widget _buildKpisResumen(int totalAno, int opsActivos, String mesPico, int maxMesValor) {
    return LayoutBuilder(builder: (context, constraints) {
      bool isWide = constraints.maxWidth > 900;
      List<Widget> cards = [
        _buildKpiCard('TOTAL INCIDENTES EN EL AÑO', '$totalAno', const Color(0xFFDC2626), Icons.warning_amber_rounded),
        _buildKpiCard('OPERADORES CON NOVEDAD', '$opsActivos', const Color(0xFF2563EB), Icons.engineering_rounded),
        _buildKpiCard('MES DE MAYOR INCIDENCIA', '$mesPico ($maxMesValor)', const Color(0xFFD97706), Icons.trending_up_rounded),
      ];

      if (isWide) {
        return Row(
          children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))).toList(),
        );
      } else {
        return Column(
          children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c)).toList(),
        );
      }
    });
  }

  Widget _buildKpiCard(String titulo, String valor, Color colorPrincipal, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorPrincipal.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: colorPrincipal.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: colorPrincipal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icono, color: colorPrincipal, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🏷️ 3. CONVENCIONES VISUALES
  // ---------------------------------------------------------------------------
  Widget _buildBarraConvenciones(int totalMostrados) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('TENDENCIA:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Color(0xFF475569), letterSpacing: 0.5)),
              const SizedBox(width: 14),
              _buildBadgeConvencion('Disminuyó eventos (Mejora)', const Color(0xFFDCFCE7), const Color(0xFF15803D), Icons.arrow_downward_rounded),
              const SizedBox(width: 12),
              _buildBadgeConvencion('Aumentó eventos (Alerta)', const Color(0xFFFEE2E2), const Color(0xFFB91C1C), Icons.arrow_upward_rounded),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.touch_app_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                'Clic en cualquier número para ver detalle • $totalMostrados operadores',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeConvencion(String texto, Color bg, Color textCol, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textCol, size: 14),
          const SizedBox(width: 4),
          Text(texto, style: TextStyle(color: textCol, fontWeight: FontWeight.w800, fontSize: 11)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 4. TABLA MATRIZ CON CELDAS CLICKEABLES
  // ---------------------------------------------------------------------------
  Widget _buildTablaTendencias(
      List<String> operadores,
      Map<String, List<int>> matriz,
      Map<String, int> totalesOperador,
      List<int> totalesMeses,
      int granTotal,
      ) {
    const double colOperadorWidth = 280;
    const double colMesWidth = 112;
    const double colTotalWidth = 110;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ENCABEZADO AZUL/OSCURO
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Row(
                  children: [
                    _buildCeldaCabecera('OPERADOR', colOperadorWidth, -1, textAlign: TextAlign.left),
                    ..._meses.asMap().entries.map((e) => _buildCeldaCabecera(e.value, colMesWidth, e.key)),
                    _buildCeldaCabecera('TOTAL', colTotalWidth, 12),
                  ],
                ),
              ),

              // FILAS DE OPERADORES
              ...operadores.asMap().entries.map((entry) {
                int index = entry.key;
                String op = entry.value;
                List<int> valoresMeses = matriz[op] ?? List<int>.filled(12, 0);
                int totalOp = totalesOperador[op] ?? 0;
                bool isEven = index % 2 == 0;

                return Container(
                  color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                  child: Row(
                    children: [
                      Container(
                        width: colOperadorWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        alignment: Alignment.centerLeft,
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: index < 3 ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: index < 3 ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                op.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF1E293B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...List.generate(12, (mesIdx) {
                        int valorActual = valoresMeses[mesIdx];
                        int? valorAnterior = mesIdx > 0 ? valoresMeses[mesIdx - 1] : null;
                        return _buildCeldaMesBadge(
                          valorActual,
                          valorAnterior,
                          colMesWidth,
                          mesIdx: mesIdx,
                          onTap: valorActual > 0
                              ? () => _mostrarModalDetalleEventos(
                            operador: op,
                            mesIdx: mesIdx,
                            periodoTexto: _meses[mesIdx],
                          )
                              : null,
                        );
                      }),
                      // Celda TOTAL por operador
                      Container(
                        width: colTotalWidth,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
                        child: totalOp > 0
                            ? Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _mostrarModalDetalleEventos(
                              operador: op,
                              mesIdx: null,
                              periodoTexto: 'TOTAL ACUMULADO',
                            ),
                            hoverColor: Colors.black.withOpacity(0.04),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              child: Tooltip(
                                message: 'Ver eventos totales del operador',
                                waitDuration: const Duration(milliseconds: 200),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$totalOp',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                            : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$totalOp',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // FILA TOTAL GENERAL
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  border: Border(top: BorderSide(color: Color(0xFFCBD5E1), width: 1.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: colOperadorWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'TOTAL GENERAL',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A), letterSpacing: 0.5),
                      ),
                    ),
                    ...List.generate(12, (mesIdx) {
                      int valorMes = totalesMeses[mesIdx];
                      int? valorAnteriorMes = mesIdx > 0 ? totalesMeses[mesIdx - 1] : null;
                      return _buildCeldaMesBadge(
                        valorMes,
                        valorAnteriorMes,
                        colMesWidth,
                        esTotal: true,
                        mesIdx: mesIdx,
                        onTap: valorMes > 0
                            ? () => _mostrarModalDetalleEventos(
                          operador: 'TOTAL GENERAL',
                          mesIdx: mesIdx,
                          periodoTexto: _meses[mesIdx],
                        )
                            : null,
                      );
                    }),
                    // Gran Total General
                    Container(
                      width: colTotalWidth,
                      alignment: Alignment.center,
                      child: granTotal > 0
                          ? Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _mostrarModalDetalleEventos(
                            operador: 'TOTAL GENERAL',
                            mesIdx: null,
                            periodoTexto: 'AÑO COMPLETO',
                          ),
                          hoverColor: Colors.black.withOpacity(0.04),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                            child: Tooltip(
                              message: 'Ver eventos de todo el año',
                              waitDuration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E3A8A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$granTotal',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                          : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A8A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$granTotal',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🧩 CELDAS INDIVIDUALES DE LA TABLA
  // ---------------------------------------------------------------------------
  Widget _buildCeldaCabecera(String titulo, double width, int idColumna, {TextAlign textAlign = TextAlign.center}) {
    bool isSorted = _columnaOrden == idColumna;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _cambiarOrden(idColumna),
        hoverColor: Colors.black12,
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          alignment: textAlign == TextAlign.left ? Alignment.centerLeft : Alignment.center,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: Colors.white24)),
          ),
          child: Row(
            mainAxisAlignment: textAlign == TextAlign.left ? MainAxisAlignment.start : MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  titulo,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 4),
                Icon(
                  _ordenAscendente ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCeldaMesBadge(
      int valorActual,
      int? valorAnterior,
      double width, {
        bool esTotal = false,
        required int mesIdx,
        VoidCallback? onTap,
      }) {
    bool esMesFuturo = _anoSeleccionado == DateTime.now().year && (mesIdx + 1) > DateTime.now().month;

    if (esMesFuturo || valorActual == 0) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        alignment: Alignment.center,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
        child: const Text('-', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontWeight: FontWeight.bold)),
      );
    }

    Color bgPill = const Color(0xFFF1F5F9);
    Color colorTexto = const Color(0xFF334155);
    IconData? icono;

    if (valorAnterior != null) {
      if (valorActual < valorAnterior) {
        bgPill = const Color(0xFFDCFCE7);
        colorTexto = const Color(0xFF15803D);
        icono = Icons.arrow_downward_rounded;
      } else if (valorActual > valorAnterior) {
        bgPill = const Color(0xFFFEE2E2);
        colorTexto = const Color(0xFFB91C1C);
        icono = Icons.arrow_upward_rounded;
      }
    }

    Widget pillContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgPill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$valorActual',
            style: TextStyle(
              fontSize: esTotal ? 13 : 12,
              fontWeight: FontWeight.w900,
              color: colorTexto,
            ),
          ),
          if (icono != null) ...[
            const SizedBox(width: 3),
            Icon(icono, color: colorTexto, size: 13),
          ],
        ],
      ),
    );

    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: onTap != null
          ? Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: Colors.black.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Tooltip(
              message: 'Ver eventos de este mes',
              waitDuration: const Duration(milliseconds: 200),
              child: pillContent,
            ),
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: pillContent,
      ),
    );
  }
}