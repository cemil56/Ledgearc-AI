import '../models/cari.dart';
import '../models/cari_hareket.dart';
import '../services/database_service.dart';

class CariRepository {
  final DatabaseService _db = DatabaseService.instance;

  Future<List<Cari>> getCariler(int firmaId) async {
    final db = await _db.getDatabase(firmaId: firmaId);
    final rows = await db.query('cariler', orderBy: 'grup_adi, unvan');
    // fromMap metodu sayesinde Kuruşlar otomatik olarak TL (Double) formatına dönüşür!
    return rows.map((r) => Cari.fromMap(r)).toList();
  }

  Future<int> cariEkle({
    required int firmaId,
    required String unvan,
    required String grupAdi,
    required String vergiNo,
    required String sehir,
  }) async {
    final db = await _db.getDatabase(firmaId: firmaId);
    return await db.insert('cariler', {
      'unvan': unvan,
      'grup_adi': grupAdi,
      'vergi_no': vergiNo.isNotEmpty ? vergiNo : 'Belirtilmedi',
      'sehir': sehir.isNotEmpty ? sehir : 'Genel',
      'bakiye': 0, // Kuruş cinsinden 0
      'olusturma_tarihi': DateTime.now().toIso8601String(),
    });
  }

  Future<List<CariHareket>> getCariHareketler(int firmaId, int cariId) async {
    final db = await _db.getDatabase(firmaId: firmaId);
    final rows = await db.query(
      'cari_hareketler',
      where: 'cari_id = ?',
      whereArgs: [cariId],
      orderBy: 'id DESC',
    );
    // fromMap metodu sayesinde borç ve alacak Kuruş'tan TL'ye çevrildi
    return rows.map((r) => CariHareket.fromMap(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getFaturaKalemleri(
    int firmaId,
    String faturaNo,
  ) async {
    final db = await _db.getDatabase(firmaId: firmaId);
    final stokListesi = await _db.getStokListesi(firmaId: firmaId);
    final stokMap = {for (var s in stokListesi) s['id']: s};

    final hareketlerDb = await db.query(
      'stok_hareketleri',
      where: 'belge_no = ? OR aciklama LIKE ?',
      whereArgs: [faturaNo, '%$faturaNo%'],
    );

    return hareketlerDb.map((h) {
      final stok = stokMap[h['stok_id']] ?? {};
      return {
        'stok_adi': stok['stok_adi'] ?? h['aciklama'] ?? 'Ürün / Hizmet',
        'birim': stok['birim'] ?? 'Adet',
        'miktar': (h['miktar'] as num?)?.toDouble() ?? 1.0,
        // DİKKAT: DB'den dönen stok kuruşlarını burada 100'e bölerek TL yapıyoruz!
        'birimFiyat': h['birim_fiyat'] != null
            ? (h['birim_fiyat'] as num).toDouble() / 100.0
            : (stok['satis_fiyati'] != null
                  ? (stok['satis_fiyati'] as num).toDouble() / 100.0
                  : 0.0),
      };
    }).toList();
  }
}
