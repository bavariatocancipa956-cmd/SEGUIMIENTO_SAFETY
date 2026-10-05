import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:math';

import 'api_service.dart';

// --- CLASE AUXILIAR PARA LA EDICIÓN DE ACCIONES ---
class AccionEditItem {
  String? tipoAccion;
  String? actividadSeleccionada;
  final TextEditingController actividadCtrl = TextEditingController();
  final TextEditingController descripcionCtrl = TextEditingController();
  final TextEditingController responsableCtrl = TextEditingController();
  DateTime? fechaCierre;
  String estado = 'Pendiente';

  void dispose() {
    actividadCtrl.dispose();
    descripcionCtrl.dispose();
    responsableCtrl.dispose();
  }
}

// Motor de compresión para nuevas imágenes subidas durante la edición
Uint8List comprimirImagenWorker(Uint8List bytes) {
  img.Image? decodedImage = img.decodeImage(bytes);
  if (decodedImage == null) return bytes;
  img.Image resized = decodedImage;
  if (decodedImage.width > 600) {
    resized = img.copyResize(decodedImage, width: 600);
  }
  int quality = 85;
  Uint8List result = img.encodeJpg(resized, quality: quality);
  while (result.length > 51200 && quality > 5) {
    quality -= 15;
    result = img.encodeJpg(resized, quality: quality);
  }
  return result;
}

class HistorialCincoWhyScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  final VoidCallback onToggleSidebar;

  const HistorialCincoWhyScreen({
    super.key,
    required this.usuario,
    required this.onToggleSidebar,
  });

  @override
  State<HistorialCincoWhyScreen> createState() => _HistorialCincoWhyScreenState();
}

class _HistorialCincoWhyScreenState extends State<HistorialCincoWhyScreen> {
  final ScrollController _tablaScrollController = ScrollController();
  bool _cargando = true;
  String? _mensajeError;
  String? _idGenerandoPdf;
  bool _generandoMultiplesPdf = false;

  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];
  Set<String> _seleccionados = {};

  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _filtroPI = 'Todos';
  String _filtroArea = 'Todas';
  String _busquedaTexto = '';
  final TextEditingController _buscarCtrl = TextEditingController();

  List<String> _listaFiltroPI = ['Todos'];
  List<String> _listaFiltroArea = ['Todas'];

  int _totalReportes = 0;
  int _conCausaRaiz = 0;
  int _sinCausaRaiz = 0;
  Map<String, int> _conteoPI = {};
  Map<String, int> _conteoAreas = {};

  int _registrosPorPagina = 10;
  int _paginaActual = 1;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _tablaScrollController.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
      _seleccionados.clear();
    });

    try {
      final data = await ApiService.consultar('gestion', '5why');
      List<Map<String, dynamic>> datosProcesados = [];
      if (data != null && data is List) {
        datosProcesados = data.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      datosProcesados.sort((a, b) {
        int idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        int idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return idB.compareTo(idA);
      });

      _registros = datosProcesados;
      _extraerListasParaFiltros();
      _aplicarFiltros();

      setState(() => _cargando = false);
    } catch (e) {
      setState(() {
        _mensajeError = 'Error al cargar los datos: $e';
        _cargando = false;
      });
    }
  }

  void _extraerListasParaFiltros() {
    Set<String> pis = {'Todos'};
    Set<String> areas = {'Todas'};

    for (var r in _registros) {
      String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();
      String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
      if (pi.isNotEmpty && pi != 'NULL') pis.add(pi);
      if (ar.isNotEmpty && ar != 'NULL') areas.add(ar);
    }

    _listaFiltroPI = pis.toList()..sort();
    _listaFiltroArea = areas.toList()..sort();
  }

  void _aplicarFiltros() {
    setState(() {
      _registrosFiltrados = _registros.where((r) {
        if (_fechaDesde != null || _fechaHasta != null) {
          DateTime? dt = DateTime.tryParse(r['fecha']?.toString() ?? '');
          if (dt != null) {
            if (_fechaDesde != null && dt.isBefore(_fechaDesde!)) return false;
            if (_fechaHasta != null && dt.isAfter(_fechaHasta!.add(const Duration(days: 1)))) return false;
          }
        }

        String ar = (r['area']?.toString() ?? '').trim().toUpperCase();
        String pi = (r['pi']?.toString() ?? '').trim().toUpperCase();

        if (_filtroArea != 'Todas' && ar != _filtroArea) return false;
        if (_filtroPI != 'Todos' && pi != _filtroPI) return false;

        if (_busquedaTexto.isNotEmpty) {
          String search = _busquedaTexto.toLowerCase();
          bool match = false;
          if (ar.toLowerCase().contains(search)) match = true;
          if (pi.toLowerCase().contains(search)) match = true;
          if ((r['participantes']?.toString() ?? '').toLowerCase().contains(search)) match = true;
          if ((r['valor_disparador_alcanzado']?.toString() ?? '').toLowerCase().contains(search)) match = true;

          if (!match) return false;
        }

        return true;
      }).toList();

      _paginaActual = 1;
      _seleccionados.clear();
      _calcularEstadisticas(_registrosFiltrados);
    });
  }

  void _limpiarFiltros() {
    setState(() {
      _fechaDesde = null; _fechaHasta = null; _filtroPI = 'Todos'; _filtroArea = 'Todas';
      _busquedaTexto = ''; _buscarCtrl.clear();
      _aplicarFiltros();
    });
  }

  void _calcularEstadisticas(List<Map<String, dynamic>> datos) {
    _totalReportes = datos.length;
    _conCausaRaiz = 0;
    _sinCausaRaiz = 0;

    Map<String, int> piTemp = {};
    Map<String, int> areasTemp = {};

    for (var fila in datos) {
      String pi = (fila['pi']?.toString() ?? 'Sin PI').toUpperCase();
      String area = (fila['area']?.toString() ?? 'Sin Área').toUpperCase();
      String causa = (fila['encontro_causa_raiz']?.toString() ?? '').toUpperCase();

      if (pi.trim().isEmpty || pi == 'NULL') pi = 'SIN PI';
      if (area.trim().isEmpty || area == 'NULL') area = 'SIN ÁREA';

      if (causa == 'SI') _conCausaRaiz++; else _sinCausaRaiz++;

      piTemp[pi] = (piTemp[pi] ?? 0) + 1;
      areasTemp[area] = (areasTemp[area] ?? 0) + 1;
    }

    _conteoPI = Map.fromEntries(piTemp.entries.toList()..sort((e1, e2) => e2.value.compareTo(e1.value)));
    _conteoAreas = Map.fromEntries(areasTemp.entries.toList()..sort((e1, e2) => e2.value.compareTo(e1.value)));
  }

  void _toggleSeleccion(String id) {
    setState(() {
      if (_seleccionados.contains(id)) _seleccionados.remove(id);
      else _seleccionados.add(id);
    });
  }

  void _toggleSeleccionarTodos(List<Map<String, dynamic>> pagina) {
    setState(() {
      bool todosSeleccionados = pagina.every((r) => _seleccionados.contains(r['id'].toString()));
      if (todosSeleccionados) {
        for (var r in pagina) { _seleccionados.remove(r['id'].toString()); }
      } else {
        for (var r in pagina) { _seleccionados.add(r['id'].toString()); }
      }
    });
  }

  Future<void> _descargarExcel() async {
    try {
      String csv = "ID;Fecha;Area;PI Afectado;Participantes;Valor Disparador;Causa Raiz Encontrada;Descripcion Causa Raiz;Req. Investigacion Adicional;Estado Evaluacion;Observacion Evaluador;Estado Acciones;Resultado 2;Observacion 2;Ultima Aprobacion\n";
      String sanitize(String val) => val.replaceAll('\n', ' ').replaceAll('\r', '').replaceAll(';', ',');

      for (var r in _registrosFiltrados) {
        String id = sanitize(r['id']?.toString() ?? '');
        String f = sanitize(r['fecha']?.toString().split('T')[0] ?? '');
        String a = sanitize(r['area']?.toString() ?? '');
        String p = sanitize(r['pi']?.toString() ?? '');
        String part = sanitize(r['participantes']?.toString() ?? '');
        String disp = sanitize(r['valor_disparador_alcanzado']?.toString() ?? '');
        String causa = sanitize(r['encontro_causa_raiz']?.toString() ?? '');
        String req = sanitize(r['requiere_investigacion_adicional']?.toString() ?? '');
        String estEval = sanitize(r['estado']?.toString() ?? 'PENDIENTE');
        String obsEval = sanitize(r['observacion_evaluador']?.toString() ?? '');

        String causaRaizDesc = sanitize(r['causa_raiz']?.toString() ?? r['causa raiz']?.toString() ?? '');
        String res2 = sanitize(r['resultado_2']?.toString() ?? '');
        String obs2 = sanitize(r['Observacion 2']?.toString() ?? r['observacion_2']?.toString() ?? '');
        String ultAp = sanitize(r['ultima aprovacion']?.toString() ?? r['ultima_aprovacion']?.toString() ?? '');

        int accionesCerradas = 0; int totalAcciones = 0;
        for (int i = 1; i <= 4; i++) {
          if ((r['accion_$i']?.toString() ?? '').isNotEmpty) {
            totalAcciones++;
            if ((r['estado_accion$i']?.toString() ?? '').toUpperCase() == 'CONCLUIDA') accionesCerradas++;
          }
        }
        String estadoAcc = "$accionesCerradas de $totalAcciones cerradas";
        csv += "$id;$f;$a;$p;$part;$disp;$causa;$causaRaizDesc;$req;$estEval;$obsEval;$estadoAcc;$res2;$obs2;$ultAp\n";
      }

      List<int> bytes = [0xEF, 0xBB, 0xBF] + utf8.encode(csv);
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'Reporte_5Why_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel generado exitosamente'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar Excel: $e'), backgroundColor: Colors.red));
    }
  }

  // ==========================================
  // FUNCIÓN FALTANTE: VISOR DE IMÁGENES
  // ==========================================
  void _mostrarPreviewImagen(String dato, {required bool isBase64}) {
    String cleanData = dato;
    if (isBase64 && dato.contains('IMAGEN_ADJUNTA:')) {
      cleanData = dato.replaceAll('IMAGEN_ADJUNTA:', '').trim();
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
                title: const Text('Evidencia Fotográfica', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                backgroundColor: const Color(0xFF0A2540), foregroundColor: Colors.white, automaticallyImplyLeading: false,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))]
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: isBase64
                  ? Image.memory(base64Decode(cleanData), fit: BoxFit.contain, height: 400, errorBuilder: (c,e,s) => const Icon(Icons.broken_image, size: 50, color: Colors.grey))
                  : Image.network(cleanData, fit: BoxFit.contain, height: 400, errorBuilder: (c,e,s) => const Icon(Icons.broken_image, size: 50, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // MODAL DE EDICIÓN TOTAL (CREADOR)
  // ==========================================
  void _abrirModalEdicion(Map<String, dynamic> row, bool soloLectura) {
    dynamic id = row['id'];

    // 1. Feedback de revisión
    String estadoActual = (row['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
    String calificacion = row['resultado']?.toString() ?? '0.0%';
    String obs1 = row['observacion_evaluador']?.toString() ?? 'Sin observaciones aún.';
    String resFinal = row['ultima aprovacion']?.toString() ?? row['ultima_aprovacion']?.toString() ?? 'Pendiente';
    String obs2 = row['Observacion 2']?.toString() ?? row['observacion_2']?.toString() ?? 'Sin observaciones de segunda revisión.';
    String estadoRevision = row['estado_revicion']?.toString() ?? '';

    // 2. Controladores Generales
    DateTime fechaSelect = DateTime.tryParse(row['fecha']?.toString() ?? '') ?? DateTime.now();
    String turnoSelect = row['turno']?.toString() ?? 'T1';
    if (!['T1', 'T2', 'T3'].contains(turnoSelect)) turnoSelect = 'T1';

    TextEditingController areaCtrl = TextEditingController(text: row['area']?.toString());
    TextEditingController participantesCtrl = TextEditingController(text: row['participantes']?.toString());
    TextEditingController disparadorCtrl = TextEditingController(text: row['valor_disparador_alcanzado']?.toString());
    TextEditingController contencionCtrl = TextEditingController(text: row['contencion_problema']?.toString());
    TextEditingController causaRaizCtrl = TextEditingController(text: row['causa_raiz']?.toString() ?? row['causa raiz']?.toString() ?? '');

    String? piSeleccionado = row['pi']?.toString();
    List<String> validPIs = _listaFiltroPI.where((e) => e != 'Todos').toList();
    if (piSeleccionado != null && !validPIs.contains(piSeleccionado)) {
      piSeleccionado = null;
    }

    String reqInvestigacion = row['requiere_investigacion_adicional']?.toString().toUpperCase() == 'SI' ? 'SI' : 'NO';
    String encontroCausa = row['encontro_causa_raiz']?.toString().toUpperCase() == 'SI' ? 'SI' : 'NO';

    // 3. Controladores 5 Porqués
    List<TextEditingController> pqCtrls = List.generate(5, (i) => TextEditingController(text: row['porque_${i + 1}']?.toString() ?? ''));
    List<TextEditingController> exCtrls = List.generate(5, (i) => TextEditingController(text: row['explique_porque_${i + 1}']?.toString() ?? ''));
    List<TextEditingController> evTextCtrls = [];

    List<String> evidenciasExistentesURL = List.generate(5, (_) => '');
    List<Uint8List?> nuevasEvidenciasBytes = List.filled(5, null);

    // FILTRO ESTRICTO DE LIMPIEZA DE BASE64
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      String textoPuro = rawEvidencia;
      String urlOBase64 = '';

      if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
        var parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
        textoPuro = parts[0].replaceAll('|', '').trim();
        urlOBase64 = 'IMAGEN_ADJUNTA:${parts[1].trim()}';
      } else if (rawEvidencia.contains('http')) {
        int httpIndex = rawEvidencia.indexOf('http');
        textoPuro = rawEvidencia.substring(0, httpIndex).replaceAll('|', '').trim();
        urlOBase64 = rawEvidencia.substring(httpIndex).trim();
      } else if (rawEvidencia.contains('data:image')) {
        int dataIndex = rawEvidencia.indexOf('data:image');
        textoPuro = rawEvidencia.substring(0, dataIndex).replaceAll('|', '').trim();
        urlOBase64 = rawEvidencia.substring(dataIndex).trim();
      }

      evTextCtrls.add(TextEditingController(text: textoPuro));
      evidenciasExistentesURL[i - 1] = urlOBase64;
    }

    // 4. Controladores Acciones
    List<AccionEditItem> accionesEditables = [];
    List<String> validActividades = ['DTO', 'SLA', 'Entrenamiento', 'PIs', 'Mapa de Procesos', 'PM Plan', 'Check List'];

    for (int i = 1; i <= 4; i++) {
      String tipo = row['accion_$i']?.toString() ?? '';
      if (tipo.trim().isNotEmpty) {
        AccionEditItem accion = AccionEditItem();
        accion.tipoAccion = ['Preventiva', 'Correctiva'].contains(tipo) ? tipo : 'Correctiva';

        String actDb = row['actividad_$i']?.toString() ?? '';
        accion.actividadSeleccionada = validActividades.contains(actDb) ? actDb : null;

        accion.actividadCtrl.text = actDb;
        accion.descripcionCtrl.text = row['descripcion_$i']?.toString() ?? '';
        accion.responsableCtrl.text = row['responsable_$i']?.toString() ?? '';

        accion.estado = row['estado_accion$i']?.toString() ?? 'Pendiente';
        if (!['Pendiente', 'Concluida'].contains(accion.estado)) accion.estado = 'Pendiente';

        String fechaC = row['fecha_cierre_$i']?.toString() ?? '';
        if (fechaC.isNotEmpty && fechaC != 'NULL') {
          accion.fechaCierre = DateTime.tryParse(fechaC);
        }
        accionesEditables.add(accion);
      }
    }
    if (accionesEditables.isEmpty) {
      accionesEditables.addAll([AccionEditItem(), AccionEditItem()]);
    }

    bool guardando = false;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (dialogContext, setModalState) {
              bool isMobile = MediaQuery.of(ctx).size.width < 700;

              Future<void> seleccionarNuevaImagen(int index) async {
                if (soloLectura) return;
                try {
                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 15, maxWidth: 400, maxHeight: 400);
                  if (image != null) {
                    Uint8List bytes = await image.readAsBytes();
                    if (bytes.length > 51200) bytes = await compute(comprimirImagenWorker, bytes);
                    if (bytes.length > 51200) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imagen demasiado compleja. Elija una más simple.'), backgroundColor: Colors.red));
                      return;
                    }
                    setModalState(() => nuevasEvidenciasBytes[index] = bytes);
                  }
                } catch (e) {
                  debugPrint('Error imagen: $e');
                }
              }

              void agregarAccion() {
                if (soloLectura) return;
                if (accionesEditables.length < 4) setModalState(() => accionesEditables.add(AccionEditItem()));
              }

              void eliminarAccion(int index) {
                if (soloLectura) return;
                if (accionesEditables.length > 2) {
                  setModalState(() {
                    accionesEditables[index].dispose();
                    accionesEditables.removeAt(index);
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debe mantener al menos 2 acciones.'), backgroundColor: Colors.orange));
                }
              }

              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
                child: Container(
                  width: isMobile ? double.infinity : 900,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(soloLectura ? Icons.visibility : Icons.edit_note_rounded, color: const Color(0xFF1976D2), size: 24),
                              const SizedBox(width: 8),
                              Text(soloLectura ? 'Detalle del Reporte (Aprobado)' : 'Editar Reporte 5 Why', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0A2540))),
                            ],
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const Divider(),

                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. PANEL DE FEEDBACK DEL REVISOR
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200, width: 1.5)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('💡 RETROALIMENTACIÓN DEL REVISOR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF1976D2))),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(child: _datoRowVisual('Estado 1ra Revisión:', estadoActual, isBold: true)),
                                        Expanded(child: _datoRowVisual('Calificación:', calificacion, isBold: true)),
                                      ],
                                    ),
                                    _datoRowVisual('Observación 1:', obs1),
                                    const Divider(color: Colors.blue),
                                    Row(
                                      children: [
                                        Expanded(child: _datoRowVisual('Aprobación Final:', resFinal, isBold: true, color: Colors.orange.shade900)),
                                        Expanded(child: _datoRowVisual('Estado Reenvío:', estadoRevision.isEmpty ? 'Ninguno' : estadoRevision, isBold: true)),
                                      ],
                                    ),
                                    _datoRowVisual('Observación 2:', obs2),
                                  ],
                                ),
                              ),

                              if (soloLectura)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green)),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                                      SizedBox(width: 8),
                                      Text('Este reporte ya ha sido aprobado y no puede ser editado.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                                    ],
                                  ),
                                ),

                              Text(soloLectura ? '📄 FORMULARIO (SOLO LECTURA)' : '✏️ FORMULARIO DE EDICIÓN', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF475569))),
                              const SizedBox(height: 12),

                              // --- 1. INFO GENERAL ---
                              _seccionSubtitulo('1. Información General', Icons.feed_rounded),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Fecha', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                        const SizedBox(height: 4),
                                        InkWell(
                                          onTap: soloLectura ? null : () async {
                                            DateTime? p = await showDatePicker(context: context, initialDate: fechaSelect, firstDate: DateTime(2020), lastDate: DateTime(2101));
                                            if (p != null) setModalState(() => fechaSelect = p);
                                          },
                                          child: Container(
                                            height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(DateFormat('yyyy-MM-dd').format(fechaSelect), style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87)),
                                                const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                              ],
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Turno', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                          const SizedBox(height: 4),
                                          Container(
                                            height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: turnoSelect, isExpanded: true, style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                items: ['T1', 'T2', 'T3'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                onChanged: soloLectura ? null : (v) => setModalState(() => turnoSelect = v!),
                                              ),
                                            ),
                                          )
                                        ],
                                      )
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: _buildInputTextField('Área / Proceso', areaCtrl, readOnly: soloLectura)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('PI Afectado', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                          const SizedBox(height: 4),
                                          Container(
                                            height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: piSeleccionado,
                                                isExpanded: true,
                                                style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                items: validPIs.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                onChanged: soloLectura ? null : (val) => setModalState(() => piSeleccionado = val),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildInputTextField('Participantes', participantesCtrl, readOnly: soloLectura),

                              const SizedBox(height: 16),
                              // --- 2. DISPARADOR ---
                              _seccionSubtitulo('2. Disparador y Contención', Icons.warning_rounded),
                              _buildInputTextField('Valor del Disparador Alcanzado', disparadorCtrl, readOnly: soloLectura),
                              const SizedBox(height: 8),
                              _buildInputTextField('¿Qué se hizo para contener el problema?', contencionCtrl, maxLines: 2, readOnly: soloLectura),

                              const SizedBox(height: 16),
                              // --- 3. LOS 5 PORQUÉS ---
                              _seccionSubtitulo('3. Análisis de Causa Raíz (5W)', Icons.account_tree_rounded),
                              ...List.generate(5, (index) {
                                bool tieneUrlAnterior = evidenciasExistentesURL[index].isNotEmpty;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8))),
                                        child: Row(
                                          children: [
                                            Text('¿Por qué ${index + 1}?', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          children: [
                                            _buildInputTextField('Pregunta', pqCtrls[index], readOnly: soloLectura),
                                            const SizedBox(height: 8),
                                            _buildInputTextField('Respuesta / Explicación', exCtrls[index], maxLines: 2, readOnly: soloLectura),
                                            const SizedBox(height: 8),
                                            _buildInputTextField('Evidencia (Texto)', evTextCtrls[index], maxLines: 2, readOnly: soloLectura),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                    child: Text(
                                                      nuevasEvidenciasBytes[index] != null ? '✅ Nueva imagen lista para subir' : (tieneUrlAnterior ? '🖼️ Imagen actual en servidor (Se conservará)' : 'Sin imagen fotográfica'),
                                                      style: TextStyle(fontSize: 10, color: nuevasEvidenciasBytes[index] != null ? Colors.green : Colors.grey.shade600, fontStyle: FontStyle.italic),
                                                    )
                                                ),
                                                if (!soloLectura)
                                                  ElevatedButton.icon(
                                                    onPressed: () => seleccionarNuevaImagen(index),
                                                    icon: const Icon(Icons.upload_file, size: 14),
                                                    label: const Text('Cambiar Foto', style: TextStyle(fontSize: 10)),
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black87, elevation: 0, minimumSize: const Size(0, 30)),
                                                  )
                                                else if (tieneUrlAnterior)
                                                  TextButton.icon(
                                                    onPressed: () => _mostrarPreviewImagen(evidenciasExistentesURL[index], isBase64: evidenciasExistentesURL[index].contains('IMAGEN_ADJUNTA:')),
                                                    icon: const Icon(Icons.visibility, size: 14),
                                                    label: const Text('Ver Foto', style: TextStyle(fontSize: 10)),
                                                  )
                                              ],
                                            )
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                );
                              }),

                              const SizedBox(height: 16),
                              // --- 4. CONCLUSIÓN ---
                              _seccionSubtitulo('Conclusión', Icons.search_rounded),
                              Row(
                                children: [
                                  Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('¿Requiere inv. adicional?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                          const SizedBox(height: 4),
                                          Container(
                                            height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: reqInvestigacion, isExpanded: true, style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                items: ['SI', 'NO'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                onChanged: soloLectura ? null : (v) => setModalState(() => reqInvestigacion = v!),
                                              ),
                                            ),
                                          )
                                        ],
                                      )
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('¿Encontró Causa Raíz?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                          const SizedBox(height: 4),
                                          Container(
                                            height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: encontroCausa, isExpanded: true, style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                items: ['SI', 'NO'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                onChanged: soloLectura ? null : (v) => setModalState(() => encontroCausa = v!),
                                              ),
                                            ),
                                          )
                                        ],
                                      )
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildInputTextField('Descripción Causa Raíz (Si aplica)', causaRaizCtrl, maxLines: 2, readOnly: soloLectura),

                              const SizedBox(height: 16),
                              // --- 5. ACCIONES ---
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _seccionSubtitulo('4. Acciones a tomar', Icons.assignment_turned_in_rounded),
                                  if (!soloLectura && accionesEditables.length < 4)
                                    TextButton.icon(
                                      onPressed: agregarAccion,
                                      icon: const Icon(Icons.add_circle, size: 14),
                                      label: const Text('Agregar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      style: TextButton.styleFrom(backgroundColor: Colors.blue.shade50),
                                    )
                                ],
                              ),
                              ...List.generate(accionesEditables.length, (index) {
                                final acc = accionesEditables[index];
                                bool esPreventiva = acc.tipoAccion == 'Preventiva';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Acción #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontSize: 12)),
                                          if (!soloLectura && accionesEditables.length > 2)
                                            InkWell(onTap: () => eliminarAccion(index), child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 16))
                                        ],
                                      ),
                                      const Divider(),
                                      Row(
                                        children: [
                                          Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('Tipo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                                    child: DropdownButtonHideUnderline(
                                                      child: DropdownButton<String>(
                                                        value: acc.tipoAccion, isExpanded: true, style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                        items: ['Preventiva', 'Correctiva'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                        onChanged: soloLectura ? null : (val) {
                                                          setModalState(() {
                                                            acc.tipoAccion = val;
                                                            if (val == 'Correctiva') acc.actividadSeleccionada = null;
                                                          });
                                                        },
                                                      ),
                                                    ),
                                                  )
                                                ],
                                              )
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('Actividad', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                                  const SizedBox(height: 4),
                                                  esPreventiva
                                                      ? Container(
                                                    height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                                    child: DropdownButtonHideUnderline(
                                                      child: DropdownButton<String>(
                                                        value: acc.actividadSeleccionada, isExpanded: true, style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                        hint: const Text('Elegir', style: TextStyle(fontSize: 10)),
                                                        items: validActividades.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                        onChanged: soloLectura ? null : (val) => setModalState(() => acc.actividadSeleccionada = val),
                                                      ),
                                                    ),
                                                  )
                                                      : _buildInputTextField('', acc.actividadCtrl, maxLines: 1, readOnly: soloLectura)
                                                ],
                                              )
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      _buildInputTextField('Descripción', acc.descripcionCtrl, maxLines: 2, readOnly: soloLectura),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(flex: 2, child: _buildInputTextField('Responsable', acc.responsableCtrl, readOnly: soloLectura)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('Fecha Cierre', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                                  const SizedBox(height: 4),
                                                  InkWell(
                                                    onTap: soloLectura ? null : () async {
                                                      DateTime? p = await showDatePicker(context: context, initialDate: acc.fechaCierre ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2101));
                                                      if (p != null) setModalState(() => acc.fechaCierre = p);
                                                    },
                                                    child: Container(
                                                      height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text(acc.fechaCierre != null ? DateFormat('yyyy-MM-dd').format(acc.fechaCierre!) : 'DD-MM-YYYY', style: TextStyle(fontSize: 11, color: acc.fechaCierre != null ? Colors.black87 : Colors.grey)),
                                                          const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                                        ],
                                                      ),
                                                    ),
                                                  )
                                                ],
                                              )
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              flex: 2,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('Estado', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    height: 35, padding: const EdgeInsets.symmetric(horizontal: 10),
                                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: soloLectura ? Colors.grey.shade100 : Colors.white),
                                                    child: DropdownButtonHideUnderline(
                                                      child: DropdownButton<String>(
                                                        value: acc.estado, isExpanded: true, style: TextStyle(fontSize: 11, color: soloLectura ? Colors.black54 : Colors.black87),
                                                        items: ['Pendiente', 'Concluida'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                                        onChanged: soloLectura ? null : (val) {
                                                          setModalState(() => acc.estado = val!);
                                                        },
                                                      ),
                                                    ),
                                                  )
                                                ],
                                              )
                                          )
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              })
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: soloLectura
                            ? [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                            child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold)),
                          )
                        ]
                            : [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: guardando ? null : () async {

                              // Validaciones
                              if (areaCtrl.text.trim().isEmpty || piSeleccionado == null || disparadorCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, complete Área, PI y Disparador.'), backgroundColor: Colors.orange));
                                return;
                              }

                              for (int i = 0; i < accionesEditables.length; i++) {
                                var a = accionesEditables[i];
                                if (a.tipoAccion == null || a.descripcionCtrl.text.trim().isEmpty || a.responsableCtrl.text.trim().isEmpty || a.fechaCierre == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Complete todos los campos de la Acción #${i+1}'), backgroundColor: Colors.orange));
                                  return;
                                }
                                if (a.tipoAccion == 'Preventiva' && a.actividadSeleccionada == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Seleccione una actividad para la Acción #${i+1}'), backgroundColor: Colors.orange));
                                  return;
                                }
                              }

                              setModalState(() => guardando = true);

                              // 1. Subir nuevas imágenes si hay
                              for (int i = 0; i < 5; i++) {
                                if (nuevasEvidenciasBytes[i] != null) {
                                  String? urlSubida = await ApiService.subirImagen(nuevasEvidenciasBytes[i]!);
                                  if (urlSubida != null) {
                                    evidenciasExistentesURL[i] = urlSubida;
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al subir imagen.'), backgroundColor: Colors.red));
                                    setModalState(() => guardando = false);
                                    return;
                                  }
                                }
                              }

                              // Construir cadena final de evidencia: "Texto | URL"
                              String getEvidenciaFinal(int index) {
                                String texto = evTextCtrls[index].text.trim();
                                String url = evidenciasExistentesURL[index];
                                if (url.isNotEmpty && texto.isNotEmpty) return '$texto | $url';
                                if (url.isNotEmpty) return url;
                                return texto;
                              }

                              // 2. Construir Payload asegurando el envio a PENDIENTE REVISION
                              final payload = {
                                'fecha': DateFormat('yyyy-MM-dd').format(fechaSelect),
                                'turno': turnoSelect,
                                'area': areaCtrl.text.trim(),
                                'pi': piSeleccionado ?? '',
                                'participantes': participantesCtrl.text.trim(),
                                'valor_disparador_alcanzado': disparadorCtrl.text.trim(),
                                'contencion_problema': contencionCtrl.text.trim(),
                                'requiere_investigacion_adicional': reqInvestigacion,
                                'encontro_causa_raiz': encontroCausa,
                                'causa raiz': causaRaizCtrl.text.trim(), // COLUMNA EXACTA SIN GUION BAJO

                                'porque_1': pqCtrls[0].text.trim(), 'explique_porque_1': exCtrls[0].text.trim(), 'evidencia_porque_1': getEvidenciaFinal(0),
                                'porque_2': pqCtrls[1].text.trim(), 'explique_porque_2': exCtrls[1].text.trim(), 'evidencia_porque_2': getEvidenciaFinal(1),
                                'porque_3': pqCtrls[2].text.trim(), 'explique_porque_3': exCtrls[2].text.trim(), 'evidencia_porque_3': getEvidenciaFinal(2),
                                'porque_4': pqCtrls[3].text.trim(), 'explique_porque_4': exCtrls[3].text.trim(), 'evidencia_porque_4': getEvidenciaFinal(3),
                                'porque_5': pqCtrls[4].text.trim(), 'explique_porque_5': exCtrls[4].text.trim(), 'evidencia_porque_5': getEvidenciaFinal(4),

                                // Acciones (Sobreescribimos hasta 4, limpiamos las que no existan)
                                'accion_1': accionesEditables.isNotEmpty ? accionesEditables[0].tipoAccion : '',
                                'actividad_1': accionesEditables.isNotEmpty && accionesEditables[0].tipoAccion == 'Preventiva' ? (accionesEditables[0].actividadSeleccionada ?? '') : '',
                                'descripcion_1': accionesEditables.isNotEmpty ? accionesEditables[0].descripcionCtrl.text : '',
                                'responsable_1': accionesEditables.isNotEmpty ? accionesEditables[0].responsableCtrl.text : '',
                                'fecha_cierre_1': (accionesEditables.isNotEmpty && accionesEditables[0].fechaCierre != null) ? DateFormat('yyyy-MM-dd').format(accionesEditables[0].fechaCierre!) : null,
                                'estado_accion1': accionesEditables.isNotEmpty ? accionesEditables[0].estado : '',

                                'accion_2': accionesEditables.length > 1 ? accionesEditables[1].tipoAccion : '',
                                'actividad_2': accionesEditables.length > 1 && accionesEditables[1].tipoAccion == 'Preventiva' ? (accionesEditables[1].actividadSeleccionada ?? '') : '',
                                'descripcion_2': accionesEditables.length > 1 ? accionesEditables[1].descripcionCtrl.text : '',
                                'responsable_2': accionesEditables.length > 1 ? accionesEditables[1].responsableCtrl.text : '',
                                'fecha_cierre_2': (accionesEditables.length > 1 && accionesEditables[1].fechaCierre != null) ? DateFormat('yyyy-MM-dd').format(accionesEditables[1].fechaCierre!) : null,
                                'estado_accion2': accionesEditables.length > 1 ? accionesEditables[1].estado : '',

                                'accion_3': accionesEditables.length > 2 ? accionesEditables[2].tipoAccion : '',
                                'actividad_3': accionesEditables.length > 2 && accionesEditables[2].tipoAccion == 'Preventiva' ? (accionesEditables[2].actividadSeleccionada ?? '') : '',
                                'descripcion_3': accionesEditables.length > 2 ? accionesEditables[2].descripcionCtrl.text : '',
                                'responsable_3': accionesEditables.length > 2 ? accionesEditables[2].responsableCtrl.text : '',
                                'fecha_cierre_3': (accionesEditables.length > 2 && accionesEditables[2].fechaCierre != null) ? DateFormat('yyyy-MM-dd').format(accionesEditables[2].fechaCierre!) : null,
                                'estado_accion3': accionesEditables.length > 2 ? accionesEditables[2].estado : '',

                                'accion_4': accionesEditables.length > 3 ? accionesEditables[3].tipoAccion : '',
                                'actividad_4': accionesEditables.length > 3 && accionesEditables[3].tipoAccion == 'Preventiva' ? (accionesEditables[3].actividadSeleccionada ?? '') : '',
                                'descripcion_4': accionesEditables.length > 3 ? accionesEditables[3].descripcionCtrl.text : '',
                                'responsable_4': accionesEditables.length > 3 ? accionesEditables[3].responsableCtrl.text : '',
                                'fecha_cierre_4': (accionesEditables.length > 3 && accionesEditables[3].fechaCierre != null) ? DateFormat('yyyy-MM-dd').format(accionesEditables[3].fechaCierre!) : null,
                                'estado_accion4': accionesEditables.length > 3 ? accionesEditables[3].estado : '',

                                // RETORNA A REVISIÓN ESTRICTAMENTE
                                'estado_revicion': 'PENDIENTE REVISION',
                                'estado': 'PENDIENTE',
                              };

                              try {
                                await ApiService.actualizar('gestion', '5why', 'id', id, payload);
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte actualizado y enviado a revisión'), backgroundColor: Colors.green));
                                  _cargarDatos();
                                }
                              } catch (e) {
                                setModalState(() => guardando = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red));
                              }
                            },
                            icon: guardando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 16),
                            label: Text(guardando ? 'Enviando...' : 'Guardar y Enviar a Revisión', style: const TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1976D2), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }
    );
  }

  Widget _buildInputTextField(String label, TextEditingController controller, {int maxLines = 1, bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
        ],
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          style: TextStyle(fontSize: 11, color: readOnly ? Colors.black54 : Colors.black87),
          decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: readOnly ? Colors.grey.shade300 : const Color(0xFF1976D2))),
              fillColor: readOnly ? Colors.grey.shade100 : Colors.white,
              filled: true
          ),
        ),
      ],
    );
  }

  Widget _seccionSubtitulo(String titulo, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1976D2), size: 16),
          const SizedBox(width: 8),
          Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _datoRowVisual(String etiqueta, String valor, {bool isBold = false, Color color = Colors.black87}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(etiqueta, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black54))),
          Expanded(child: Text(valor, style: TextStyle(fontSize: 11, color: color, fontWeight: isBold ? FontWeight.w900 : FontWeight.normal))),
        ],
      ),
    );
  }

  // ==========================================
  // EXTRACCIÓN INTELIGENTE DE IMÁGENES PARA EL PDF
  // ==========================================
  Future<Map<int, pw.ImageProvider>> _preDecodificarImagenesParaPDF(Map<String, dynamic> row) async {
    Map<int, pw.ImageProvider> imagenesListas = {};
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      try {
        if (rawEvidencia.contains('http://') || rawEvidencia.contains('https://')) {
          int httpIndex = rawEvidencia.indexOf('http');
          String imageUrl = rawEvidencia.substring(httpIndex).trim();
          imagenesListas[i] = await networkImage(imageUrl);
        } else if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
          final parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
          if (parts.length > 1) {
            String base64String = parts[1];
            int commaIndex = base64String.indexOf('base64,');
            if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
            if (base64String.length > 1000000) continue;
            base64String = base64String.replaceAll(RegExp(r'\s+'), '');
            await Future.delayed(const Duration(milliseconds: 10));
            final imgBytes = base64Decode(base64String);
            imagenesListas[i] = pw.MemoryImage(imgBytes, dpi: 72);
          }
        } else if (rawEvidencia.contains('data:image')) {
          int dataIndex = rawEvidencia.indexOf('data:image');
          String base64String = rawEvidencia.substring(dataIndex);
          int commaIndex = base64String.indexOf('base64,');
          if (commaIndex != -1) base64String = base64String.substring(commaIndex + 7);
          if (base64String.length > 1000000) continue;
          base64String = base64String.replaceAll(RegExp(r'\s+'), '');
          await Future.delayed(const Duration(milliseconds: 10));
          final imgBytes = base64Decode(base64String);
          imagenesListas[i] = pw.MemoryImage(imgBytes, dpi: 72);
        }
      } catch (e) {
        debugPrint('Error procesando imagen PDF $i: $e');
      }
    }
    return imagenesListas;
  }

  List<pw.Widget> _construirPaginasPdf(Map<String, dynamic> row, pw.ImageProvider? imgLogo, Map<int, pw.ImageProvider> imagenesDecodificadas) {
    final boldStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
    const regularStyle = pw.TextStyle(fontSize: 9);
    final greyBg = PdfColors.grey300;
    final darkGreyBg = PdfColors.grey400;

    pw.Widget celdaLabel(String texto, {pw.TextAlign align = pw.TextAlign.center, PdfColor colorTexto = PdfColors.black}) => pw.Container(
      padding: const pw.EdgeInsets.all(5), alignment: align == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(texto, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: colorTexto), textAlign: align),
    );
    pw.Widget celdaValor(String texto) => pw.Container(padding: const pw.EdgeInsets.all(5), alignment: pw.Alignment.centerLeft, child: pw.Text(texto, style: regularStyle));

    List<pw.Widget> evidenciasWidgets = [];
    for (int i = 1; i <= 5; i++) {
      String rawEvidencia = row['evidencia_porque_$i']?.toString() ?? '';
      String textoEvidencia = rawEvidencia;

      if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
        textoEvidencia = rawEvidencia.split('IMAGEN_ADJUNTA:')[0].replaceAll('|', '').trim();
      } else if (rawEvidencia.contains('http')) {
        textoEvidencia = rawEvidencia.substring(0, rawEvidencia.indexOf('http')).replaceAll('|', '').trim();
      } else if (rawEvidencia.contains('data:image')) {
        textoEvidencia = rawEvidencia.substring(0, rawEvidencia.indexOf('data:image')).replaceAll('|', '').trim();
      }

      if (imagenesDecodificadas.containsKey(i)) {
        evidenciasWidgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
          if (textoEvidencia.isNotEmpty) pw.SizedBox(height: 4),
          pw.Center(child: pw.Image(imagenesDecodificadas[i]!, height: 60, fit: pw.BoxFit.contain)),
        ]));
      } else {
        if (rawEvidencia.contains('IMAGEN_ADJUNTA:') || rawEvidencia.contains('http') || rawEvidencia.contains('data:image')) {
          evidenciasWidgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 4),
            pw.Text('[Imagen omitida o muy pesada]', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800)),
          ]));
        } else {
          evidenciasWidgets.add(pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)));
        }
      }
    }

    String fecha = row['fecha']?.toString().split('T')[0] ?? '-';
    String turno = row['turno']?.toString() ?? '-';
    String area = row['area']?.toString() ?? '-';
    String pi = row['pi']?.toString() ?? '-';
    String participantes = row['participantes']?.toString() ?? '-';
    String disparador = row['valor_disparador_alcanzado']?.toString() ?? '-';
    String contencion = row['contencion_problema']?.toString() ?? '-';
    String necesitaInv = (row['requiere_investigacion_adicional']?.toString() ?? 'NO').toUpperCase();
    String causaRaizFormulario = (row['encontro_causa_raiz']?.toString() ?? 'NO').toUpperCase();
    String descripcionCausaRaiz = row['causa_raiz']?.toString() ?? row['causa raiz']?.toString() ?? '-';

    String q1 = row['cumple_flujo_resolucion']?.toString() ?? 'PD';
    String q2 = row['resolucion_primera_linea']?.toString() ?? 'PD';
    String q3 = row['secuencia_tiene_sentido']?.toString() ?? 'PD';
    String q4 = row['porques_con_evidencia']?.toString() ?? 'PD';
    String q5 = row['encontro_causa_raiz_eval']?.toString() ?? row['encontro_causa_raiz']?.toString() ?? 'PD';
    String q6 = row['proponen_acciones_eliminacion']?.toString() ?? 'PD';

    String estadoEval = row['estado']?.toString().toUpperCase() ?? 'PENDIENTE';
    String calificacion = estadoEval == 'PENDIENTE' ? '0.0%' : (row['resultado']?.toString() ?? '0.0%');
    String obsEval = estadoEval == 'PENDIENTE' ? 'Pendiente por revisión' : (row['observacion_evaluador']?.toString() ?? '-');
    String resultado2 = row['resultado_2']?.toString() ?? (estadoEval == 'APTO' ? 'No aplica' : 'Pendiente por revisión');
    String ultimaAprovacion = row['ultima_aprovacion']?.toString() ?? row['ultima aprovacion']?.toString() ?? (estadoEval == 'APTO' ? 'No aplica' : 'Pendiente por revisión');
    String obs2 = row['Observacion 2']?.toString() ?? row['observacion_2']?.toString() ?? '-';

    return [
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1.2), 1: const pw.FlexColumnWidth(3.5), 2: const pw.FlexColumnWidth(1.2) },
          children: [
            pw.TableRow(
                children: [
                  pw.Container(height: 40, padding: const pw.EdgeInsets.all(5), alignment: pw.Alignment.center, child: imgLogo != null ? pw.Image(imgLogo, fit: pw.BoxFit.contain) : pw.SizedBox()),
                  pw.Container(color: greyBg, alignment: pw.Alignment.center, child: pw.Text('Análisis 5 porqués', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))),
                  pw.Container(alignment: pw.Alignment.center, child: pw.Text('ABInBev', style: pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold, fontSize: 14))),
                ]
            )
          ]
      ),
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(2.5), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.5) },
          children: [
            pw.TableRow(children: [ celdaLabel('Fecha:'), celdaValor(fecha), celdaLabel('Turno:'), celdaValor(turno) ]),
            pw.TableRow(children: [ celdaLabel('Área:'), celdaValor(area), celdaLabel('PI:'), celdaValor(pi) ]),
          ]
      ),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(5) }, children: [
        pw.TableRow(children: [ celdaLabel('Participantes:'), celdaValor(participantes) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Información del disparador:', style: boldStyle)) ]),
        pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(disparador, style: regularStyle)) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('¿Qué se hizo para contener el problema y lograr reanudar el proceso?', style: boldStyle)) ]),
        pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(contencion, style: regularStyle)) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('5W', style: boldStyle)) ]),
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), columnWidths: { 0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(2) }, children: [
        pw.TableRow(children: [
          pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Responda los 5 porqués', style: boldStyle)),
          pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Evidencias', style: boldStyle))
        ]),
      ]),
      ...List.generate(5, (index) {
        String pq = row['porque_${index + 1}']?.toString() ?? '';
        String ex = row['explique_porque_${index + 1}']?.toString() ?? '';
        return pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FixedColumnWidth(25), 1: const pw.FixedColumnWidth(65), 2: const pw.FlexColumnWidth(3), 3: const pw.FlexColumnWidth(2) },
            children: [
              pw.TableRow(
                  children: [
                    pw.Container(alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(4), child: pw.Text('${index + 1}', style: regularStyle)),
                    pw.Container(alignment: pw.Alignment.center, padding: const pw.EdgeInsets.all(4), child: pw.Text('¿Por qué?', style: regularStyle)),
                    pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Container(padding: const pw.EdgeInsets.all(4), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.Text(pq.isEmpty ? ' ' : pq, style: boldStyle, textAlign: pw.TextAlign.center)),
                          pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(ex.isEmpty ? ' ' : ex, style: regularStyle)),
                        ]
                    ),
                    pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: evidenciasWidgets[index])
                  ]
              )
            ]
        );
      }),
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1.5), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(3), 4: const pw.FlexColumnWidth(1) },
          children: [
            pw.TableRow(
                children: [
                  pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Cierre del ciclo:', style: boldStyle)),
                  pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('¿Se necesita realizar una\ninvestigación adicional?', style: boldStyle, textAlign: pw.TextAlign.center)),
                  pw.Container(color: necesitaInv == 'SI' ? PdfColors.red : PdfColors.green, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text(necesitaInv, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11))),
                  pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Causa raíz encontrada', style: boldStyle, textAlign: pw.TextAlign.center)),
                  pw.Container(color: causaRaizFormulario == 'SI' ? PdfColors.green : PdfColors.red, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text(causaRaizFormulario, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)))
                ]
            )
          ]
      ),
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(5) },
          children: [
            pw.TableRow(children: [ celdaLabel('Descripción Causa Raíz:'), celdaValor(descripcionCausaRaiz) ]),
          ]
      ),
      pw.SizedBox(height: 5),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), children: [
        pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('ACCIONES', style: boldStyle)) ]),
      ]),
      pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 1),
          columnWidths: { 0: const pw.FlexColumnWidth(1.2), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(3), 3: const pw.FlexColumnWidth(1.5), 4: const pw.FlexColumnWidth(1.2), 5: const pw.FlexColumnWidth(1.2) },
          children: [
            pw.TableRow(
                decoration: pw.BoxDecoration(color: greyBg),
                children: [ celdaLabel('Tipo de accion'), celdaLabel('Aplicar a / Actividad'), celdaLabel('Accion / Descripción'), celdaLabel('Responsable'), celdaLabel('Fecha cierre'), celdaLabel('Estado') ]
            ),
            ...List.generate(4, (index) {
              String tipo = row['accion_${index + 1}']?.toString() ?? '';
              String act = row['actividad_${index + 1}']?.toString() ?? '';
              String desc = row['descripcion_${index + 1}']?.toString() ?? '';
              String resp = row['responsable_${index + 1}']?.toString() ?? '';
              String fCie = row['fecha_cierre_${index + 1}']?.toString().split('T')[0] ?? '';
              String est = row['estado_accion${index + 1}']?.toString() ?? '';

              if (tipo.isEmpty && desc.isEmpty) return pw.TableRow(children: []);
              bool isPreventiva = tipo.toUpperCase() == 'PREVENTIVA';
              bool isConcluida = est.toUpperCase() == 'CONCLUIDA';

              return pw.TableRow(
                  children: [
                    celdaLabel(tipo, align: pw.TextAlign.center),
                    pw.Container(color: isPreventiva ? darkGreyBg : PdfColors.white, padding: const pw.EdgeInsets.all(5), alignment: pw.Alignment.center, child: pw.Text(act.isEmpty ? 'N/A' : act, style: pw.TextStyle(fontSize: 9, fontWeight: isPreventiva ? pw.FontWeight.bold : pw.FontWeight.normal))),
                    celdaValor(desc),
                    celdaValor(resp),
                    celdaValor(fCie),
                    celdaLabel(est.isNotEmpty ? est : 'Pendiente', align: pw.TextAlign.center, colorTexto: isConcluida ? PdfColors.green800 : PdfColors.orange800),
                  ]
              );
            })
          ]
      ),
      if (estadoEval == 'APTO' || estadoEval == 'NO APTO' || estadoEval == 'PENDIENTE') ...[
        pw.SizedBox(height: 15),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            children: [
              pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('EVALUACIÓN DE CALIDAD Y REVISIÓN', style: boldStyle)) ]),
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FlexColumnWidth(5), 1: const pw.FlexColumnWidth(1) },
            children: [
              pw.TableRow(children: [celdaValor('1. ¿Se cumple con el flujo de resolución de problemas (participación adecuada)?'), celdaLabel(q1, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('2. ¿La resolución se llevó a cabo con la primera línea (operadores y técnicos)?'), celdaLabel(q2, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('3. ¿La secuencia de la resolución de problema tiene sentido?'), celdaLabel(q3, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('4. ¿Todos los porqués cuentan con evidencia?'), celdaLabel(q4, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('5. ¿Se encontró causa raíz?'), celdaLabel(q5, align: pw.TextAlign.center)]),
              pw.TableRow(children: [celdaValor('6. ¿Se proponen acciones de eliminación de la causa raíz?'), celdaLabel(q6, align: pw.TextAlign.center)]),
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1) },
            children: [
              pw.TableRow(children: [
                celdaLabel('Calificación Obtenida:'),
                celdaLabel(calificacion, colorTexto: estadoEval == 'APTO' ? PdfColors.green800 : (estadoEval == 'NO APTO' ? PdfColors.red800 : PdfColors.orange800)),
                celdaLabel('Estado Final:'),
                celdaLabel(estadoEval, colorTexto: estadoEval == 'APTO' ? PdfColors.green800 : (estadoEval == 'NO APTO' ? PdfColors.red800 : PdfColors.orange800)),
              ])
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1.5) },
            children: [
              pw.TableRow(children: [
                celdaLabel('Resultado 2:'),
                celdaLabel(resultado2, colorTexto: PdfColors.blue800),
                celdaLabel('Última Aprobación:'),
                celdaLabel(ultimaAprovacion, colorTexto: PdfColors.blue800),
              ])
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            children: [
              pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Observación Evaluador (1ra Revisión):', style: boldStyle)) ]),
              pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obsEval, style: regularStyle)) ]),
            ]
        ),
        pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 1),
            children: [
              pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Observación 2 (2da Revisión):', style: boldStyle)) ]),
              pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obs2, style: regularStyle)) ]),
            ]
        ),
      ]
    ];
  }

  // --- PDF ÚNICO ---
  Future<void> _generarYDescargarPDF(Map<String, dynamic> row) async {
    setState(() { _idGenerandoPdf = row['id'].toString(); });
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      Map<int, pw.ImageProvider> imagenesListas = await _preDecodificarImagenesParaPDF(row);

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) => _construirPaginasPdf(row, imgLogo, imagenesListas),
      ));

      final bytesPdf = await doc.save();
      String areaNom = (row['area']?.toString() ?? 'General').replaceAll(' ', '_');
      String fecha = row['fecha']?.toString().split('T')[0] ?? '-';

      await Printing.sharePdf(bytes: bytesPdf, filename: '5Why_${fecha}_$areaNom.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _idGenerandoPdf = null; });
    }
  }

  // --- PDF MÚLTIPLE MASIVO ---
  Future<void> _descargarMultiplesPDFs() async {
    if (_seleccionados.isEmpty) return;
    setState(() { _generandoMultiplesPdf = true; });
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final doc = pw.Document(compress: false);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      List<Map<String, dynamic>> registrosSeleccionados = _registrosFiltrados.where((r) => _seleccionados.contains(r['id'].toString())).toList();

      for (var row in registrosSeleccionados) {
        Map<int, pw.ImageProvider> imagenesListas = await _preDecodificarImagenesParaPDF(row);
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) => _construirPaginasPdf(row, imgLogo, imagenesListas),
        ));
      }

      final bytesPdf = await doc.save();
      await Printing.sharePdf(bytes: bytesPdf, filename: 'Reporte_Masivo_5Why_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar PDFs múltiples: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _generandoMultiplesPdf = false; });
    }
  }

  // ==========================================
  // CONSTRUCCIÓN DE LA VISTA PRINCIPAL
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(backgroundColor: Color(0xFFF4F6F9), body: Center(child: CircularProgressIndicator(color: Color(0xFF0A2540))));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        leading: IconButton(icon: const Icon(Icons.menu, color: Colors.white), onPressed: widget.onToggleSidebar),
        title: const Text('Historial y Analítica 5 Why', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _cargarDatos)
        ],
      ),
      body: _mensajeError != null
          ? Center(child: Text(_mensajeError!, style: const TextStyle(color: Colors.red)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBarraFiltros(),
            const SizedBox(height: 20),
            _buildDashboardTarjetas(),
            const SizedBox(height: 20),
            _buildTablasResumen(),
            const SizedBox(height: 24),
            _buildTablaDetalle(),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraFiltros() {
    bool hayFiltrosActivos = _fechaDesde != null || _fechaHasta != null || _filtroPI != 'Todos' || _filtroArea != 'Todas' || _busquedaTexto.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF1976D2)),
                  SizedBox(width: 8),
                  Text('Filtros y Búsqueda', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
              if (hayFiltrosActivos)
                InkWell(
                  onTap: _limpiarFiltros,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('🧹 Limpiar Filtros', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _buildFiltroFecha('Fecha Desde', _fechaDesde, (fecha) => setState(() { _fechaDesde = fecha; _aplicarFiltros(); })),
              _buildFiltroFecha('Fecha Hasta', _fechaHasta, (fecha) => setState(() { _fechaHasta = fecha; _aplicarFiltros(); })),
              _buildFiltroDropdown('Área', _listaFiltroArea, _filtroArea, (val) => setState(() { _filtroArea = val!; _aplicarFiltros(); })),
              _buildFiltroDropdown('PI Afectado', _listaFiltroPI, _filtroPI, (val) => setState(() { _filtroPI = val!; _aplicarFiltros(); })),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Buscar (Evento, OPM, Disparador)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 220, height: 35,
                    child: TextField(
                      controller: _buscarCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Escriba aquí...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (v) { _busquedaTexto = v; _aplicarFiltros(); },
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade200)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_rounded, color: Colors.orange, size: 14),
                    const SizedBox(width: 6),
                    Text('Resultados: ${_registrosFiltrados.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroFecha(String label, DateTime? fechaActual, Function(DateTime?) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            DateTime? picked = await showDatePicker(context: context, initialDate: fechaActual ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2101));
            if (picked != null) onSelect(picked);
          },
          child: Container(
            width: 140, height: 35,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4), color: Colors.white),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fechaActual != null ? DateFormat('yyyy-MM-dd').format(fechaActual) : 'DD/MM/AAAA', style: TextStyle(fontSize: 12, color: fechaActual != null ? Colors.black87 : Colors.grey)),
                const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroDropdown(String label, List<String> opciones, String valor, Function(String?) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          width: 160, height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4), color: Colors.white),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: opciones.contains(valor) ? valor : opciones.first,
              isExpanded: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              items: opciones.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: onSelect,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTarjetas() {
    return LayoutBuilder(builder: (context, constraints) {
      double w = constraints.maxWidth;
      int crossAxisCount = w > 800 ? 3 : (w > 500 ? 2 : 1);
      return GridView.count(
        crossAxisCount: crossAxisCount, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 2.5,
        children: [
          _kpiCard('Total Análisis', '$_totalReportes', Icons.assignment_rounded, Colors.blue),
          _kpiCard('Con Causa Raíz', '$_conCausaRaiz', Icons.check_circle_rounded, Colors.green),
          _kpiCard('Sin Causa Raíz', '$_sinCausaRaiz', Icons.warning_rounded, Colors.orange),
        ],
      );
    });
  }

  Widget _kpiCard(String titulo, String valor, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Text(valor, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0A2540))),
            ],
          ),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 24)),
        ],
      ),
    );
  }

  Widget _buildTablasResumen() {
    bool isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      return Column(
        children: [
          _buildTablaTop('Análisis por Área (Top 10)', 'ÁREA', _conteoAreas),
          const SizedBox(height: 16),
          _buildTablaTop('Análisis por PI (Top 10)', 'PI AFECTADO', _conteoPI),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTablaTop('Análisis por Área (Top 10)', 'ÁREA', _conteoAreas)),
          const SizedBox(width: 16),
          Expanded(child: _buildTablaTop('Análisis por PI (Top 10)', 'PI AFECTADO', _conteoPI)),
        ],
      );
    }
  }

  Widget _buildTablaTop(String titulo, String headerCol1, Map<String, int> datos) {
    var top10 = datos.entries.take(10).toList();
    int totalTop = top10.fold(0, (sum, e) => sum + e.value);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
          ),
          Table(
            border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade100)),
            columnWidths: const { 0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1) },
            children: [
              TableRow(
                  decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                  children: [
                    Padding(padding: const EdgeInsets.all(10), child: Text(headerCol1, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold))),
                    const Padding(padding: EdgeInsets.all(10), child: Text('TOTAL', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    const Padding(padding: EdgeInsets.all(10), child: Text('%', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  ]
              ),
              ...top10.map((e) {
                double pct = _totalReportes == 0 ? 0 : (e.value / _totalReportes) * 100;
                return TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(10), child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
                      Padding(padding: const EdgeInsets.all(10), child: Text('${e.value}', style: const TextStyle(fontSize: 11, color: Colors.black87), textAlign: TextAlign.center)),
                      Padding(padding: const EdgeInsets.all(10), child: Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center)),
                    ]
                );
              }),
              TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFE2E8F0)),
                  children: [
                    const Padding(padding: EdgeInsets.all(10), child: Text('TOTALES MOSTRADOS', style: TextStyle(fontSize: 11, color: Color(0xFF1E293B), fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Padding(padding: const EdgeInsets.all(10), child: Text('$totalTop', style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B), fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Padding(padding: const EdgeInsets.all(10), child: Text(_totalReportes == 0 ? '0%' : '${((totalTop / _totalReportes) * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B), fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  ]
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTablaDetalle() {
    int inicio = (_paginaActual - 1) * _registrosPorPagina;
    int fin = min(inicio + _registrosPorPagina, _registrosFiltrados.length);
    List<Map<String, dynamic>> paginaLista = _registrosFiltrados.isEmpty ? [] : _registrosFiltrados.sublist(inicio, fin);
    int totalPaginas = max(1, (_registrosFiltrados.length / _registrosPorPagina).ceil());

    bool todosSeleccionados = paginaLista.isNotEmpty && paginaLista.every((r) => _seleccionados.contains(r['id'].toString()));

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Mostrar ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Container(
                      height: 30, padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _registrosPorPagina,
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                          icon: const Icon(Icons.arrow_drop_down, size: 16),
                          items: [10, 25, 50, 100].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                          onChanged: (v) => setState(() { _registrosPorPagina = v!; _paginaActual = 1; }),
                        ),
                      ),
                    ),
                    const Text(' registros', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_seleccionados.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: _generandoMultiplesPdf ? null : _descargarMultiplesPDFs,
                          icon: _generandoMultiplesPdf
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                          label: Text('Descargar Seleccionados (${_seleccionados.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black87, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                        ),
                      ElevatedButton.icon(
                        onPressed: _descargarExcel,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Descargar Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                      )
                    ]
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Scrollbar(
            controller: _tablaScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _tablaScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 1600),
                child: Table(
                  border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade100)),
                  columnWidths: const {
                    0: FixedColumnWidth(40),
                    1: FixedColumnWidth(80),
                    2: FixedColumnWidth(100),
                    3: FixedColumnWidth(100),
                    4: FlexColumnWidth(2.5),
                    5: FlexColumnWidth(1.5),
                    6: FixedColumnWidth(90),
                    7: FlexColumnWidth(2),
                    8: FlexColumnWidth(2),
                    9: FixedColumnWidth(100),
                    10: FixedColumnWidth(150)
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Checkbox(
                              value: todosSeleccionados,
                              onChanged: paginaLista.isEmpty ? null : (v) => _toggleSeleccionarTodos(paginaLista),
                              activeColor: const Color(0xFF1976D2),
                            ),
                          ),
                          _headerCell('Fecha Evento'), _headerCell('Área'), _headerCell('PI Afectado'), _headerCell('Disparador'), _headerCell('Participantes'), _headerCell('Estado', centrar: true), _headerCell('Observación 1'), _headerCell('Observación 2'), _headerCell('Res. Final', centrar: true), _headerCell('Gestión', centrar: true),
                        ]
                    ),
                    ...paginaLista.map((row) {
                      String idRow = row['id'].toString();

                      String estadoOriginal = (row['estado']?.toString() ?? 'PENDIENTE').toUpperCase();
                      String ultAp = (row['ultima aprovacion']?.toString() ?? row['ultima_aprovacion']?.toString() ?? '').toUpperCase();

                      String obs1 = row['observacion_evaluador']?.toString() ?? '-';
                      if (obs1.trim().isEmpty || obs1 == 'NULL') obs1 = '-';

                      String obs2 = row['Observacion 2']?.toString() ?? row['observacion_2']?.toString() ?? '-';
                      if (obs2.trim().isEmpty || obs2 == 'NULL') obs2 = '-';

                      String estadoMostrar = estadoOriginal;
                      if (estadoOriginal != 'PENDIENTE' && ultAp.isNotEmpty && ultAp != 'NULL' && ultAp != 'NO APLICA' && ultAp != 'PENDIENTE POR REVISIÓN') {
                        estadoMostrar = ultAp;
                      }

                      bool bloqueado = (estadoMostrar == 'APTO' || estadoMostrar == 'APROBADO');

                      Color colorEst;
                      if (estadoMostrar == 'APTO' || estadoMostrar == 'APROBADO') colorEst = Colors.green;
                      else if (estadoMostrar == 'NO APTO' || estadoMostrar == 'NO APROBADO') colorEst = Colors.red;
                      else if (estadoMostrar == 'VOLVER A REVISAR') colorEst = Colors.orange.shade800;
                      else colorEst = Colors.orange;

                      String resFinal = row['ultima aprovacion']?.toString() ?? row['ultima_aprovacion']?.toString() ?? '-';
                      if (resFinal.trim().isEmpty || resFinal == 'NULL') resFinal = '-';

                      Color colorResFinal = Colors.black87;
                      if (resFinal == 'APROBADO' || resFinal == 'APTO') colorResFinal = Colors.green;
                      if (resFinal == 'NO APROBADO' || resFinal == 'NO APTO') colorResFinal = Colors.red;
                      if (resFinal == 'VOLVER A REVISAR') colorResFinal = Colors.orange.shade800;

                      return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Checkbox(
                                value: _seleccionados.contains(idRow),
                                onChanged: (v) => _toggleSeleccion(idRow),
                                activeColor: const Color(0xFF1976D2),
                              ),
                            ),
                            _dataCell(row['fecha']?.toString().split('T')[0] ?? '-'),
                            _dataCell(row['area']?.toString() ?? '-'),
                            _dataCell(row['pi']?.toString() ?? '-', isBold: true),
                            _dataCell(row['valor_disparador_alcanzado']?.toString() ?? '-'),
                            _dataCell(row['participantes']?.toString() ?? '-'),
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                decoration: BoxDecoration(color: colorEst.withOpacity(0.1), border: Border.all(color: colorEst), borderRadius: BorderRadius.circular(4)),
                                child: Text(estadoMostrar, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorEst)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                              child: Text(obs1.trim(), style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                              child: Text(obs2.trim(), style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black54), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                decoration: BoxDecoration(color: colorResFinal != Colors.black87 ? colorResFinal.withOpacity(0.1) : Colors.grey.shade100, border: Border.all(color: colorResFinal != Colors.black87 ? colorResFinal : Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                                child: Text(resFinal, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorResFinal != Colors.black87 ? colorResFinal : Colors.black87)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirModalEdicion(row, bloqueado),
                                    icon: Icon(bloqueado ? Icons.visibility : Icons.edit, size: 14),
                                    label: Text(bloqueado ? 'Ver Detalle' : 'Editar', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(backgroundColor: bloqueado ? Colors.grey.shade300 : const Color(0xFFFFB300), foregroundColor: Colors.black87, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), minimumSize: const Size(0, 30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                                  ),
                                  _idGenerandoPdf == idRow
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                                      : IconButton(
                                    icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 20),
                                    tooltip: 'Descargar PDF',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _generarYDescargarPDF(row),
                                  ),
                                ],
                              ),
                            )
                          ]
                      );
                    })
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mostrando ${paginaLista.isEmpty ? 0 : inicio + 1} a $fin de ${_registrosFiltrados.length} reportes', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Row(
                  children: [
                    InkWell(onTap: _paginaActual > 1 ? () => setState(() => _paginaActual--) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: const Text('Anterior', style: TextStyle(fontSize: 11, color: Colors.blue)))),
                    const SizedBox(width: 4),
                    Text(' $_paginaActual / $totalPaginas ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                    const SizedBox(width: 4),
                    InkWell(onTap: _paginaActual < totalPaginas ? () => setState(() => _paginaActual++) : null, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: const Text('Siguiente', style: TextStyle(fontSize: 11, color: Colors.blue)))),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _headerCell(String text, {bool centrar = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)), textAlign: centrar ? TextAlign.center : TextAlign.left),
    );
  }

  Widget _dataCell(String text, {bool centrar = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Text(text, style: TextStyle(fontSize: 10, color: isBold ? const Color(0xFF1976D2) : Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), textAlign: centrar ? TextAlign.center : TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final int aptos;
  final int noAptos;
  final int pendientes;

  _PieChartPainter({required this.aptos, required this.noAptos, required this.pendientes});

  @override
  void paint(Canvas canvas, Size size) {
    double total = (aptos + noAptos + pendientes).toDouble();
    if (total == 0) return;

    double startAngle = -pi / 2;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..style = PaintingStyle.fill;

    if (aptos > 0) {
      double sweep = (aptos / total) * 2 * pi;
      paint.color = Colors.green;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }

    if (noAptos > 0) {
      double sweep = (noAptos / total) * 2 * pi;
      paint.color = Colors.red;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
      startAngle += sweep;
    }

    if (pendientes > 0) {
      double sweep = (pendientes / total) * 2 * pi;
      paint.color = Colors.orange;
      canvas.drawArc(rect, startAngle, sweep, true, paint);
    }

    final innerPaint = Paint()..style = PaintingStyle.fill..color = Colors.white;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 3.5, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}