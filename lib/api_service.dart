import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'https://plantatocancipa.site/api/v1';
  static const String database = 'db_logistica';
  static const String apiKey = 'PlantaLogistica2026*';

  static final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
  };

  // 🟢 CONSULTAR
  static Future<List<dynamic>> consultar(String esquema, String tabla) async {
    final url = Uri.parse('$baseUrl/$database/consultar/$esquema/$tabla');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['data'];
    } else {
      throw Exception('Error de API: ${response.body}');
    }
  }

  // 🔵 INSERTAR
  static Future<Map<String, dynamic>> insertar(String esquema, String tabla, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/$database/insertar/$esquema/$tabla');
    final response = await http.post(url, headers: _headers, body: jsonEncode(datos));
    if (response.statusCode == 201) {
      return jsonDecode(response.body)['data'];
    } else {
      throw Exception('Error guardando datos: ${response.body}');
    }
  }

  // 🔴 ELIMINAR
  static Future<bool> eliminar(String esquema, String tabla, String idColumna, dynamic idValor) async {
    final url = Uri.parse('$baseUrl/$database/eliminar/$esquema/$tabla/$idColumna/$idValor');
    final response = await http.delete(url, headers: _headers);
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Error al eliminar: ${response.body}');
    }
  }

  // 📸 SUBIR FOTO
  static Future<String?> subirFoto(String nombreCampo, File archivo) async {
    final url = Uri.parse('$baseUrl/archivos/subir');
    var request = http.MultipartRequest('POST', url);
    request.headers.addAll({'x-api-key': apiKey});

    String ext = '.jpg';
    String tipoMime = 'jpeg';
    if (archivo.path.toLowerCase().endsWith('.png')) {
      ext = '.png';
      tipoMime = 'png';
    }

    final bytes = await archivo.readAsBytes();

    request.files.add(http.MultipartFile.fromBytes(
      nombreCampo,
      bytes,
      filename: '${nombreCampo}_${DateTime.now().millisecondsSinceEpoch}$ext',
      contentType: MediaType('image', tipoMime),
    ));

    final response = await request.send();
    final responseData = await response.stream.bytesToString();
    final json = jsonDecode(responseData);

    if (response.statusCode == 200 && json['exito'] == true) {
      return json['urls'][nombreCampo];
    } else {
      final mensajeError = json['error'] ?? responseData;
      throw Exception(mensajeError.toString().trim());
    }
  }

  // ✉️ ENVIAR CORREO
  static Future<void> enviarCorreo({
    required String esquemaCredenciales,
    required String tablaCredenciales,
    required String para,
    required String asunto,
    required String html,
    String? adjuntoBase64,
  }) async {
    final url = Uri.parse('$baseUrl/$database/$esquemaCredenciales/$tablaCredenciales/enviar');

    final Map<String, dynamic> bodyData = {
      'para': para,
      'asunto': asunto,
      'html': html,
    };

    if (adjuntoBase64 != null) {
      bodyData['adjuntoBase64'] = adjuntoBase64;
    }

    final response = await http.post(
      url,
      headers: _headers,
      body: jsonEncode(bodyData),
    );

    if (response.statusCode != 200) {
      throw Exception('Fallo al enviar correo: ${response.body}');
    }
  }
}