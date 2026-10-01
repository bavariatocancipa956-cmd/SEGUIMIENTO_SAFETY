import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math';

import 'api_service.dart';

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

  // Datos Originales y Filtrados
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _registrosFiltrados = [];

  // Set para Selección Múltiple
  Set<String> _seleccionados = {};

  // Filtros
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  String _filtroPI = 'Todos';
  String _filtroArea = 'Todas';
  String _busquedaTexto = '';
  final TextEditingController _buscarCtrl = TextEditingController();

  List<String> _listaFiltroPI = ['Todos'];
  List<String> _listaFiltroArea = ['Todas'];

  // Variables Analíticas
  int _totalReportes = 0;
  int _conCausaRaiz = 0;
  int _sinCausaRaiz = 0;
  Map<String, int> _conteoPI = {};
  Map<String, int> _conteoAreas = {};

  int _registrosPorPagina = 10;
  int _paginaActual = 1;

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
      _seleccionados.clear(); // Limpiar selecciones al filtrar
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

  // ==========================================
  // SELECCIÓN Y EXPORTACIÓN EXCEL
  // ==========================================
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
      String csv = "ID;Fecha;Area;PI Afectado;Participantes;Valor Disparador;Causa Raiz Encontrada;Req. Investigacion Adicional;Estado Evaluacion;Observacion Evaluador;Estado Acciones\n";
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

        int accionesCerradas = 0; int totalAcciones = 0;
        for (int i = 1; i <= 4; i++) {
          if ((r['accion_$i']?.toString() ?? '').isNotEmpty) {
            totalAcciones++;
            if ((r['estado_accion$i']?.toString() ?? '').toUpperCase() == 'CONCLUIDA') accionesCerradas++;
          }
        }
        String estadoAcc = "$accionesCerradas de $totalAcciones cerradas";
        csv += "$id;$f;$a;$p;$part;$disp;$causa;$req;$estEval;$obsEval;$estadoAcc\n";
      }

      List<int> bytes = [0xEF, 0xBB, 0xBF] + utf8.encode(csv);
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'Reporte_5Why_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel generado exitosamente'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al exportar Excel: $e'), backgroundColor: Colors.red));
    }
  }

  // ==========================================
  // CONSTRUCTOR DE PÁGINAS PDF (REUTILIZABLE)
  // ==========================================
  List<pw.Widget> _construirPaginasPdf(Map<String, dynamic> row, pw.ImageProvider? imgLogo) {
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
      if (rawEvidencia.contains('IMAGEN_ADJUNTA:')) {
        final parts = rawEvidencia.split('IMAGEN_ADJUNTA:');
        final textoEvidencia = parts[0].replaceAll('|', '').trim();
        final base64String = parts[1].replaceAll('data:image/jpeg;base64,', '').replaceAll('data:image/png;base64,', '').trim();
        try {
          final img = pw.MemoryImage(base64Decode(base64String), dpi: 72);
          evidenciasWidgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (textoEvidencia.isNotEmpty) pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8)),
            if (textoEvidencia.isNotEmpty) pw.SizedBox(height: 4),
            pw.Center(child: pw.Image(img, height: 60, fit: pw.BoxFit.contain)),
          ]));
        } catch (e) { evidenciasWidgets.add(pw.Text(textoEvidencia, style: const pw.TextStyle(fontSize: 8))); }
      } else {
        evidenciasWidgets.add(pw.Text(rawEvidencia, style: const pw.TextStyle(fontSize: 8)));
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

    // Variables de Evaluación (Si está pendiente, fuerza valores nulos / "PD")
    String q1 = row['cumple_flujo_resolucion']?.toString() ?? 'PD';
    String q2 = row['resolucion_primera_linea']?.toString() ?? 'PD';
    String q3 = row['secuencia_tiene_sentido']?.toString() ?? 'PD';
    String q4 = row['porques_con_evidencia']?.toString() ?? 'PD';
    String q5 = row['encontro_causa_raiz_eval']?.toString() ?? row['encontro_causa_raiz']?.toString() ?? 'PD';
    String q6 = row['proponen_acciones_eliminacion']?.toString() ?? 'PD';

    String estadoEval = row['estado']?.toString().toUpperCase() ?? 'PENDIENTE';
    String calificacion = estadoEval == 'PENDIENTE' ? '0.0%' : (row['resultado']?.toString() ?? '0.0%');
    String obsEval = estadoEval == 'PENDIENTE' ? 'Pendiente por revisión' : (row['observacion_evaluador']?.toString() ?? '-');

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
      ]),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.black, width: 1), columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(5) }, children: [
        pw.TableRow(children: [ celdaLabel('Valor del disparador alcanzado:'), celdaValor(disparador) ]),
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

      // =====================================
      // EVALUACIÓN DE CALIDAD
      // =====================================
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
          children: [
            pw.TableRow(children: [ pw.Container(color: greyBg, padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.centerLeft, child: pw.Text('Observación del Evaluador:', style: boldStyle)) ]),
            pw.TableRow(children: [ pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(obsEval, style: regularStyle)) ]),
          ]
      ),
    ];
  }

  // --- PDF ÚNICO ---
  Future<void> _generarYDescargarPDF(Map<String, dynamic> row) async {
    setState(() { _idGenerandoPdf = row['id'].toString(); });
    try {
      final doc = pw.Document(compress: true);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) => _construirPaginasPdf(row, imgLogo),
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

    try {
      final doc = pw.Document(compress: true);
      pw.ImageProvider? imgLogo;
      try {
        final ByteData data = await rootBundle.load('assets/icono_ol.png');
        imgLogo = pw.MemoryImage(data.buffer.asUint8List());
      } catch (_) {}

      // Filtrar solo los seleccionados
      List<Map<String, dynamic>> registrosSeleccionados = _registrosFiltrados.where((r) => _seleccionados.contains(r['id'].toString())).toList();

      for (var row in registrosSeleccionados) {
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) => _construirPaginasPdf(row, imgLogo),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      onChanged: (v) { _busquedaTexto = v; _aplicarFiltros(); },
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                child: Text('Resultados: ${_registrosFiltrados.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
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
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
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
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6), color: Colors.white),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: opciones.contains(valor) ? valor : opciones.first,
              isExpanded: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)]),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
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
                    Padding(padding: const EdgeInsets.all(12), child: Text(headerCol1, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold))),
                    const Padding(padding: EdgeInsets.all(12), child: Text('TOTAL', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    const Padding(padding: EdgeInsets.all(12), child: Text('%', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  ]
              ),
              ...top10.map((e) {
                double pct = _totalReportes == 0 ? 0 : (e.value / _totalReportes) * 100;
                return TableRow(
                    children: [
                      Padding(padding: const EdgeInsets.all(12), child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
                      Padding(padding: const EdgeInsets.all(12), child: Text('${e.value}', style: const TextStyle(fontSize: 12, color: Colors.black87), textAlign: TextAlign.center)),
                      Padding(padding: const EdgeInsets.all(12), child: Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.black54), textAlign: TextAlign.center)),
                    ]
                );
              }),
              TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFE2E8F0)),
                  children: [
                    const Padding(padding: EdgeInsets.all(12), child: Text('TOTALES MOSTRADOS', style: TextStyle(fontSize: 11, color: Color(0xFF1E293B), fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Padding(padding: const EdgeInsets.all(12), child: Text('$totalTop', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Padding(padding: const EdgeInsets.all(12), child: Text(_totalReportes == 0 ? '0%' : '${((totalTop / _totalReportes) * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B), fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
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
                          items: [10, 25, 50, 100].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                          onChanged: (v) => setState(() { _registrosPorPagina = v!; _paginaActual = 1; }),
                        ),
                      ),
                    ),
                    const Text(' registros', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Row(
                    children: [
                      if (_seleccionados.isNotEmpty) ...[
                        ElevatedButton.icon(
                          onPressed: _generandoMultiplesPdf ? null : _descargarMultiplesPDFs,
                          icon: _generandoMultiplesPdf
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                          label: Text('Descargar Seleccionados (${_seleccionados.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black87, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: _descargarExcel,
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Descargar Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
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
                constraints: const BoxConstraints(minWidth: 1000),
                child: Table(
                  border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade100)),
                  columnWidths: const {
                    0: FixedColumnWidth(50),  // CHECKBOX
                    1: FixedColumnWidth(90),  // FECHA
                    2: FixedColumnWidth(110), // AREA
                    3: FixedColumnWidth(130), // PI
                    4: FlexColumnWidth(2),    // DISPARADOR
                    5: FlexColumnWidth(1.5),  // PARTICIPANTES
                    6: FixedColumnWidth(100)  // GESTION
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
                          _headerCell('Fecha Evento'), _headerCell('Área'), _headerCell('PI Afectado'), _headerCell('Disparador'), _headerCell('Participantes'), _headerCell('Gestión', centrar: true),
                        ]
                    ),
                    ...paginaLista.map((row) {
                      String idRow = row['id'].toString();
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _idGenerandoPdf == idRow
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                                      : ElevatedButton.icon(
                                    onPressed: () => _generarYDescargarPDF(row),
                                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
                                    label: const Text('PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red.shade800, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), minimumSize: const Size(0, 28)),
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
      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)), textAlign: centrar ? TextAlign.center : TextAlign.left),
    );
  }

  Widget _dataCell(String text, {bool centrar = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Text(text, style: TextStyle(fontSize: 12, color: isBold ? const Color(0xFF1976D2) : Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), textAlign: centrar ? TextAlign.center : TextAlign.left, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}