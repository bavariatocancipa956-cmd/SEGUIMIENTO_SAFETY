import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:html' as html;
import 'api_service.dart';

class DashboardFmsAreasScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;

  const DashboardFmsAreasScreen({super.key, this.onToggleSidebar});

  @override
  State<DashboardFmsAreasScreen> createState() => _DashboardFmsAreasScreenState();
}

class _DashboardFmsAreasScreenState extends State<DashboardFmsAreasScreen> {
  // ---------------------------------------------------------------------------
  // 📸 LLAVE PARA CAPTURA DE PANTALLA Y ESTADO FOTO
  // ---------------------------------------------------------------------------
  final GlobalKey _dashboardKey = GlobalKey();
  bool _modoFoto = false;

  // ---------------------------------------------------------------------------
  // 📅 FILTROS DE MES Y FECHA ESPECÍFICA
  // ---------------------------------------------------------------------------
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;
  DateTime? _fechaEspecifica; // Si es null, muestra todo el mes.

  final List<String> _nombresMeses = [
    'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
    'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE'
  ];

  // ---------------------------------------------------------------------------
  // 🌐 ESTADOS DE BASE DE DATOS
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> _reportesFms = [];
  List<String> _listaAreas = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _cargarDatosBD();
  }

  // ---------------------------------------------------------------------------
  // 🗓️ FUNCIÓN AUXILIAR NOMBRES DE MESES
  // ---------------------------------------------------------------------------
  String _obtenerNombreMes(int mes, {bool corto = false}) {
    const mesesCortos = [
      'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
      'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'
    ];
    if (mes < 1 || mes > 12) return '';
    return corto ? mesesCortos[mes - 1] : _nombresMeses[mes - 1];
  }

  // ---------------------------------------------------------------------------
  // 🛠️ NORMALIZACIÓN DE ÁREAS (UNIFICA CARPAS)
  // ---------------------------------------------------------------------------
  String _normalizarArea(String raw) {
    String ar = raw.toUpperCase().trim();
    if (ar.contains('CARPA')) {
      return 'CARPAS';
    }
    return ar;
  }

  // ---------------------------------------------------------------------------
  // 🔌 CONSUMO DE API Y PREPROCESAMIENTO
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

      Set<String> areasSet = {};
      for (var d in dataCalculada) {
        String ar = _normalizarArea(d['area']?.toString() ?? '');
        d['area_normalizada'] = ar;
        if (ar.isNotEmpty) areasSet.add(ar);
      }

      setState(() {
        _reportesFms = dataCalculada;
        _listaAreas = areasSet.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al consultar datos FMS: $e';
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
        row['reinc_mes_ant'] = 0;
        row['reinc_ano'] = 0;
        continue;
      }
      String nombre = row['nombre'].toString();
      DateTime d = row['fecha_dt'] as DateTime;
      DateTime dAnt = DateTime(d.year, d.month - 1);

      String keyAno = "${nombre}_${d.year}";
      String keyMes = "${nombre}_${d.year}_${d.month}";
      String keyMesAnt = "${nombre}_${dAnt.year}_${dAnt.month}";

      row['reinc_mes'] = conteoMes[keyMes] ?? 0;
      row['reinc_mes_ant'] = conteoMes[keyMesAnt] ?? 0;
      row['reinc_ano'] = conteoAno[keyAno] ?? 0;
    }

    return dataRows;
  }

  String _normalizarEvento(String raw) {
    String ev = raw.toUpperCase().trim();
    ev = ev.replaceAll('Á', 'A').replaceAll('É', 'E').replaceAll('Í', 'I').replaceAll('Ó', 'O').replaceAll('Ú', 'U');
    if (ev.contains('ACELERACI')) return 'ACELERACION';
    if (ev.contains('IMPACTO')) return 'IMPACTOS';
    if (ev.contains('FRENAD')) return 'FRENADAS BRUSCAS';
    return ev;
  }

  // ---------------------------------------------------------------------------
  // 📸 FUNCIÓN PARA CAPTURAR PANTALLA INTELIGENTE
  // ---------------------------------------------------------------------------
  Future<void> _tomarFoto() async {
    setState(() {
      _modoFoto = true;
    });

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📸 Preparando reporte de áreas con incidentes...'),
          backgroundColor: Color(0xFF475569),
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 600));

      RenderRepaintBoundary boundary = _dashboardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        Uint8List pngBytes = byteData.buffer.asUint8List();
        final blob = html.Blob([pngBytes], 'image/png');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute("download", "Reporte_Novedades_FMS_${DateTime.now().millisecondsSinceEpoch}.png")
          ..click();
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Reporte de incidentes descargado con éxito'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error: El reporte es muy largo. Intenta reducir el zoom de tu navegador (Ctrl + -) y vuelve a capturar.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _modoFoto = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🔄 FILTRADO POR MES O DÍA ESPECÍFICO
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> get _reportesFiltrados {
    return _reportesFms.where((item) {
      try {
        DateTime fechaItem = item['fecha_dt'] as DateTime;

        // Si hay una fecha específica seleccionada, filtramos solo por ese día exacto
        if (_fechaEspecifica != null) {
          return fechaItem.year == _fechaEspecifica!.year &&
              fechaItem.month == _fechaEspecifica!.month &&
              fechaItem.day == _fechaEspecifica!.day;
        }
        // Si no, filtramos por todo el mes seleccionado
        else {
          return fechaItem.year == _anioSeleccionado &&
              fechaItem.month == _mesSeleccionado;
        }
      } catch (e) {
        return false;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F3F9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFDC2626)),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F3F9),
        body: Center(
          child: Text(_errorMessage, style: const TextStyle(color: Colors.red, fontSize: 16)),
        ),
      );
    }

    final datosDelRango = _reportesFiltrados;

    List<String> areasAMostrar = _listaAreas.where((area) {
      int incidentesEnArea = datosDelRango.where((e) => e['area_normalizada'] == area).length;
      if (_modoFoto && incidentesEnArea == 0) {
        return false;
      }
      return true;
    }).toList();

    areasAMostrar.sort((a, b) {
      int countA = datosDelRango.where((e) => e['area_normalizada'] == a).length;
      int countB = datosDelRango.where((e) => e['area_normalizada'] == b).length;

      if (countA > 0 && countB == 0) return -1;
      if (countA == 0 && countB > 0) return 1;
      return countB.compareTo(countA);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: RepaintBoundary(
          key: _dashboardKey,
          child: Container(
            color: const Color(0xFFF1F3F9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBarraFiltrosMes(),
                const SizedBox(height: 24),

                if (_listaAreas.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: const Center(
                      child: Text('No hay áreas registradas en el sistema.', style: TextStyle(fontSize: 16, color: Colors.blueGrey)),
                    ),
                  )
                else if (areasAMostrar.isEmpty && _modoFoto)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981), width: 2),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.shield_rounded, size: 64, color: Color(0xFF10B981)),
                        SizedBox(height: 16),
                        Text('CERO INCIDENTES REPORTADOS EN EL PERIODO SELECCIONADO',
                          style: TextStyle(fontSize: 20, color: Color(0xFF047857), fontWeight: FontWeight.w900),
                        ),
                        Text('100% DE CUMPLIMIENTO EN TODAS LAS ÁREAS',
                          style: TextStyle(fontSize: 16, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: areasAMostrar.map((area) {
                      return _buildBloqueCompletoArea(area, datosDelRango);
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎛️ NUEVA BARRA DE FILTROS: MES / AÑO / DÍA ESPECÍFICO
  // ---------------------------------------------------------------------------
  Widget _buildBarraFiltrosMes() {
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
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          // 1. Selector de Mes
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('MES A EVALUAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _mesSeleccionado,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                    items: List.generate(12, (index) {
                      return DropdownMenuItem(
                        value: index + 1,
                        child: Text(_nombresMeses[index]),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _mesSeleccionado = val;
                          _fechaEspecifica = null; // Resetea el día si cambia de mes
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          // 2. Selector de Año
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AÑO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _anioSeleccionado,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                    items: [2024, 2025, 2026, 2027, 2028].map((anio) {
                      return DropdownMenuItem(
                        value: anio,
                        child: Text(anio.toString()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _anioSeleccionado = val;
                          _fechaEspecifica = null;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          // 3. Filtro Opcional de Fecha Específica
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('FILTRAR DÍA EXACTO (OPCIONAL)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  // Limita el calendario para que solo se pueda elegir un día del mes y año seleccionados
                  DateTime primerDiaDelMes = DateTime(_anioSeleccionado, _mesSeleccionado, 1);
                  DateTime ultimoDiaDelMes = DateTime(_anioSeleccionado, _mesSeleccionado + 1, 0);

                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _fechaEspecifica ?? primerDiaDelMes,
                    firstDate: primerDiaDelMes,
                    lastDate: ultimoDiaDelMes,
                  );
                  if (picked != null) {
                    setState(() => _fechaEspecifica = picked);
                  }
                },
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fechaEspecifica != null
                            ? "${_fechaEspecifica!.day.toString().padLeft(2, '0')}/${_fechaEspecifica!.month.toString().padLeft(2, '0')}/${_fechaEspecifica!.year}"
                            : "Ver todo el mes",
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _fechaEspecifica != null ? const Color(0xFFDC2626) : const Color(0xFF334155)
                        ),
                      ),
                      if (_fechaEspecifica != null)
                        GestureDetector(
                          onTap: () => setState(() => _fechaEspecifica = null),
                          child: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                        )
                      else
                        const Icon(Icons.calendar_month_rounded, size: 18, color: Colors.blueGrey),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Botones de acción
          ElevatedButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.shield_rounded, size: 20),
            label: const Text('EVALUAR RIESGO', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _cargarDatosBD,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('RECARGAR BD', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF475569),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _tomarFoto,
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text('CAPTURAR REPORTE', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🏢 BLOQUE DE ÁREA
  // ---------------------------------------------------------------------------
  Widget _buildBloqueCompletoArea(String area, List<Map<String, dynamic>> datosDelRango) {
    // La referencia SIEMPRE es el mes seleccionado, sin importar si filtramos un solo día.
    DateTime mesReferencia = DateTime(_anioSeleccionado, _mesSeleccionado);

    final todosLosDelArea = _reportesFms.where((e) => e['area_normalizada'] == area).toList();
    final registrosRangoArea = datosDelRango.where((e) => e['area_normalizada'] == area).toList();
    bool tieneActividad = registrosRangoArea.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tieneActividad ? const Color(0xFFDC2626) : const Color(0xFFE2E8F0),
          width: tieneActividad ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: tieneActividad ? const Color(0xFFDC2626).withOpacity(0.08) : Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: tieneActividad ? const Color(0xFF0F172A) : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      tieneActividad ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                      color: tieneActividad ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      area.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: tieneActividad ? const Color(0xFFDC2626) : const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tieneActividad
                        ? '🚨 ALERTA: ${registrosRangoArea.length} INCIDENTE(S)'
                        : '🛡️ ÁREA CONFORME / SIN INCIDENTES',
                    style: TextStyle(
                      color: tieneActividad ? Colors.white : const Color(0xFF34D399),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildTarjetasResumenArea(todosLosDelArea, registrosRangoArea, mesReferencia),
          const SizedBox(height: 24),

          _buildTablaAreaCentrada(registrosRangoArea, mesReferencia),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 📊 TARJETAS DE EVENTOS LIMPIAS
  // ---------------------------------------------------------------------------
  Widget _buildTarjetasResumenArea(
      List<Map<String, dynamic>> todosDelArea,
      List<Map<String, dynamic>> rangoArea,
      DateTime mesReferencia,
      ) {
    List<String> tiposStandard = ['FRENADAS BRUSCAS', 'ACELERACION', 'IMPACTOS'];

    String nombreMesActual = _obtenerNombreMes(mesReferencia.month);
    DateTime mesAnteriorDt = DateTime(mesReferencia.year, mesReferencia.month - 1);
    String nombreMesAnterior = _obtenerNombreMes(mesAnteriorDt.month);

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWide = constraints.maxWidth > 800;

        List<Widget> cards = tiposStandard.map((tipo) {
          // Incidentes recientes cuenta lo que haya en el filtro activo (Todo el mes O un día específico)
          int countRango = rangoArea.where((e) => _normalizarEvento(e['evento']?.toString() ?? '') == tipo).length;

          int countMes = todosDelArea.where((e) {
            DateTime d = e['fecha_dt'] as DateTime;
            return _normalizarEvento(e['evento']?.toString() ?? '') == tipo &&
                d.year == mesReferencia.year &&
                d.month == mesReferencia.month;
          }).length;

          int countMesAnterior = todosDelArea.where((e) {
            DateTime d = e['fecha_dt'] as DateTime;
            return _normalizarEvento(e['evento']?.toString() ?? '') == tipo &&
                d.year == mesAnteriorDt.year &&
                d.month == mesAnteriorDt.month;
          }).length;

          int countAno = todosDelArea.where((e) {
            DateTime d = e['fecha_dt'] as DateTime;
            return _normalizarEvento(e['evento']?.toString() ?? '') == tipo && d.year == mesReferencia.year;
          }).length;

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: countRango > 0 ? const Color(0xFFFEF2F2) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: countRango > 0 ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                width: countRango > 0 ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              children: [
                Text(
                  tipo,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: countRango > 0 ? const Color(0xFF991B1B) : const Color(0xFF1E293B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSubMetrica(
                        _fechaEspecifica != null ? 'DIA ${_fechaEspecifica!.day}' : 'TOTAL MES',
                        '$countRango',
                        const Color(0xFFDC2626)
                    ),
                    _buildSubMetrica(nombreMesActual, '$countMes', const Color(0xFFD97706)),
                    _buildSubMetrica(nombreMesAnterior, '$countMesAnterior', const Color(0xFF059669)),
                    _buildSubMetrica('ACUMULADO AÑO', '$countAno', const Color(0xFF7C3AED)),
                  ],
                ),
              ],
            ),
          );
        }).toList();

        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c))).toList(),
          );
        } else {
          return Column(
            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
          );
        }
      },
    );
  }

  Widget _buildSubMetrica(String titulo, String valor, Color colorValor) {
    bool esCero = valor == '0';
    return Column(
      children: [
        Text(titulo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        Text(
          valor,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: esCero ? const Color(0xFF94A3B8) : colorValor,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 📋 TABLA DE INCIDENTES
  // ---------------------------------------------------------------------------
  Widget _buildTablaAreaCentrada(List<Map<String, dynamic>> registrosArea, DateTime mesReferencia) {
    String mesActualCorto = _obtenerNombreMes(mesReferencia.month, corto: true);
    DateTime mesAntDt = DateTime(mesReferencia.year, mesReferencia.month - 1);
    String mesAntCorto = _obtenerNombreMes(mesAntDt.month, corto: true);

    List<String> headers = ['ÁREA', 'OPERADOR', 'SUPERVISOR', 'MÁQUINA', 'TIPO DE EVENTO', 'ORIGEN OPM', 'EV. $mesActualCorto', 'EV. $mesAntCorto', 'EVENTOS AÑO'];
    List<double> minWidths = [160, 240, 200, 100, 160, 110, 110, 120, 110];

    if (registrosArea.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: const Center(
          child: Text('🛡️ No se registraron incidentes ni novedades de seguridad para esta área en la fecha seleccionada.',
            style: TextStyle(color: Color(0xFF059669), fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            double totalWidth = minWidths.fold(0, (s, w) => s + w);
            List<double> finalWidths = List.from(minWidths);

            if (totalWidth < constraints.maxWidth) {
              double extra = (constraints.maxWidth - totalWidth) / headers.length;
              for (int i = 0; i < finalWidths.length; i++) finalWidths[i] += extra;
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        alignment: Alignment.center,
                        child: Text(headers[i], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5)),
                      );
                    }),
                  ),
                ),
                Column(
                  children: registrosArea.map((item) {
                    List<String> valoresFila = [
                      (item['area_normalizada'] ?? '').toString(),
                      (item['nombre'] ?? '').toString(),
                      (item['supervisor'] ?? '').toString(),
                      (item['maquina'] ?? '').toString(),
                      (item['evento'] ?? '').toString(),
                      (item['origen_opm'] ?? '').toString(),
                      '${item['reinc_mes'] ?? 0}',
                      '${item['reinc_mes_ant'] ?? 0}',
                      '${item['reinc_ano'] ?? 0}',
                    ];

                    return Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                      child: Row(
                        children: List.generate(valoresFila.length, (i) {
                          bool isEvento = headers[i] == 'TIPO DE EVENTO';
                          bool isOperador = headers[i] == 'OPERADOR';
                          bool isReinc = headers[i].contains('EVENTOS') || headers[i].contains('EV.');

                          return Container(
                            width: finalWidths[i],
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            alignment: Alignment.center,
                            child: Text(
                              valoresFila[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: (isOperador || isEvento || isReinc) ? FontWeight.bold : FontWeight.w500,
                                color: isEvento ? const Color(0xFFDC2626) : (isReinc && valoresFila[i] != '0' ? const Color(0xFFB91C1C) : Colors.black87),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: totalWidth, child: tableContent),
            );
          },
        ),
      ),
    );
  }
}