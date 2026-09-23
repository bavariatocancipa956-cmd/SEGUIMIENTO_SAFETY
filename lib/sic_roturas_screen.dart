import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;

class SicRoturasScreen extends StatefulWidget {
  final VoidCallback? onToggleSidebar;
  final bool isFullScreen;

  // Variables para heredar los filtros al abrir Modo TV
  final DateTime? initFecha;
  final String? initZona;
  final String? initTurno;
  final String? initWqi;
  final String? initSupervisor;

  const SicRoturasScreen({
    super.key,
    this.onToggleSidebar,
    this.isFullScreen = false,
    this.initFecha,
    this.initZona,
    this.initTurno,
    this.initWqi,
    this.initSupervisor,
  });

  @override
  State<SicRoturasScreen> createState() => _SicRoturasScreenState();
}

class _SicRoturasScreenState extends State<SicRoturasScreen> {
  static const String _apiUrl = 'https://plantatocancipa.site/api/v1/db_logistica/consultar/roturas/reportes_rotura';
  static const String _apiKey = 'PlantaLogistica2026*';

  bool _cargando = true;
  String? _mensajeError;
  String _ultimaActualizacion = '';

  List<Map<String, dynamic>> _todosLosReportes = [];

  // Filtros (Se inicializan con lo que venga del Modo TV o por defecto)
  late DateTime _fechaSeleccionada;
  late String _turnoSeleccionado;
  late String _supervisorSeleccionado;
  late String _zonaSeleccionada;
  late String _wqiSeleccionado;

  List<String> _listaTurnos = ['Todos'];
  List<String> _listaSupervisores = ['Todos'];
  List<String> _listaZonas = ['Todas'];
  List<String> _listaWqi = ['Todos'];

  // Meta de roturas permitidas por hora
  final double _metaPorHora = 50.0;

  // Datos procesados
  Map<int, double> _roturasPorHora = {};
  List<Map<String, dynamic>> _eventosFiltrados = [];
  Map<String, double> _roturasPorOperador = {};

  // Controladores y Timers
  Timer? _timerActualizacion;
  final ScrollController _scrollOperadores = ScrollController();
  final ScrollController _scrollEventos = ScrollController();

  @override
  void initState() {
    super.initState();

    // Asignar los filtros heredados si existen, si no, poner valores por defecto
    _fechaSeleccionada = widget.initFecha ?? DateTime.now();
    _zonaSeleccionada = widget.initZona ?? 'Todas';
    _turnoSeleccionado = widget.initTurno ?? 'Todos';
    _wqiSeleccionado = widget.initWqi ?? 'Todos';
    _supervisorSeleccionado = widget.initSupervisor ?? 'Todos';

    _cargarDatosBD();

    // Iniciar auto-refresco cada 5 minutos
    _timerActualizacion = Timer.periodic(const Duration(minutes: 5), (timer) {
      _cargarDatosBD();
    });

    // Iniciar movimiento perpetuo de las tablas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarScrollPerpetuo(_scrollOperadores, velocidad: 35);
      _iniciarScrollPerpetuo(_scrollEventos, velocidad: 25);
    });
  }

  @override
  void dispose() {
    _timerActualizacion?.cancel();
    _scrollOperadores.dispose();
    _scrollEventos.dispose();
    super.dispose();
  }

  // Lógica de Movimiento Perpetuo (Auto-Scroll)
  void _iniciarScrollPerpetuo(ScrollController controller, {required double velocidad}) async {
    await Future.delayed(const Duration(seconds: 3));
    while (mounted) {
      if (controller.hasClients && controller.position.maxScrollExtent > 0) {
        double maxExtent = controller.position.maxScrollExtent;
        int durationSeconds = (maxExtent / velocidad).round();

        // Bajar lentamente
        await controller.animateTo(
          maxExtent,
          duration: Duration(seconds: durationSeconds > 0 ? durationSeconds : 1),
          curve: Curves.linear,
        );

        await Future.delayed(const Duration(seconds: 4)); // Pausa abajo

        if (mounted && controller.hasClients) {
          controller.jumpTo(0); // Reiniciar arriba instantáneamente
        }

        await Future.delayed(const Duration(seconds: 3)); // Pausa arriba antes de volver a bajar
      } else {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _cargarDatosBD() async {
    if (!mounted) return;
    setState(() {
      _cargando = _todosLosReportes.isEmpty;
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

        Set<String> turnosSet = {'Todos'};
        Set<String> supervisoresSet = {'Todos'};
        Set<String> zonasSet = {'Todas'};
        Set<String> wqiSet = {'Todos'};

        for (var fila in datosRaw) {
          if (fila is Map) {
            final Map<String, dynamic> mapa = {};
            fila.forEach((key, val) => mapa[key.toString().toLowerCase().trim()] = val);

            String t = (mapa['turno']?.toString() ?? '').replaceAll('\n', ' ').trim();
            String s = (mapa['supervisor']?.toString() ?? '').replaceAll('\n', ' ').trim();
            String z = (mapa['zona']?.toString() ?? '').replaceAll('\n', ' ').trim();
            String w = (mapa['wqi']?.toString() ?? '').replaceAll('\n', ' ').trim();

            if (t.isNotEmpty) turnosSet.add(t);
            if (s.isNotEmpty) supervisoresSet.add(s);
            if (z.isNotEmpty) zonasSet.add(z);
            if (w.isNotEmpty) wqiSet.add(w);

            mapa['turno'] = t;
            mapa['supervisor'] = s;
            mapa['zona'] = z;
            mapa['wqi'] = w;

            datosProcesados.add(mapa);
          }
        }

        if (!mounted) return;
        setState(() {
          _todosLosReportes = datosProcesados;
          _listaTurnos = turnosSet.toList()..sort();
          _listaSupervisores = supervisoresSet.toList()..sort();
          _listaZonas = zonasSet.toList()..sort();
          _listaWqi = wqiSet.toList()..sort();

          if (!_listaTurnos.contains(_turnoSeleccionado)) _turnoSeleccionado = 'Todos';
          if (!_listaSupervisores.contains(_supervisorSeleccionado)) _supervisorSeleccionado = 'Todos';
          if (!_listaZonas.contains(_zonaSeleccionada)) _zonaSeleccionada = 'Todas';
          if (!_listaWqi.contains(_wqiSeleccionado)) _wqiSeleccionado = 'Todos';

          _ultimaActualizacion = DateFormat('HH:mm:ss').format(DateTime.now());
          _procesarDatosDelDia();
          _cargando = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensajeError = 'Error de conexión. Verifica la API: $e';
        _cargando = false;
      });
    }
  }

  void _procesarDatosDelDia() {
    _roturasPorHora.clear();
    _eventosFiltrados.clear();
    _roturasPorOperador.clear();

    int maxHora = 23;
    DateTime ahora = DateTime.now();

    if (_fechaSeleccionada.year == ahora.year &&
        _fechaSeleccionada.month == ahora.month &&
        _fechaSeleccionada.day == ahora.day) {
      maxHora = ahora.hour;
    } else if (_fechaSeleccionada.isAfter(ahora)) {
      maxHora = -1; // Futuro
    }

    for (int i = 0; i <= maxHora; i++) {
      _roturasPorHora[i] = 0.0;
    }

    Map<String, Map<String, dynamic>> agrupacionEventos = {};

    for (var r in _todosLosReportes) {
      String? rawFecha = r['timestamp_registro']?.toString() ?? r['fecha_evento']?.toString();

      if (rawFecha != null && rawFecha.isNotEmpty) {
        String fechaLimpia = rawFecha.replaceAll('T', ' ').split('.')[0];
        DateTime? dt = DateTime.tryParse(fechaLimpia);

        if (dt != null && dt.year == _fechaSeleccionada.year && dt.month == _fechaSeleccionada.month && dt.day == _fechaSeleccionada.day) {

          String turno = r['turno']?.toString() ?? '';
          String sup = r['supervisor']?.toString() ?? '';
          String zona = r['zona']?.toString() ?? '';
          String wqi = r['wqi']?.toString() ?? '';

          if (_turnoSeleccionado != 'Todos' && turno != _turnoSeleccionado) continue;
          if (_supervisorSeleccionado != 'Todos' && sup != _supervisorSeleccionado) continue;
          if (_zonaSeleccionada != 'Todas' && zona != _zonaSeleccionada) continue;
          if (_wqiSeleccionado != 'Todos' && wqi != _wqiSeleccionado) continue;

          int hora = dt.hour;
          double cant = double.tryParse(r['cantidad']?.toString() ?? '0') ?? 0.0;
          String operador = r['personal']?.toString().trim() ?? 'NO REGISTRADO';
          if (operador.isEmpty) operador = 'NO REGISTRADO';

          _roturasPorHora[hora] = (_roturasPorHora[hora] ?? 0.0) + cant;
          _roturasPorOperador[operador] = (_roturasPorOperador[operador] ?? 0) + cant;

          String causal = r['causal']?.toString().trim() ?? 'Desconocida';
          String plan = r['plan_reaccion']?.toString().trim() ?? '';
          String llaveGrupo = '${hora}_$causal';

          if (!agrupacionEventos.containsKey(llaveGrupo)) {
            agrupacionEventos[llaveGrupo] = {
              'hora_int': hora,
              'hora_str': '${hora.toString().padLeft(2, '0')}:00',
              'causal': causal,
              'plan_reaccion': plan,
              'cantidad': 0.0,
            };
          }
          agrupacionEventos[llaveGrupo]!['cantidad'] += cant;
        }
      }
    }

    _eventosFiltrados = agrupacionEventos.values.toList();
    _eventosFiltrados.sort((a, b) => (b['hora_int'] as int).compareTo(a['hora_int'] as int));
  }

  Future<void> _seleccionarFecha() async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1E293B),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (seleccion != null && seleccion != _fechaSeleccionada) {
      setState(() {
        _fechaSeleccionada = seleccion;
        _procesarDatosDelDia();
      });
    }
  }

  // Activar Modo Pantalla Completa pasando los filtros actuales
  void _togglePantallaCompleta() {
    if (widget.isFullScreen) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SicRoturasScreen(
            isFullScreen: true,
            initFecha: _fechaSeleccionada,
            initZona: _zonaSeleccionada,
            initTurno: _turnoSeleccionado,
            initWqi: _wqiSeleccionado,
            initSupervisor: _supervisorSeleccionado,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _todosLosReportes.isEmpty) {
      return const Scaffold(backgroundColor: Color(0xFFF4F6F8), body: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))));
    }

    double totalRoturasDia = _roturasPorHora.values.fold(0, (sum, val) => sum + val);

    int horasActivas = _roturasPorHora.length;
    int horasCumplen = _roturasPorHora.values.where((v) => v <= _metaPorHora).length;
    double pctCumplimiento = horasActivas > 0 ? (horasCumplen / horasActivas) * 100 : 100;

    var operadoresOrdenados = _roturasPorOperador.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ENCABEZADO Y BOTÓN DE PANTALLA COMPLETA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Monitoreo SIC T1', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B), letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text('Control de Intervalo Corto (Meta actual: ${_metaPorHora.toInt()} und/hora)', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                        child: Row(
                          children: [
                            const Icon(Icons.sync, size: 14, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text('Actualizado: $_ultimaActualizacion', style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _togglePantallaCompleta,
                        icon: Icon(widget.isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 20),
                        label: Text(widget.isFullScreen ? 'SALIR MODO TV' : 'MODO TV', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isFullScreen ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        ),
                      )
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // BARRA DE FILTROS (Se oculta en Modo TV)
              if (!widget.isFullScreen) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _buildFilterColumn(
                          'Fecha',
                          InkWell(
                            onTap: _seleccionarFecha,
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(DateFormat('dd/MM/yyyy').format(_fechaSeleccionada), style: const TextStyle(fontSize: 12, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
                                  const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF94A3B8)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFilterColumn('Zona', _buildDropdown(_zonaSeleccionada, _listaZonas, (v) => setState(() { _zonaSeleccionada = v!; _procesarDatosDelDia(); }))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFilterColumn('Turno', _buildDropdown(_turnoSeleccionado, _listaTurnos, (v) => setState(() { _turnoSeleccionado = v!; _procesarDatosDelDia(); }))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFilterColumn('WQI', _buildDropdown(_wqiSeleccionado, _listaWqi, (v) => setState(() { _wqiSeleccionado = v!; _procesarDatosDelDia(); }))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _buildFilterColumn('Supervisor', _buildDropdown(_supervisorSeleccionado, _listaSupervisores, (v) => setState(() { _supervisorSeleccionado = v!; _procesarDatosDelDia(); }))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // LAS 3 TARJETAS KPI
              Row(
                children: [
                  Expanded(child: _buildKPICard('TOTAL ROTURAS', '${totalRoturasDia.toInt()}', 'Unidades físicas reportadas', const Color(0xFF3B82F6))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildKPICard('TOTAL EVENTOS', '${_eventosFiltrados.length}', 'Causales únicas gestionadas', const Color(0xFF8B5CF6))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _buildKPICard(
                          'CUMPLIMIENTO META',
                          '${pctCumplimiento.toStringAsFixed(0)}%',
                          horasActivas > 0 ? '$horasCumplen de $horasActivas horas transcurridas' : 'Sin datos operativos',
                          pctCumplimiento >= 80 ? const Color(0xFF10B981) : (pctCumplimiento >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444))
                      )
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // GRÁFICA Y TABLAS CON AUTO-SCROLL
              SizedBox(
                height: widget.isFullScreen ? 850 : 720,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // GRÁFICA
                    Expanded(
                      flex: 65,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Evolución de Roturas por Hora (24 Horas)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                                  child: Text('Límite: ${_metaPorHora.toInt()} und', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                )
                              ],
                            ),
                            const SizedBox(height: 24),
                            Expanded(
                              child: CustomPaint(
                                painter: _AreaChartPainter(datos: _roturasPorHora, meta: _metaPorHora),
                                child: Container(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),

                    // TABLAS LATERALES
                    Expanded(
                      flex: 35,
                      child: Column(
                        children: [
                          // TABLA 1: OPERADORES
                          Expanded(
                            flex: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('Desempeño por Operador', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 14)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    color: const Color(0xFFF8FAFC),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: const [
                                        Text('PERSONAL ASIGNADO', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800)),
                                        Text('ROTURAS', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: operadoresOrdenados.isEmpty
                                        ? const Center(child: Text('Sin datos', style: TextStyle(color: Colors.grey, fontSize: 12)))
                                        : ListView.separated(
                                      controller: _scrollOperadores,
                                      padding: EdgeInsets.zero,
                                      itemCount: operadoresOrdenados.length,
                                      separatorBuilder: (c, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                      itemBuilder: (context, index) {
                                        var op = operadoresOrdenados[index];
                                        bool excede = op.value > _metaPorHora;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(child: Text(op.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(color: excede ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(4)),
                                                child: Text('${op.value.toInt()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: excede ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // TABLA 2: DETALLES DE EVENTOS
                          Expanded(
                            flex: 60,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('Detalle Causal y Plan de Reacción', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 14)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    color: const Color(0xFFF8FAFC),
                                    child: Row(
                                      children: const [
                                        Expanded(flex: 2, child: Text('HORA', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800))),
                                        Expanded(flex: 1, child: Text('UND', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800))),
                                        Expanded(flex: 4, child: Text('CAUSAL', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800))),
                                        Expanded(flex: 4, child: Text('PLAN DE REACCIÓN', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800))),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _eventosFiltrados.isEmpty
                                        ? const Center(child: Text('Sin eventos registrados', style: TextStyle(color: Colors.grey, fontSize: 12)))
                                        : ListView.separated(
                                      controller: _scrollEventos,
                                      padding: EdgeInsets.zero,
                                      itemCount: _eventosFiltrados.length,
                                      separatorBuilder: (c, i) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                      itemBuilder: (context, index) {
                                        var e = _eventosFiltrados[index];

                                        String horaStr = e['hora_str'] ?? '';
                                        String causal = e['causal'] ?? 'Desconocida';
                                        String plan = e['plan_reaccion'] ?? '';
                                        int cant = (e['cantidad'] as double).toInt();

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(flex: 2, child: Text(horaStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)))),
                                              Expanded(flex: 1, child: Align(
                                                alignment: Alignment.topLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(4)),
                                                  child: Text('$cant', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                                                ),
                                              )),
                                              Expanded(flex: 4, child: Padding(
                                                padding: const EdgeInsets.only(right: 8.0),
                                                child: Text(causal, style: const TextStyle(fontSize: 10, color: Color(0xFF1E293B), fontWeight: FontWeight.w600), maxLines: 4, overflow: TextOverflow.ellipsis),
                                              )),
                                              Expanded(flex: 4, child: Text(plan.isEmpty ? 'Sin plan asignado' : plan, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)), maxLines: 5, overflow: TextOverflow.ellipsis)),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterColumn(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, size: 16, color: Color(0xFF94A3B8)),
          style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w600),
          items: items.map((e) => DropdownMenuItem(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis, maxLines: 1)
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildKPICard(String titulo, String mainValue, String subValue, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(top: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5)),
          const SizedBox(height: 12),
          Text(mainValue, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: color, height: 1)),
          const SizedBox(height: 10),
          Text(subValue, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  final Map<int, double> datos;
  final double meta;

  _AreaChartPainter({required this.datos, required this.meta});

  @override
  void paint(Canvas canvas, Size size) {
    if (datos.isEmpty) return;

    List<MapEntry<int, double>> puntos = datos.entries.toList();
    puntos.sort((a, b) => a.key.compareTo(b.key));

    double maxVal = meta;
    for (var p in puntos) {
      if (p.value > maxVal) maxVal = p.value;
    }
    maxVal = maxVal * 1.15;

    double pTop = 30;
    double pBottom = 30;
    double pLeft = 40;
    double pRight = 30;

    double drawWidth = size.width - pLeft - pRight;
    double drawHeight = size.height - pTop - pBottom;

    // ESCALA DIVIDIDA (Asegura mínimo 20% de altura para el verde)
    double minGreenRatio = 0.20;
    double naturalGreenRatio = meta / maxVal;
    double actualGreenRatio = math.max(minGreenRatio, naturalGreenRatio);

    double bottomHeight = drawHeight * actualGreenRatio;
    double topHeight = drawHeight - bottomHeight;
    double metaY = pTop + topHeight;

    final redPaint = Paint()..color = const Color(0xFFEF4444).withOpacity(0.85);
    final greenPaint = Paint()..color = const Color(0xFF10B981).withOpacity(0.85);

    // Zonas de fondo
    canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTRB(pLeft, pTop, pLeft + drawWidth, metaY), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), redPaint);
    canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTRB(pLeft, metaY, pLeft + drawWidth, pTop + drawHeight), bottomLeft: const Radius.circular(4), bottomRight: const Radius.circular(4)), greenPaint);

    double getY(double val) {
      if (val <= meta) {
        return (pTop + drawHeight) - (val / meta) * bottomHeight;
      } else {
        return metaY - ((val - meta) / (maxVal - meta)) * topHeight;
      }
    }

    // Eje Y
    Set<int> yValues = {meta.toInt()};
    double step = (maxVal - meta) / 4;
    for(int i=1; i<=4; i++) {
      yValues.add((meta + step * i).toInt());
    }

    for (int v in yValues) {
      double yLine = getY(v.toDouble());
      canvas.drawLine(Offset(pLeft, yLine), Offset(pLeft + drawWidth, yLine), Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1);

      TextPainter tpY = TextPainter(
        text: TextSpan(text: v.toString(), style: TextStyle(color: v == meta.toInt() ? const Color(0xFF10B981) : const Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tpY.paint(canvas, Offset(pLeft - tpY.width - 6, yLine - (tpY.height / 2)));
    }

    // El Eje X está estandarizado para tener siembre 24 divisiones (00:00 a 23:00)
    double spacing = drawWidth / 23;

    // Pintar las etiquetas del eje X siempre (00:00 a 23:00)
    for (int i = 0; i < 24; i++) {
      double x = pLeft + (i * spacing);

      String horaText = '${i.toString().padLeft(2, '0')}:00';
      TextPainter tpX = TextPainter(
        text: TextSpan(text: horaText, style: const TextStyle(color: Color(0xFF475569), fontSize: 9, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(x, pTop + drawHeight + 12);
      canvas.rotate(-0.4);
      tpX.paint(canvas, const Offset(0, 0));
      canvas.restore();
    }

    // Línea Principal
    if (puntos.isNotEmpty) {
      final linePaint = Paint()
        ..color = const Color(0xFF0F172A)
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final dotOuterPaint = Paint()..color = const Color(0xFF0F172A);
      final dotInnerPaint = Paint()..color = Colors.white;

      Path path = Path();
      for (int i = 0; i < puntos.length; i++) {
        double val = puntos[i].value;
        double x = pLeft + (puntos[i].key * spacing);
        double y = getY(val);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);

      // Puntos y Textos
      for (int i = 0; i < puntos.length; i++) {
        double val = puntos[i].value;
        double x = pLeft + (puntos[i].key * spacing);
        double y = getY(val);

        canvas.drawCircle(Offset(x, y), 5, dotOuterPaint);
        canvas.drawCircle(Offset(x, y), 2.5, dotInnerPaint);

        TextPainter tpVal = TextPainter(
          text: TextSpan(text: val.toInt().toString(), style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w900)),
          textDirection: TextDirection.ltr,
        )..layout();
        tpVal.paint(canvas, Offset(x - (tpVal.width / 2), y - 22));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}