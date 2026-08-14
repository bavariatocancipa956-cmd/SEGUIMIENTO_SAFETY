import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'https://plantatocancipa.site/api/v1';
  static const String database = 'db_logistica';
  static const String apiKey = 'PlantaLogistica2026*';
  static const String defaultSchema = 'sorting';

  static final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
  };

  // 🟢 CONSULTAR (Parámetros Posicionales)
  static Future<List<dynamic>> consultar(String esquema, String tabla) async {
    return consultarTabla(esquema: esquema, tabla: tabla);
  }

  // 🟢 CONSULTAR TABLA (Parámetros Nombrados)
  static Future<List<dynamic>> consultarTabla({String? esquema, required String tabla}) async {
    final schemaStr = esquema ?? defaultSchema;
    final url = Uri.parse('$baseUrl/$database/consultar/$schemaStr/$tabla');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['exito'] == true && body['data'] != null) {
          return body['data'];
        } else if (body is Map && body['data'] != null) {
          return body['data'];
        } else if (body is List) {
          return body;
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 🔵 INSERTAR (Parámetros Posicionales)
  static Future<Map<String, dynamic>> insertar(String esquema, String tabla, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/$database/insertar/$esquema/$tabla');
    final response = await http.post(url, headers: _headers, body: jsonEncode(datos));
    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['data'] ?? {};
    } else {
      throw Exception('Error guardando datos: ${response.body}');
    }
  }

  // 🔵 INSERTAR TABLA (Parámetros Nombrados)
  static Future<bool> insertarTabla({
    String? esquema,
    required String tabla,
    required Map<String, dynamic> datos,
  }) async {
    final schemaStr = esquema ?? defaultSchema;
    final url = Uri.parse('$baseUrl/$database/insertar/$schemaStr/$tabla');
    final datosLimpios = Map<String, dynamic>.from(datos)..removeWhere((key, value) => value == null);

    try {
      final response = await http.post(url, headers: _headers, body: jsonEncode(datosLimpios));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final resJson = jsonDecode(response.body);
        return resJson['exito'] == true || resJson['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 🔴 ELIMINAR (Parámetros Posicionales)
  static Future<bool> eliminar(String esquema, String tabla, String idColumna, dynamic idValor) async {
    final url = Uri.parse('$baseUrl/$database/eliminar/$esquema/$tabla/$idColumna/$idValor');
    final response = await http.delete(url, headers: _headers);
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Error al eliminar: ${response.body}');
    }
  }

  // 🔴 ELIMINAR TABLA (Parámetros Nombrados)
  static Future<bool> eliminarTabla({
    String? esquema,
    required String tabla,
    required dynamic id,
  }) async {
    final schemaStr = esquema ?? defaultSchema;
    final url = Uri.parse('$baseUrl/$database/borrar/$schemaStr/$tabla/$id');
    try {
      final response = await http.delete(url, headers: _headers);
      return response.statusCode == 200;
    } catch (e) {
      return false;
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