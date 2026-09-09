import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Windows development client. Provider credentials belong to the local server.
/// Name retained to keep existing imports compatible.
class GeminiService {
  static const _token = String.fromEnvironment('LEDGERARC_LOCAL_TOKEN');
  static const _maxBytes = 8 * 1024 * 1024;
  static const _types = {
    'pdf': 'application/pdf', 'png': 'image/png',
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'webp': 'image/webp',
    'm4a': 'audio/mp4', 'mp3': 'audio/mpeg', 'wav': 'audio/wav',
    'aac': 'audio/aac', 'ogg': 'audio/ogg', 'flac': 'audio/flac',
  };

  static Future<Map<String, dynamic>> _request(
    String route, String prompt, List<File> files,
  ) async {
    if (_token.isEmpty) {
      throw const FormatException('Uygulamayı yerel AI başlatıcısıyla açın.');
    }
    if (files.length > 4 || prompt.length > 12000) {
      throw const FormatException('En fazla 4 dosya ve 12000 karakter gönderilebilir.');
    }
    final encoded = <Map<String, String>>[];
    var total = 0;
    for (final file in files) {
      final ext = file.path.toLowerCase().split('.').last;
      final mime = _types[ext];
      if (mime == null) throw const FormatException('Bu dosya türü desteklenmiyor.');
      final length = await file.length();
      if (length == 0 || total + length > _maxBytes) {
        throw const FormatException('Dosyalar boş olmamalı; toplam boyut en fazla 8 MB olabilir.');
      }
      final bytes = await file.readAsBytes();
      total += bytes.length;
      if (bytes.isEmpty || total > _maxBytes) {
        throw const FormatException('Dosya boyutu sınırı aşıldı.');
      }
      encoded.add({'mimeType': mime, 'data': base64Encode(bytes)});
    }
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.http('127.0.0.1:8765', route),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
        body: jsonEncode({'prompt': prompt, 'files': encoded}),
      ).timeout(const Duration(seconds: 80));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('AI servisinin yanıtı okunamadı.');
      }
      if (response.statusCode != 200) {
        final message = decoded['reply'] is String
            ? decoded['reply'] as String : 'AI işlemi tamamlanamadı.';
        final code = decoded['error_code']?.toString() ?? 'AI_ERROR';
        throw FormatException('$message (Kod: $code)');
      }
      return decoded;
    } finally {
      client.close();
    }
  }

  static String _error(Object error) {
    if (error is TimeoutException) return 'AI yanıtı zamanında gelmedi. Tekrar deneyebilirsiniz.';
    if (error is SocketException || error is http.ClientException) {
      return 'Yerel AI servisine bağlanılamadı. 2-SERVISI-BASLAT.cmd penceresinin açık olduğunu kontrol edin.';
    }
    if (error is FileSystemException) return 'Seçilen dosya okunamadı. Dosyayı yeniden seçin.';
    if (error is FormatException) return error.message;
    return 'AI işlemi tamamlanamadı. Yeniden deneyin.';
  }

  static Future<Map<String, dynamic>> analizEt({
    required String prompt, List<File> dosyalar = const [],
  }) async {
    try {
      final response = await _request('/analyze', prompt, dosyalar);
      if (response['items'] is! List || response['reply'] is! String) {
        throw const FormatException('AI yanıtında gerekli alanlar eksik.');
      }
      return response;
    } catch (error) {
      return {'reply': _error(error), 'items': <dynamic>[]};
    }
  }

  static Future<String> sesiYaziyaCevir(File sesDosyasi) async {
    try {
      final response = await _request('/transcribe', 'Konuşmayı metne dönüştür.', [sesDosyasi]);
      if (response['text'] is! String || (response['text'] as String).trim().isEmpty) {
        throw const FormatException('Ses kaydından metin çıkarılamadı.');
      }
      return response['text'] as String;
    } catch (error) {
      throw FormatException(_error(error));
    }
  }
}
