import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ IMPORTANTE: Mantén tu IP/dominio tal cual como lo tenías
  static const String baseUrl = 'https://plantatocancipa.site/api/v1/db_logistica';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json; charset=UTF-8',
  };

  // ==========================================
  // CONSULTAR REGISTROS
  // ==========================================
  static Future<dynamic> consultar(String esquema, String tabla) async {
    final url = Uri.parse('$baseUrl/consultar/$esquema/$tabla');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error al consultar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // INSERTAR REGISTRO (Recuperado)
  // ==========================================
  static Future<bool> insertar(String esquema, String tabla, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/insertar/$esquema/$tabla');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(datos),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        throw Exception('Error al insertar: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // ACTUALIZAR REGISTRO
  // ==========================================
  static Future<bool> actualizar(String esquema, String tabla, String idColumna, dynamic idValor, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/actualizar/$esquema/$tabla/$idColumna/$idValor');
    try {
      final response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode(datos),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Error al actualizar: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // ELIMINAR REGISTRO
  // ==========================================
  static Future<bool> eliminar(String esquema, String tabla, String idColumna, dynamic idValor) async {
    final url = Uri.parse('$baseUrl/database/eliminar/$esquema/$tabla/$idColumna/$idValor');
    try {
      final response = await http.delete(url, headers: _headers);
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Error al eliminar: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // SUBIR FOTO MULTIPLATAFORMA
  // ==========================================
  static Future<String?> subirFoto(String nombreCampo, Uint8List bytes, String nombreArchivo) async {
    try {
      final url = Uri.parse('${baseUrl.replaceAll('/db_logistica', '')}/archivos/subir');
      var request = http.MultipartRequest('POST', url);
      request.files.add(http.MultipartFile.fromBytes(nombreCampo, bytes, filename: nombreArchivo));

      var streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200) {
        var response = await http.Response.fromStream(streamedResponse);
        var json = jsonDecode(response.body);
        return json['url'];
      }
    } catch (e) {
      print('Error al subir foto: $e');
    }
    return null;
  }

  // ==========================================
  // SUBIR IMAGEN (Atajo usado por el 5 Why)
  // ==========================================
  static Future<String?> subirImagen(Uint8List bytes) async {
    return await subirFoto('archivo', bytes, 'evidencia_${DateTime.now().millisecondsSinceEpoch}.jpg');
  }

  // ==========================================
  // 🤖 AUDITOR INTELIGENTE (GEMINI IA)
  // ==========================================
  static Future<bool> auditarConIA(String id) async {
    final url = Uri.parse('$baseUrl/auditar/5why/$id');

    try {
      final response = await http.post(url, headers: _headers);

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Fallo en la auditoría IA (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión con el Auditor IA: $e');
    }
  }

}