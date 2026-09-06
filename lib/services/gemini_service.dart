import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'rag_service.dart';

class GeminiService {
  // Sizin OAuth 2.0 Access Token'ınız
  static const String apiKey = "";

  // SADECE GEMINI 3 VE ÜZERİ MODELLER
  static const List<String> modellerHavuzu = [
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
  ];

  static const String sistemPrompt = """
Sen LedgerArc AI Kurumsal Baş Muhasebe, Depo ve Fatura Analiz Danışmanısın.

ÇIKTI KURALI:
- Yanıtın YALNIZCA geçerli bir JSON nesnesi veya JSON DİZİSİ [ {...} ] olmalıdır. Markdown etiketi (```json) ekleme.

ÖNEMLİ KATEGORİZASYON VE CARİ KURALI:
Tüm talepleri analiz ederken şu 5 kategoriden birini "islem_kategorisi" olarak belirle:
1. "ISLETME_GIDERI": Perakende fişler, akaryakıt, yemek, noter, fatura.
2. "PERSONEL": Maaş, avans, işçi ödemeleri.
3. "TICARI_CARI": Toptan mal/hizmet alım-satım faturaları.
4. "CEK_SENET": Çek/senet alınması veya verilmesi işlemleri.
5. "STOK_DEPO_ISLEMI": Depoya yeni mal/ürün eklemek, fiyat güncellemek veya giriş/çıkış yapmak isterse (YENİ).

GÖREVLER:
1. İŞLEM / FATURA / ÇEK-SENET TALEPLERİ (Kategori 1-4):
   - "is_action": true
   - "islem_kategorisi": "ISLETME_GIDERI" | "PERSONEL" | "TICARI_CARI" | "CEK_SENET"
   - "vkn": Belge üzerinde 10 haneli VKN veya 11 haneli TCKN varsa BİREBİR yaz. YOKSA KESİNLİKLE UYDURMA, alanı tamamen boş ("") bırak.
   - "tutar": Sayısal float
   - Diğer muhasebe alanları...

2. STOK VE DEPO TALEPLERİ (Kategori 5):
   - "is_action": true
   - "islem_kategorisi": "STOK_DEPO_ISLEMI"
   - "action_type": "YENI_STOK_KARTI" veya "FIYAT_GUNCELLE" veya "STOK_GIRIS" veya "STOK_CIKIS"
   - "stok_adi": Ürünün adı (Örn: "DN 150 Çelik Flanş", "Matkap")
   - "alis_fiyati": Sayısal float (varsa)
   - "satis_fiyati": Sayısal float (varsa)
   - "miktar": (Sayısal float) Girilecek veya çıkacak adet.
   - "summary": İşlem özeti

3. GENEL SOHBET:
   - "is_action": false
   - "reply": Esnaf diline uygun profesyonel yanıt.
""";

  static Future<String> sesiYaziyaCevir(File sesDosyasi) async {
    try {
      final bytes = await sesDosyasi.readAsBytes();
      final base64Audio = base64Encode(bytes);

      final ilkModel = modellerHavuzu.first;

      final url = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/$ilkModel:generateContent",
      );

      final response = await http
          .post(
            url,
            // OAuth Token için Bearer formatı
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {
                      "text": "Bu ses kaydındaki konuşmayı kelimesi kelimesine Türkçe metne dönüştür. Muhasebe ve ticari terimleri doğru yaz.",
                    },
                    {
                      "inline_data": {
                        "mime_type": "audio/mp4",
                        "data": base64Audio,
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates']?[0]?['content']?['parts']?[0]?['text']
                ?.toString()
                .trim() ??
            '';
      } else {
        debugPrint(
          "Gemini Ses Çeviri Hatası: ${response.statusCode} -${response.body}",
        );
      }
    } catch (e) {
      debugPrint("Gemini Ses Bağlantı Hatası: $e");
    }
    return '';
  }

  static Future<Map<String, dynamic>> analizEt({
    required String prompt,
    List<File> dosyalar = const [],
  }) async {
    final baglam = RagService.baglamUret(prompt);
    final nihaiPrompt = baglam.isNotEmpty
        ? "Kullanıcı Talebi: $prompt\n\nBağlam:\n$baglam"
        : "Kullanıcı Talebi: $prompt";

    final List<Map<String, dynamic>> parts = [];

    for (var f in dosyalar) {
      final bytes = await f.readAsBytes();
      final mime = f.path.toLowerCase().endsWith(".pdf")
          ? "application/pdf"
          : "image/jpeg";
      parts.add({
        "inlineData": {"mimeType": mime, "data": base64Encode(bytes)},
      });
    }
    parts.add({"text": nihaiPrompt});

    final payload = {
      "systemInstruction": {
        "parts": [
          {"text": sistemPrompt},
        ],
      },
      "contents": [
        {"parts": parts},
      ],
      "generationConfig": {
        "responseMimeType": "application/json",
        "temperature": 0.1,
      },
    };

    // OAuth Token için Bearer formatı
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $apiKey",
    };

    for (var modelName in modellerHavuzu) {
      try {
        debugPrint("🤖 Denenen Model: $modelName");

        final url = Uri.parse(
          "[https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent]",
        );

        final response = await http
            .post(url, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final resJson = jsonDecode(response.body);
          final rawText =
              resJson["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ??
              "";
          final parsed = _guvenliJsonCoz(rawText);
          List<dynamic> items = [];
          String reply = "";

          if (parsed is List) {
            items = parsed;
            reply = items.isNotEmpty
                ? (items.first['reply']?.toString() ?? '')
                : '';
          } else if (parsed is Map<String, dynamic>) {
            if (parsed.containsKey('items') && parsed['items'] is List) {
              items = parsed['items'];
              reply = parsed['reply']?.toString() ?? '';
            } else {
              items = [parsed];
              reply = parsed['reply']?.toString() ?? '';
            }
          }
          debugPrint("✅ $modelName modelinden başarıyla yanıt alındı.");
          return {"reply": reply, "items": items};
        } else {
          debugPrint(
            "⚠️ Model $modelName reddetti: HTTP${response.statusCode}",
          );
          debugPrint("Hata detayı: ${response.body}");
          continue;
        }
      } catch (e) {
        debugPrint("⏳ Model $modelName 10 saniyede cevap veremedi:$e");
        continue;
      }
    }

    return {
      "reply": "Yapay zeka modellerinin tümü 10 saniyede yanıt veremedi veya yetkilendirme onaylanmadı.",
      "items": [],
    };
  }

  static dynamic _guvenliJsonCoz(String rawText) {
    if (rawText.trim().isEmpty) {
      return {"is_action": false, "reply": ""};
    }
    String temiz = rawText
        .replaceAll(RegExp(r'```(?:json)?'), '')
        .replaceAll('`', '')
        .trim();
    try {
      return jsonDecode(temiz);
    } catch (_) {}
    final match = RegExp(r'(\[.*\]|\{.*\})', dotAll: true).firstMatch(temiz);
    if (match != null) {
      try {
        return jsonDecode(match.group(0)!);
      } catch (_) {}
    }
    return {"is_action": false, "reply": rawText.trim()};
  }
}
