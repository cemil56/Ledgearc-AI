import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  final Map<int, Database> _dbPool = {};

  DatabaseService._init();

  // 🚨 GÜVENLİ PARA ÇEVİRİCİ: Virgülleri, çift sıfırları hatasız okur!
  static double parsePara(dynamic val) {
    if (val == null) {
      return 0.0;
    }
    if (val is num) {
      return val.toDouble();
    }
    String text = val.toString().trim();
    if (text.isEmpty) {
      return 0.0;
    }
    String temiz = text.replaceAll('₺', '').replaceAll('TL', '').trim();
    if (temiz.contains('.') && temiz.contains(',')) {
      if (temiz.indexOf('.') < temiz.indexOf(',')) {
        temiz = temiz.replaceAll('.', '').replaceAll(',', '.');
      } else {
        temiz = temiz.replaceAll(',', '');
      }
    } else if (temiz.contains(',')) {
      temiz = temiz.replaceAll(',', '.');
    }
    return double.tryParse(temiz) ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getCekSenetListesi({
    int firmaId = 1,
    String? durum,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    if (durum != null && durum.isNotEmpty) {
      return await db.query(
        'cek_senet_bordro',
        where: 'durum = ?',
        whereArgs: [durum],
        orderBy: 'vade_tarihi ASC',
      );
    }
    return await db.query('cek_senet_bordro', orderBy: 'vade_tarihi ASC');
  }

  static String trKucuk(String text) {
    if (text.isEmpty) {
      return '';
    }
    const Map<String, String> donusum = {
      'İ': 'i',
      'I': 'ı',
      'Ş': 'ş',
      'Ğ': 'ğ',
      'Ü': 'ü',
      'Ö': 'ö',
      'Ç': 'ç',
    };
    String sonuc = text;
    donusum.forEach((k, v) => sonuc = sonuc.replaceAll(k, v));
    return sonuc.toLowerCase();
  }

  static String _temizleUnvan(String text) {
    return text
        .toLowerCase()
        .replaceAll('i̇', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(
          RegExp(
            r'\b(san|tic|ltd|sti|şirketi|sirketi|a\.s|as|ve|endustriyel|insaat|grup|holding)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'[^a-z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<Map<String, dynamic>>> benzerCarileriBul({
    required String gelenUnvan,
    String? vkn,
    required int firmaId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    if (vkn != null && vkn.trim().isNotEmpty && vkn != 'Belirtilmedi') {
      final vknMatch = await db.query(
        'cariler',
        where: 'vergi_no = ?',
        whereArgs: [vkn.trim()],
      );
      if (vknMatch.isNotEmpty) {
        return [vknMatch.first];
      }
    }
    final cariler = await db.query('cariler');
    if (cariler.isEmpty) {
      return [];
    }
    final temizGelen = _temizleUnvan(gelenUnvan);
    final gelenKelimeler = temizGelen
        .split(' ')
        .where((k) => k.length > 2)
        .toList();
    List<Map<String, dynamic>> adaylar = [];
    for (var cari in cariler) {
      final mevcutUnvan = cari['unvan'].toString();
      final temizMevcut = _temizleUnvan(mevcutUnvan);
      if (temizMevcut == temizGelen ||
          temizMevcut.contains(temizGelen) ||
          temizGelen.contains(temizMevcut)) {
        adaylar.add(cari);
        continue;
      }
      int puan = 0;
      for (var kelime in gelenKelimeler) {
        if (temizMevcut.contains(kelime)) {
          puan += kelime.length;
        }
      }
      if (puan >= 3) {
        adaylar.add(cari);
      }
    }
    return adaylar;
  }

  Future<Map<String, dynamic>?> akilliCariBul({
    required String gelenUnvan,
    String? vkn,
    required int firmaId,
  }) async {
    final adaylar = await benzerCarileriBul(
      gelenUnvan: gelenUnvan,
      vkn: vkn,
      firmaId: firmaId,
    );
    if (adaylar.length == 1) {
      return adaylar.first;
    }
    return null;
  }

  static String grupAdiCikar(String unvan) {
    final temiz = unvan.replaceAll(
      RegExp(
        r'(ltd\.?\s*şti\.?|a\.?ş\.?|şirketi|ticaret|sanayi|endüstriyel|inşaat|makina|makine|elektrik|şahıs|malzemeleri|yapı|taah\.|ve)',
        caseSensitive: false,
      ),
      '',
    );
    final kelimeler = temiz
        .split(' ')
        .map((k) => k.trim())
        .where((k) => k.length > 2)
        .toList();
    if (kelimeler.isNotEmpty) {
      final ilk = kelimeler.first;
      return '${ilk[0].toUpperCase()}${ilk.substring(1)} Grubu';
    }
    return 'Genel Cari Grubu';
  }

  Future<Map<String, dynamic>?> mukerrerFaturaKontrol({
    required String faturaNo,
    required int firmaId,
    String? vkn,
    double? tutar,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    List<Map<String, dynamic>> sonuclar = await db.query(
      'cari_hareketler',
      where: 'fatura_no = ?',
      whereArgs: [faturaNo],
      limit: 1,
    );
    if (sonuclar.isNotEmpty) {
      return sonuclar.first;
    }
    if (vkn != null && vkn.isNotEmpty && tutar != null && tutar > 0) {
      sonuclar = await db.rawQuery(
        '''SELECT ch.* FROM cari_hareketler ch JOIN cariler c ON c.id = ch.cari_id WHERE c.vergi_no = ? AND (ch.borc = ? OR ch.alacak = ?) LIMIT 1''',
        [vkn, (tutar * 100).round(), (tutar * 100).round()],
      );
      if (sonuclar.isNotEmpty) {
        return sonuclar.first;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> kasaBankaHareketleriGetir({
    required int firmaId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    try {
      return await db.rawQuery(
        '''SELECT id, hesap_kodu, hesap_adi, borc, alacak, tarih, aciklama, fis_no as fatura_no FROM yevmiye_kayitlari WHERE hesap_kodu LIKE '100%' OR hesap_kodu LIKE '102%' ORDER BY id DESC LIMIT 50''',
      );
    } catch (_) {
      return await db.rawQuery(
        '''SELECT ch.id, CASE WHEN ch.odeme_yontemi = 'NAKİT' THEN '100' ELSE '102' END as hesap_kodu, CASE WHEN ch.odeme_yontemi = 'NAKİT' THEN 'Kasa Hesabı' ELSE 'Banka Hesabı' END as hesap_adi, ch.borc, ch.alacak, ch.tarih, ch.aciklama, ch.fatura_no FROM cari_hareketler ch WHERE ch.odeme_yontemi IN ('NAKİT', 'HAVALE', 'EFT', 'KREDİ_KARTI') ORDER BY ch.id DESC LIMIT 50''',
      );
    }
  }

  Future<int> cekSenetKaydet({
    required int firmaId,
    int? cariId,
    required String kesideci,
    String vkn = '',
    required String evrakTuru,
    required String evrakNo,
    required String bankaAdi,
    required double tutar,
    required String vadeTarihi,
    required String? belgeYolu,
    String? karekodIcerik,
    int? riskSkoru,
    String? riskDurumu,
    String? aiRiskYorumu,
    List<Map<String, dynamic>> yevmiyeMaddeleri = const [],
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final simdi = DateTime.now().toIso8601String();
    final int tutarKurus = (tutar * 100).round();

    int finalCariId = cariId ?? 0;
    return await db.transaction((txn) async {
      if (finalCariId <= 0) {
        final tamEslesen = await txn.query(
          'cariler',
          where: 'unvan = ?',
          whereArgs: [kesideci.trim()],
        );
        if (tamEslesen.isNotEmpty) {
          finalCariId = tamEslesen.first['id'] as int;
          if (vkn.isNotEmpty &&
              tamEslesen.first['vergi_no'] == 'Belirtilmedi') {
            await txn.update(
              'cariler',
              {'vergi_no': vkn},
              where: 'id = ?',
              whereArgs: [finalCariId],
            );
          }
        } else {
          finalCariId = await txn.insert('cariler', {
            'unvan': kesideci.trim(),
            'grup_adi': grupAdiCikar(kesideci),
            'vergi_no': vkn.isNotEmpty ? vkn : 'Belirtilmedi',
            'sehir': 'Genel',
            'bakiye': 0,
            'olusturma_tarihi': simdi,
          });
        }
      }

      final bool isMusteriCeki = evrakTuru == 'MUSTERI_CEKI';
      final hareketId = await txn.insert('cari_hareketler', {
        'cari_id': finalCariId,
        'tarih': simdi.substring(0, 10),
        'vade_tarihi': vadeTarihi,
        'fatura_no': evrakNo,
        'odeme_yontemi': evrakTuru.contains('CEK') ? 'CEK' : 'SENET',
        'islem_turu': isMusteriCeki ? 'TAHSİLAT' : 'TEDİYE',
        'borc': isMusteriCeki ? 0 : tutarKurus,
        'alacak': isMusteriCeki ? tutarKurus : 0,
        'aciklama': '$kesideci - $bankaAdi (Çek No: $evrakNo)',
        'belge_yolu': belgeYolu,
      });

      final cariRows = await txn.query(
        'cariler',
        where: 'id = ?',
        whereArgs: [finalCariId],
      );
      if (cariRows.isNotEmpty) {
        final int mevcutBakiye = (cariRows.first['bakiye'] as int?) ?? 0;
        await txn.update(
          'cariler',
          {'bakiye': mevcutBakiye + (isMusteriCeki ? -tutarKurus : tutarKurus)},
          where: 'id = ?',
          whereArgs: [finalCariId],
        );
      }

      final cekId = await txn.insert('cek_senet_bordro', {
        'cari_id': finalCariId,
        'hareket_id': hareketId,
        'evrak_turu': evrakTuru,
        'evrak_no': evrakNo,
        'banka_adi': bankaAdi,
        'kesideci': kesideci,
        'tutar': tutarKurus,
        'vade_tarihi': vadeTarihi,
        'belge_yolu': belgeYolu,
        'durum': 'PORTFOYDE',
        'olusturma_tarihi': simdi,
      });

      if (yevmiyeMaddeleri.isNotEmpty) {
        final fisNo = await _yeniFisNoGetir(txn);

        for (var m in yevmiyeMaddeleri) {
          final double yBorc = (m['borc'] as num?)?.toDouble() ?? 0.0;
          final double yAlacak = (m['alacak'] as num?)?.toDouble() ?? 0.0;
          await txn.insert('yevmiye_kayitlari', {
            'hareket_id': hareketId,
            'fis_no': fisNo,
            'tarih': simdi.substring(0, 10),
            'hesap_kodu': m['kod'] ?? '101',
            'hesap_adi': m['ad'] ?? 'Muhtelif Hesap',
            'borc': (yBorc * 100).round(),
            'alacak': (yAlacak * 100).round(),
            'aciklama': '$evrakNo - $kesideci',
          });
        }
      }
      return cekId;
    });
  }

  Future<void> cekSenetDurumGuncelle({
    required int firmaId,
    required int cekId,
    required String yeniDurum,
    required String odemeYeri,
    String? bankaAdi,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final simdi = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final evraklar = await txn.query(
        'cek_senet_bordro',
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.isEmpty) {
        return;
      }
      final evrak = evraklar.first;
      final tutarKurus = (evrak['tutar'] as int?) ?? 0;
      final evrakTuru = evrak['evrak_turu']?.toString() ?? '';
      final evrakNo = evrak['evrak_no']?.toString() ?? '';
      final kesideci = evrak['kesideci']?.toString() ?? '';
      final bool isAlinan = evrakTuru.contains('MUSTERI');
      final bool isSenet = evrakTuru.contains('SENET');

      await txn.update(
        'cek_senet_bordro',
        {'durum': yeniDurum},
        where: 'id = ?',
        whereArgs: [cekId],
      );

      if (yeniDurum == 'TAHSIL_EDILDI' || yeniDurum == 'ODENDI') {
        final karsiKod = odemeYeri == 'KASA' ? '100' : '102';
        final karsiAd = odemeYeri == 'KASA'
            ? 'Kasa Hesabı'
            : (bankaAdi != null && bankaAdi.isNotEmpty
                  ? 'Banka Hesabı ($bankaAdi)'
                  : 'Banka Hesabı');
        final fisNo = await _yeniFisNoGetir(txn);
        List<Map<String, dynamic>> yevmiye = [];

        if (isAlinan) {
          final portfoyKod = isSenet ? '121' : '101';
          final portfoyAd = isSenet ? 'Alacak Senetleri' : 'Alınan Çekler';
          yevmiye = [
            {'kod': karsiKod, 'ad': karsiAd, 'borc': tutarKurus, 'alacak': 0},
            {
              'kod': portfoyKod,
              'ad': portfoyAd,
              'borc': 0,
              'alacak': tutarKurus,
            },
          ];
        } else {
          final borcKod = isSenet ? '321' : '103';
          final borcAd = isSenet ? 'Borç Senetleri' : 'Verilen Çekler (-)';
          yevmiye = [
            {'kod': borcKod, 'ad': borcAd, 'borc': tutarKurus, 'alacak': 0},
            {'kod': karsiKod, 'ad': karsiAd, 'borc': 0, 'alacak': tutarKurus},
          ];
        }
        for (var m in yevmiye) {
          await txn.insert('yevmiye_kayitlari', {
            'hareket_id': cekId,
            'fis_no': fisNo,
            'tarih': simdi.substring(0, 10),
            'hesap_kodu': m['kod'],
            'hesap_adi': m['ad'],
            'borc': m['borc'],
            'alacak': m['alacak'],
            'aciklama': '$evrakNo - $kesideci Evrak Kapanışı',
          });
        }
      }
    });
  }

  Future<Database> getDatabase({int firmaId = 1}) async {
    if (_dbPool.containsKey(firmaId)) {
      return _dbPool[firmaId]!;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final firmalarDir = Directory(
      join(docsDir.path, 'LedgerArc', 'db_firmalar'),
    );
    if (!await firmalarDir.exists()) {
      await firmalarDir.create(recursive: true);
    }
    final path = join(firmalarDir.path, 'firma_$firmaId.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => _createTables(db),
    );
    await _createTables(db);
    _dbPool[firmaId] = db;
    return db;
  }

  Future<List<Map<String, dynamic>>> cariHareketleriGetir(
    int cariId, {
    int firmaId = 1,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    return await db.query(
      'cari_hareketler',
      where: 'cari_id = ?',
      whereArgs: [cariId],
      orderBy: 'id DESC',
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS cariler (id INTEGER PRIMARY KEY AUTOINCREMENT, unvan TEXT UNIQUE NOT NULL, grup_adi TEXT DEFAULT '', vergi_no TEXT DEFAULT '', sehir TEXT DEFAULT 'Genel', bakiye INTEGER DEFAULT 0, olusturma_tarihi TEXT)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS cek_senet_bordro (id INTEGER PRIMARY KEY AUTOINCREMENT, cari_id INTEGER, hareket_id INTEGER, evrak_turu TEXT, evrak_no TEXT, banka_adi TEXT, sube_adi TEXT, hesap_no TEXT, kesideci TEXT, tutar INTEGER DEFAULT 0, vade_tarihi TEXT, belge_yolu TEXT, durum TEXT DEFAULT 'PORTFOYDE', karekod_icerik TEXT, risk_skoru INTEGER, risk_durumu TEXT, ai_risk_yorumu TEXT, rapor_pdf_yolu TEXT, olusturma_tarihi TEXT, FOREIGN KEY (cari_id) REFERENCES cariler (id))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS cari_hareketler (id INTEGER PRIMARY KEY AUTOINCREMENT, cari_id INTEGER, fatura_no TEXT DEFAULT '', tarih TEXT, vade_tarihi TEXT DEFAULT '', odeme_yontemi TEXT DEFAULT 'AÇIK_HESAP', islem_turu TEXT, borc INTEGER DEFAULT 0, alacak INTEGER DEFAULT 0, aciklama TEXT, belge_yolu TEXT, FOREIGN KEY (cari_id) REFERENCES cariler(id))''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS yevmiye_kayitlari (id INTEGER PRIMARY KEY AUTOINCREMENT, hareket_id INTEGER, fis_no TEXT, tarih TEXT, hesap_kodu TEXT, hesap_adi TEXT, borc INTEGER DEFAULT 0, alacak INTEGER DEFAULT 0, aciklama TEXT, belge_yolu TEXT, FOREIGN KEY (hareket_id) REFERENCES cari_hareketler(id) ON DELETE CASCADE)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS depolar (id INTEGER PRIMARY KEY AUTOINCREMENT, depo_adi TEXT NOT NULL, konum TEXT, varsayilan INTEGER DEFAULT 0)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS stok_kartlari (id INTEGER PRIMARY KEY AUTOINCREMENT, stok_kodu TEXT UNIQUE NOT NULL, stok_adi TEXT NOT NULL, birim TEXT DEFAULT 'Adet', kdv_orani REAL DEFAULT 20.0, hesap_kodu TEXT DEFAULT '153', alis_fiyati INTEGER DEFAULT 0, satis_fiyati INTEGER DEFAULT 0, kritik_seviye REAL DEFAULT 0.0)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS stok_hareketleri (id INTEGER PRIMARY KEY AUTOINCREMENT, stok_id INTEGER NOT NULL, depo_id INTEGER NOT NULL, hedef_depo_id INTEGER, hareket_tipi TEXT NOT NULL, miktar REAL NOT NULL, birim_fiyat INTEGER NOT NULL, toplam_tutar INTEGER NOT NULL, tarih TEXT NOT NULL, belge_no TEXT, aciklama TEXT, FOREIGN KEY (stok_id) REFERENCES stok_kartlari (id) ON DELETE CASCADE, FOREIGN KEY (depo_id) REFERENCES depolar (id))''',
    );
    await db.insert('depolar', {
      'depo_adi': 'Merkez Depo',
      'konum': 'Genel Merkez',
      'varsayilan': 1,
    });
  }

  Future<Map<String, dynamic>?> faturaVarMi(
    String faturaNo, {
    int firmaId = 1,
  }) async {
    if (faturaNo.trim().length < 4) {
      return null;
    }
    final db = await getDatabase(firmaId: firmaId);
    final list = await db.rawQuery(
      '''SELECT h.fatura_no, h.tarih, h.borc, h.alacak, h.aciklama, c.unvan FROM cari_hareketler h JOIN cariler c ON c.id = h.cari_id WHERE UPPER(TRIM(h.fatura_no)) = UPPER(TRIM(?))''',
      [faturaNo.trim()],
    );
    if (list.isNotEmpty) {
      final kayit = list.first;
      final borc = ((kayit['borc'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final alacak = ((kayit['alacak'] as num?)?.toDouble() ?? 0.0) / 100.0;
      return {
        'fatura_no': kayit['fatura_no'],
        'cari': kayit['unvan'],
        'tarih': kayit['tarih'],
        'tutar': borc > 0 ? borc : alacak,
        'aciklama': kayit['aciklama'],
      };
    }
    return null;
  }

  // DatabaseService içine bu yardımcı fonksiyonu ekleyin:
  Future<String> _yeniFisNoGetir(Transaction txn) async {
    final year = DateTime.now().year;
    final result = await txn.rawQuery(
      "SELECT fis_no FROM yevmiye_kayitlari WHERE fis_no LIKE 'YEV-$year-%' ORDER BY fis_no DESC LIMIT 1",
    );
    int cnt = 0;
    if (result.isNotEmpty) {
      final parts = result.first['fis_no'].toString().split('-');
      if (parts.length == 3) cnt = int.tryParse(parts[2]) ?? 0;
    }
    return 'YEV-$year-${(cnt + 1).toString().padLeft(4, '0')}';
  }

  Future<int?> islemKaydet({
    required String unvan,
    required String islemTuru,
    required double tutar,
    required bool borcMu,
    String aciklama = '',
    String odemeYontemi = 'AÇIK_HESAP',
    String vadeTarihi = '',
    String faturaNo = '',
    List<Map<String, dynamic>> yevmiyeMaddeleri = const [],
    String vkn = '',
    String? belgeYolu,
    int firmaId = 1,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final simdi = DateTime.now()
        .toIso8601String()
        .replaceAll('T', ' ')
        .substring(0, 19);
    final islemKucuk = '$islemTuru $aciklama $unvan'.toLowerCase();
    final isCariDisi = [
      'virman',
      'transfer',
      'maaş',
      'maas',
      'personel',
      'avans',
      'usta',
      'işçi',
      'isci',
      'çalışan',
      'yakıt',
      'yakit',
      'benzin',
      'mazot',
      'akaryakıt',
      'yemek',
      'lokanta',
      'restoran',
      'market',
      'noter',
      'kargo',
      'kırtasiye',
      'kirtasiye',
      'kira',
      'aidat',
      'elektrik',
      'su',
      'doğalgaz',
      'dogalgaz',
      'internet',
      'gider',
      'masraf',
      'fiş',
      'fis',
    ].any((k) => islemKucuk.contains(k));

    return await db.transaction((txn) async {
      int? hareketId;
      final int tutarKurus = (tutar * 100).round();

      if (!isCariDisi) {
        final tamEslesen = await txn.query(
          'cariler',
          where: 'unvan = ?',
          whereArgs: [unvan],
        );
        Map<String, dynamic>? cari;
        if (tamEslesen.isNotEmpty) {
          cari = tamEslesen.first;
        } else {
          if (vkn.isNotEmpty && vkn != 'Belirtilmedi') {
            final vknMatch = await txn.query(
              'cariler',
              where: 'vergi_no = ?',
              whereArgs: [vkn.trim()],
            );
            if (vknMatch.isNotEmpty) {
              cari = vknMatch.first;
            }
          }
        }

        int cariId;
        final int baslangicBakiye = borcMu ? tutarKurus : -tutarKurus;
        if (cari == null) {
          cariId = await txn.insert('cariler', {
            'unvan': unvan,
            'grup_adi': grupAdiCikar(unvan),
            'vergi_no': vkn.isNotEmpty ? vkn : 'Belirtilmedi',
            'sehir': 'Genel',
            'bakiye': baslangicBakiye,
            'olusturma_tarihi': simdi,
          });
        } else {
          cariId = cari['id'] as int;
          final int mevcutBakiye = (cari['bakiye'] as int?) ?? 0;
          await txn.update(
            'cariler',
            {'bakiye': mevcutBakiye + baslangicBakiye},
            where: 'id = ?',
            whereArgs: [cariId],
          );
        }

        hareketId = await txn.insert('cari_hareketler', {
          'cari_id': cariId,
          'fatura_no': faturaNo,
          'tarih': simdi,
          'vade_tarihi': vadeTarihi.isNotEmpty
              ? vadeTarihi
              : simdi.substring(0, 10),
          'odeme_yontemi': odemeYontemi,
          'islem_turu': islemTuru,
          'borc': borcMu ? tutarKurus : 0,
          'alacak': borcMu ? 0 : tutarKurus,
          'aciklama': aciklama,
          'belge_yolu': belgeYolu,
        });
      }

      if (yevmiyeMaddeleri.isNotEmpty) {
        final fisNo = await _yeniFisNoGetir(txn);
        for (var m in yevmiyeMaddeleri) {
          final kod = m['kod']?.toString() ?? '100';
          String ad =
              m['ad']?.toString() ??
              m['hesap_adi']?.toString() ??
              'Muhtelif Hesap';
          final double yBorc = (m['borc'] as num?)?.toDouble() ?? 0.0;
          final double yAlacak = (m['alacak'] as num?)?.toDouble() ?? 0.0;
          await txn.insert('yevmiye_kayitlari', {
            'hareket_id': hareketId,
            'fis_no': fisNo,
            'tarih': simdi.substring(0, 10),
            'hesap_kodu': kod,
            'hesap_adi': ad,
            'borc': (yBorc * 100).round(),
            'alacak': (yAlacak * 100).round(),
            'aciklama': '$faturaNo - $unvan',
          });
        }
      }
      return hareketId;
    });
  }

  // 🚨 STOK İŞLEMLERİ 🚨
  Future<List<Map<String, dynamic>>> getDepolar({required int firmaId}) async {
    final db = await getDatabase(firmaId: firmaId);
    await db.rawDelete(
      '''DELETE FROM depolar WHERE id NOT IN (SELECT MIN(id) FROM depolar GROUP BY depo_adi)''',
    );
    return await db.query('depolar', orderBy: 'varsayilan DESC, depo_adi ASC');
  }

  Future<int> depoEkle({
    required int firmaId,
    required String depoAdi,
    String? konum,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    return await db.insert('depolar', {
      'depo_adi': depoAdi,
      'konum': konum ?? '',
      'varsayilan': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getStokListesi({
    required int firmaId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final rows = await db.rawQuery('''
      SELECT s.*, COALESCE(SUM(CASE WHEN h.hareket_tipi = 'GIRIS' THEN h.miktar ELSE 0 END), 0) as toplam_giris, COALESCE(SUM(CASE WHEN h.hareket_tipi = 'CIKIS' THEN h.miktar ELSE 0 END), 0) as toplam_cikis, (COALESCE(SUM(CASE WHEN h.hareket_tipi = 'GIRIS' THEN h.miktar ELSE 0 END), 0) - COALESCE(SUM(CASE WHEN h.hareket_tipi = 'CIKIS' THEN h.miktar ELSE 0 END), 0)) as mevcut_miktar
      FROM stok_kartlari s LEFT JOIN stok_hareketleri h ON s.id = h.stok_id GROUP BY s.id ORDER BY s.stok_adi ASC
    ''');
    return rows
        .map(
          (r) => {
            ...r,
            'alis_fiyati':
                ((r['alis_fiyati'] as num?)?.toDouble() ?? 0.0) / 100.0,
            'satis_fiyati':
                ((r['satis_fiyati'] as num?)?.toDouble() ?? 0.0) / 100.0,
          },
        )
        .toList();
  }

  Future<int> stokKartiEkle({
    required int firmaId,
    required String stokKodu,
    required String stokAdi,
    required String birim,
    required double kdvOrani,
    required double alisFiyati,
    required double satisFiyati,
    required double kritikSeviye,
    String hesapKodu = '153',
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    return await db.insert('stok_kartlari', {
      'stok_kodu': stokKodu,
      'stok_adi': stokAdi,
      'birim': birim,
      'kdv_orani': kdvOrani,
      'hesap_kodu': hesapKodu,
      'alis_fiyati': (alisFiyati * 100).round(),
      'satis_fiyati': (satisFiyati * 100).round(),
      'kritik_seviye': kritikSeviye,
    });
  }

  Future<int> stokKartiGuncelle({
    required int firmaId,
    required int stokId,
    double? alisFiyati,
    double? satisFiyati,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    Map<String, dynamic> data = {};
    if (alisFiyati != null) {
      data['alis_fiyati'] = (alisFiyati * 100).round();
    }
    if (satisFiyati != null) {
      data['satis_fiyati'] = (satisFiyati * 100).round();
    }
    if (data.isNotEmpty) {
      return await db.update(
        'stok_kartlari',
        data,
        where: 'id = ?',
        whereArgs: [stokId],
      );
    }
    return 0;
  }

  Future<int> stokHareketiEkle({
    required int firmaId,
    required int stokId,
    required int depoId,
    required String hareketTipi,
    required double miktar,
    required double birimFiyat,
    required String tarih,
    String? belgeNo,
    String? aciklama,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final double toplamTutar = miktar * birimFiyat;
    return await db.insert('stok_hareketleri', {
      'stok_id': stokId,
      'depo_id': depoId,
      'hareket_tipi': hareketTipi,
      'miktar': miktar,
      'birim_fiyat': (birimFiyat * 100).round(),
      'toplam_tutar': (toplamTutar * 100).round(),
      'tarih': tarih,
      'belge_no': belgeNo ?? '',
      'aciklama': aciklama ?? '',
    });
  }

  // 🚨 KURUŞ HATASI GİDERİLDİ (* 100 Eklendi)
  Future<void> cokluFaturaIsle({
    required int firmaId,
    required String fisNo,
    required String tarih,
    required String faturaTipi,
    required int cariId,
    required String cariUnvan,
    required List<Map<String, dynamic>> kalemler,
    String? aciklama,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    double toplamMatrah = 0;
    double toplamKdv = 0;
    double toplamStmmMaliyeti = 0;

    await db.transaction((txn) async {
      for (final kalem in kalemler) {
        final int stokId = kalem['stokId'];
        final double miktar = (kalem['miktar'] as num).toDouble();
        final double birimFiyat = (kalem['birimFiyat'] as num).toDouble();
        final double kdvOrani = (kalem['kdvOrani'] as num).toDouble();

        final stokList = await txn.query(
          'stok_kartlari',
          where: 'id = ?',
          whereArgs: [stokId],
        );
        if (stokList.isEmpty) {
          continue;
        }
        final stok = stokList.first;
        final String stokAdi = stok['stok_adi']?.toString() ?? 'Malzeme';
        final String stokHesapKodu = stok['hesap_kodu']?.toString() ?? '153';
        final double alisMaliyeti =
            ((stok['alis_fiyati'] as num?)?.toDouble() ?? 0) / 100.0;

        final double satirMatrah = miktar * birimFiyat;
        final double satirKdv = satirMatrah * (kdvOrani / 100);
        toplamMatrah += satirMatrah;
        toplamKdv += satirKdv;

        final hareketTipi = faturaTipi == 'ALIS' ? 'GIRIS' : 'CIKIS';
        await txn.insert('stok_hareketleri', {
          'stok_id': stokId,
          'depo_id': 1,
          'hareket_tipi': hareketTipi,
          'miktar': miktar,
          'birim_fiyat': (birimFiyat * 100).round(),
          'toplam_tutar': (satirMatrah * 100).round(),
          'tarih': tarih,
          'belge_no': fisNo,
          'aciklama':
              aciklama ??
              '$faturaTipi Faturası: $fisNo - $cariUnvan ($stokAdi)',
        });

        if (faturaTipi == 'ALIS') {
          await txn.insert('yevmiye_kayitlari', {
            'fis_no': fisNo,
            'tarih': tarih,
            'hesap_kodu': stokHesapKodu,
            'hesap_adi': stokAdi,
            'borc': (satirMatrah * 100).round(),
            'alacak': 0,
            'aciklama': '$stokAdi Alımı ($miktar Adet)',
          });
        } else {
          toplamStmmMaliyeti += (miktar * alisMaliyeti);
        }
      }

      final double genelToplam = toplamMatrah + toplamKdv;

      if (faturaTipi == 'ALIS') {
        if (toplamKdv > 0) {
          await txn.insert('yevmiye_kayitlari', {
            'fis_no': fisNo,
            'tarih': tarih,
            'hesap_kodu': '191',
            'hesap_adi': 'İndirilecek KDV',
            'borc': (toplamKdv * 100).round(),
            'alacak': 0,
            'aciklama': '$fisNo KDV Tutarı',
          });
        }
        await txn.insert('yevmiye_kayitlari', {
          'fis_no': fisNo,
          'tarih': tarih,
          'hesap_kodu': '320',
          'hesap_adi': 'Satıcılar ($cariUnvan)',
          'borc': 0,
          'alacak': (genelToplam * 100).round(),
          'aciklama': '$fisNo Alış Faturası',
        });
      } else {
        await txn.insert('yevmiye_kayitlari', {
          'fis_no': fisNo,
          'tarih': tarih,
          'hesap_kodu': '120',
          'hesap_adi': 'Alıcılar ($cariUnvan)',
          'borc': (genelToplam * 100).round(),
          'alacak': 0,
          'aciklama': '$fisNo Satış Faturası',
        });
        await txn.insert('yevmiye_kayitlari', {
          'fis_no': fisNo,
          'tarih': tarih,
          'hesap_kodu': '600',
          'hesap_adi': 'Yurtiçi Satışlar',
          'borc': 0,
          'alacak': (toplamMatrah * 100).round(),
          'aciklama': '$fisNo Toplam Satış Hasılatı',
        });
        if (toplamKdv > 0) {
          await txn.insert('yevmiye_kayitlari', {
            'fis_no': fisNo,
            'tarih': tarih,
            'hesap_kodu': '391',
            'hesap_adi': 'Hesaplanan KDV',
            'borc': 0,
            'alacak': (toplamKdv * 100).round(),
            'aciklama': '$fisNo Satış KDV Tutarı',
          });
        }
        if (toplamStmmMaliyeti > 0) {
          final maliyetFisNo = '$fisNo-STMM';
          await txn.insert('yevmiye_kayitlari', {
            'fis_no': maliyetFisNo,
            'tarih': tarih,
            'hesap_kodu': '621',
            'hesap_adi': 'Satılan Ticari Mallar Maliyeti',
            'borc': (toplamStmmMaliyeti * 100).round(),
            'alacak': 0,
            'aciklama': '$fisNo Fatura Satış Maliyeti',
          });
          await txn.insert('yevmiye_kayitlari', {
            'fis_no': maliyetFisNo,
            'tarih': tarih,
            'hesap_kodu': '153',
            'hesap_adi': 'Ticari Mallar',
            'borc': 0,
            'alacak': (toplamStmmMaliyeti * 100).round(),
            'aciklama': '$fisNo Envanter Çıkışı',
          });
        }
      }

      final tipMetni = faturaTipi == 'ALIS'
          ? 'Alış Faturası'
          : 'Satış Faturası';
      final int bakiyeFarki = faturaTipi == 'SATIS'
          ? (genelToplam * 100).round()
          : -(genelToplam * 100).round();

      await txn.insert('cari_hareketler', {
        'cari_id': cariId,
        'fatura_no': fisNo,
        'tarih': tarih,
        'vade_tarihi': tarih,
        'odeme_yontemi': 'AÇIK_HESAP',
        'islem_turu': tipMetni,
        'borc': faturaTipi == 'SATIS' ? (genelToplam * 100).round() : 0,
        'alacak': faturaTipi == 'ALIS' ? (genelToplam * 100).round() : 0,
        'aciklama': '$tipMetni ($fisNo) - ${kalemler.length} Kalem',
      });
      await txn.rawUpdate(
        'UPDATE cariler SET bakiye = bakiye + ? WHERE id = ?',
        [bakiyeFarki, cariId],
      );
    });
  }

  // --- İPTAL EDİLMİŞ METOTLARIN GÜNCEL KURUŞLU HALLERİ ---
  Future<void> cekSenetKirdir({
    required int firmaId,
    required int cekId,
    required double komisyonTutari,
    required String odemeYeri,
    String? kurumAdi,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final simdi = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final evraklar = await txn.query(
        'cek_senet_bordro',
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.isEmpty) {
        return;
      }
      final evrak = evraklar.first;
      final brutTutarKurus = (evrak['tutar'] as int?) ?? 0;
      final komisyonKurus = (komisyonTutari * 100).round();
      final netTutarKurus = brutTutarKurus - komisyonKurus;
      await txn.update(
        'cek_senet_bordro',
        {'durum': 'KIRDIRILDI'},
        where: 'id = ?',
        whereArgs: [cekId],
      );
      final fisNo = await _yeniFisNoGetir(txn);

      final yevmiye = [
        {
          'kod': odemeYeri == 'KASA' ? '100' : '102',
          'ad': 'Giriş',
          'borc': netTutarKurus,
          'alacak': 0,
        },
        if (komisyonKurus > 0)
          {'kod': '780', 'ad': 'Kesinti', 'borc': komisyonKurus, 'alacak': 0},
        {
          'kod': (evrak['evrak_turu']?.toString() ?? '').contains('SENET')
              ? '121'
              : '101',
          'ad': 'Portföy',
          'borc': 0,
          'alacak': brutTutarKurus,
        },
      ];
      for (var m in yevmiye) {
        await txn.insert('yevmiye_kayitlari', {
          'hareket_id': cekId,
          'fis_no': fisNo,
          'tarih': simdi.substring(0, 10),
          'hesap_kodu': m['kod'],
          'hesap_adi': m['ad'],
          'borc': m['borc'],
          'alacak': m['alacak'],
          'aciklama': 'Kırdırma İşlemi',
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> ciroIcinCarileriGetir({
    required int firmaId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    return await db.query(
      'cariler',
      columns: ['id', 'unvan', 'bakiye'],
      orderBy: 'unvan ASC',
    );
  }

  Future<void> cekSenetCiroEt({
    required int firmaId,
    required int cekId,
    required int hedefCariId,
    required String hedefCariUnvan,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final simdi = DateTime.now().toIso8601String();
    final bugun = simdi.substring(0, 10);
    await db.transaction((txn) async {
      final evraklar = await txn.query(
        'cek_senet_bordro',
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.isEmpty) {
        return;
      }
      final brutTutar = (evraklar.first['tutar'] as int?) ?? 0;
      await txn.update(
        'cek_senet_bordro',
        {'durum': 'CIRO_EDILDI'},
        where: 'id = ?',
        whereArgs: [cekId],
      );
      final fisNo = await _yeniFisNoGetir(txn);

      final yevmiye = [
        {'kod': '320', 'borc': brutTutar, 'alacak': 0},
        {
          'kod':
              (evraklar.first['evrak_turu']?.toString() ?? '').contains('SENET')
              ? '121'
              : '101',
          'borc': 0,
          'alacak': brutTutar,
        },
      ];
      for (var m in yevmiye) {
        await txn.insert('yevmiye_kayitlari', {
          'hareket_id': cekId,
          'fis_no': fisNo,
          'tarih': bugun,
          'hesap_kodu': m['kod'],
          'hesap_adi': 'Ciro',
          'borc': m['borc'],
          'alacak': m['alacak'],
          'aciklama': 'Evrak Ciro Edildi',
        });
      }
      await txn.insert('cari_hareketler', {
        'cari_id': hedefCariId,
        'tarih': bugun,
        'fatura_no': evraklar.first['evrak_no'],
        'islem_turu': 'EVRAK_CIROSU',
        'odeme_yontemi': 'CEK',
        'borc': brutTutar,
        'alacak': 0,
        'aciklama': 'Ciro',
      });
      await txn.rawUpdate(
        'UPDATE cariler SET bakiye = bakiye + ? WHERE id = ?',
        [brutTutar, hedefCariId],
      );
    });
  }

  Future<void> cekSenetKarsiliksizYap({
    required int firmaId,
    required int cekId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    await db.transaction((txn) async {
      final evraklar = await txn.query(
        'cek_senet_bordro',
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.isEmpty) {
        return;
      }
      final brutTutar = (evraklar.first['tutar'] as int?) ?? 0;
      await txn.update(
        'cek_senet_bordro',
        {'durum': 'KARSILIKSIZ'},
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.first['cari_id'] != null) {
        await txn.insert('cari_hareketler', {
          'cari_id': evraklar.first['cari_id'],
          'tarih': bugun,
          'islem_turu': 'KARSILIKSIZ',
          'borc': brutTutar,
          'alacak': 0,
          'aciklama': 'Karşılıksız',
        });
        await txn.rawUpdate(
          'UPDATE cariler SET bakiye = bakiye + ? WHERE id = ?',
          [brutTutar, evraklar.first['cari_id']],
        );
      }
    });
  }

  Future<void> kendiCekSenetOdenemedi({
    required int firmaId,
    required int cekId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final bugun = DateTime.now().toIso8601String().substring(0, 10);
    await db.transaction((txn) async {
      final evraklar = await txn.query(
        'cek_senet_bordro',
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.isEmpty) {
        return;
      }
      final brutTutar = (evraklar.first['tutar'] as int?) ?? 0;
      await txn.update(
        'cek_senet_bordro',
        {'durum': 'KARSILIKSIZ_YAZILDI'},
        where: 'id = ?',
        whereArgs: [cekId],
      );
      if (evraklar.first['cari_id'] != null) {
        await txn.insert('cari_hareketler', {
          'cari_id': evraklar.first['cari_id'],
          'tarih': bugun,
          'islem_turu': 'KARSILIKSIZ_YAZILDI',
          'borc': 0,
          'alacak': brutTutar,
          'aciklama': 'Ödenemedi',
        });
        await txn.rawUpdate(
          'UPDATE cariler SET bakiye = bakiye - ? WHERE id = ?',
          [brutTutar, evraklar.first['cari_id']],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getOdemeTakvimi({
    required int firmaId,
  }) async {
    try {
      final db = await getDatabase(firmaId: firmaId);
      final rowsCari = await db.rawQuery(
        '''SELECT h.id, h.id AS cari_hareket_id, NULL AS cek_id, h.tarih, CASE WHEN h.vade_tarihi IS NOT NULL AND TRIM(h.vade_tarihi) != '' THEN h.vade_tarihi ELSE h.tarih END AS vade_tarihi, h.fatura_no, h.odeme_yontemi, h.islem_turu, COALESCE(h.borc, 0) AS borc, COALESCE(h.alacak, 0) AS alacak, h.aciklama, h.belge_yolu, COALESCE(c.unvan, 'Genel İşlem') AS cari_unvan, 0 AS is_cek FROM cari_hareketler h LEFT JOIN cariler c ON c.id = h.cari_id WHERE h.odeme_yontemi NOT IN ('CEK', 'SENET')''',
      );
      final rowsCekSenet = await db.rawQuery(
        '''SELECT id, id AS cek_id, NULL AS cari_hareket_id, vade_tarihi AS tarih, vade_tarihi, evrak_no AS fatura_no, evrak_turu AS odeme_yontemi, 'ÇEK/SENET' AS islem_turu, CASE WHEN evrak_turu LIKE '%MUSTERI%' THEN COALESCE(tutar, 0) ELSE 0 END AS borc, CASE WHEN evrak_turu LIKE '%BORC%' THEN COALESCE(tutar, 0) ELSE 0 END AS alacak, (kesideci || ' - ' || banka_adi) AS aciklama, belge_yolu, kesideci AS cari_unvan, banka_adi, durum, 1 AS is_cek FROM cek_senet_bordro WHERE durum = 'PORTFOYDE' OR durum IS NULL''',
      );

      final birlesmisListe = <Map<String, dynamic>>[
        ...rowsCari,
        ...rowsCekSenet,
      ];
      birlesmisListe.sort(
        (a, b) => (a['vade_tarihi']?.toString() ?? '').compareTo(
          b['vade_tarihi']?.toString() ?? '',
        ),
      );

      return birlesmisListe.map((r) {
        final rawVade = r['vade_tarihi']?.toString() ?? '';
        return {
          ...r,
          'vade_tarihi': rawVade.length >= 10
              ? rawVade.substring(0, 10)
              : rawVade,
          'borc': ((r['borc'] as num?)?.toDouble() ?? 0.0) / 100.0,
          'alacak': ((r['alacak'] as num?)?.toDouble() ?? 0.0) / 100.0,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getYevmiyeDefteri({
    int firmaId = 1,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final rows = await db.rawQuery(
      '''SELECT id, hareket_id, fis_no, tarih, hesap_kodu, hesap_adi, borc, alacak, aciklama FROM yevmiye_kayitlari ORDER BY id ASC''',
    );
    final Map<String, Map<String, dynamic>> fisler = {};
    for (var r in rows) {
      final fNo = r['fis_no'] as String? ?? 'YEV-001';
      if (!fisler.containsKey(fNo)) {
        fisler[fNo] = {
          'fis_no': fNo,
          'tarih': r['tarih'],
          'aciklama': r['aciklama'],
          'toplam_borc': 0.0,
          'toplam_alacak': 0.0,
          'satirlar': <Map<String, dynamic>>[],
        };
      }
      final borc = ((r['borc'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final alacak = ((r['alacak'] as num?)?.toDouble() ?? 0.0) / 100.0;
      fisler[fNo]!['toplam_borc'] =
          (fisler[fNo]!['toplam_borc'] as double) + borc;
      fisler[fNo]!['toplam_alacak'] =
          (fisler[fNo]!['toplam_alacak'] as double) + alacak;
      (fisler[fNo]!['satirlar'] as List<Map<String, dynamic>>).add({
        'hesap_kodu': r['hesap_kodu'],
        'hesap_adi': r['hesap_adi'],
        'borc': borc,
        'alacak': alacak,
      });
    }
    return fisler.values.toList();
  }

  Future<Map<String, dynamic>> getKasaBankaDurumu({int firmaId = 1}) async {
    final db = await getDatabase(firmaId: firmaId);
    final yevRows = await db.rawQuery(
      '''SELECT hesap_kodu, SUM(borc) as toplam_borc, SUM(alacak) as toplam_alacak FROM yevmiye_kayitlari WHERE hesap_kodu LIKE '100%' OR hesap_kodu LIKE '102%' GROUP BY SUBSTR(hesap_kodu, 1, 3)''',
    );
    final cariOzet = await db.rawQuery(
      '''SELECT SUM(CASE WHEN bakiye > 0 THEN bakiye ELSE 0 END) as toplam_alacak, SUM(CASE WHEN bakiye < 0 THEN ABS(bakiye) ELSE 0 END) as toplam_borc FROM cariler''',
    );

    double kasaNet = 0.0;
    double bankaNet = 0.0;
    for (var yr in yevRows) {
      final kod = yr['hesap_kodu']?.toString() ?? '';
      final b = ((yr['toplam_borc'] as num?)?.toDouble() ?? 0.0);
      final a = ((yr['toplam_alacak'] as num?)?.toDouble() ?? 0.0);
      if (kod.startsWith('100')) {
        kasaNet += (b - a);
      }
      if (kod.startsWith('102')) {
        bankaNet += (b - a);
      }
    }
    final row = cariOzet.isNotEmpty ? cariOzet.first : null;
    return {
      'kasa_100': kasaNet,
      'banka_102': bankaNet,
      'acik_alacaklar': ((row?['toplam_alacak'] as num?)?.toDouble() ?? 0.0),
      'acik_borclar': ((row?['toplam_borc'] as num?)?.toDouble() ?? 0.0),
      'net_likidite': kasaNet + bankaNet,
    };
  }

  Future<List<Map<String, dynamic>>> getMizanListesi({
    required int firmaId,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final result = await db.rawQuery(
      '''SELECT hesap_kodu, hesap_adi, SUM(borc) as toplam_borc, SUM(alacak) as toplam_alacak, (SUM(borc) - SUM(alacak)) as net_fark FROM yevmiye_kayitlari GROUP BY hesap_kodu ORDER BY hesap_kodu ASC''',
    );
    return result.map((row) {
      final borc = ((row['toplam_borc'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final alacak =
          ((row['toplam_alacak'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final fark = borc - alacak;
      return {
        'hesap_kodu': row['hesap_kodu']?.toString() ?? '',
        'hesap_adi': row['hesap_adi']?.toString() ?? 'Muhtelif Hesap',
        'toplam_borc': borc,
        'toplam_alacak': alacak,
        'borc_bakiye': fark > 0 ? fark : 0.0,
        'alacak_bakiye': fark < 0 ? fark.abs() : 0.0,
      };
    }).toList();
  }

  Future<Map<String, double>> getKasaBankaOzet({required int firmaId}) async {
    final db = await getDatabase(firmaId: firmaId);
    final result = await db.rawQuery(
      '''SELECT hesap_kodu, (SUM(borc) - SUM(alacak)) as bakiye FROM yevmiye_kayitlari WHERE hesap_kodu IN ('100', '102') GROUP BY hesap_kodu''',
    );
    double kasaBakiye = 0.0;
    double bankaBakiye = 0.0;
    for (var row in result) {
      final bakiyeTL = ((row['bakiye'] as num?)?.toDouble() ?? 0.0) / 100.0;
      if (row['hesap_kodu'] == '100') {
        kasaBakiye = bakiyeTL;
      }
      if (row['hesap_kodu'] == '102') {
        bankaBakiye = bakiyeTL;
      }
    }
    return {
      'kasa': kasaBakiye,
      'banka': bankaBakiye,
      'toplam': kasaBakiye + bankaBakiye,
    };
  }

  Future<List<Map<String, dynamic>>> getKasaBankaHareketleri({
    required int firmaId,
    required String hesapKodu,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final rows = await db.rawQuery(
      '''SELECT id, tarih, fis_no, aciklama, borc, alacak, hesap_kodu, hesap_adi FROM yevmiye_kayitlari WHERE hesap_kodu = ? ORDER BY tarih DESC, id DESC''',
      [hesapKodu],
    );
    return rows
        .map(
          (r) => {
            ...r,
            'borc': ((r['borc'] as num?)?.toDouble() ?? 0.0) / 100.0,
            'alacak': ((r['alacak'] as num?)?.toDouble() ?? 0.0) / 100.0,
          },
        )
        .toList();
  }

  Future<void> kasaBankaVirmanYap({
    required int firmaId,
    required double tutar,
    required String kaynak,
    required String aciklama,
    String? bankaAdi,
  }) async {
    final db = await getDatabase(firmaId: firmaId);
    final tarih = DateTime.now().toIso8601String().substring(0, 10);
    final int tutarKurus = (tutar * 100).round();
    await db.transaction((txn) async {
      final fisNo = await _yeniFisNoGetir(txn);
      await txn.insert('yevmiye_kayitlari', {
        'fis_no': fisNo,
        'tarih': tarih,
        'hesap_kodu': kaynak == 'KASA' ? '102' : '100',
        'hesap_adi': 'Transfer',
        'borc': tutarKurus,
        'alacak': 0,
        'aciklama': aciklama,
      });
      await txn.insert('yevmiye_kayitlari', {
        'fis_no': fisNo,
        'tarih': tarih,
        'hesap_kodu': kaynak == 'KASA' ? '100' : '102',
        'hesap_adi': 'Transfer',
        'borc': 0,
        'alacak': tutarKurus,
        'aciklama': aciklama,
      });
    });
  }

  Future<Map<String, dynamic>> getMaliTablolar({required int firmaId}) async {
    final db = await getDatabase(firmaId: firmaId);
    final result = await db.rawQuery(
      '''SELECT hesap_kodu, hesap_adi, SUM(borc) as toplam_borc, SUM(alacak) as toplam_alacak FROM yevmiye_kayitlari GROUP BY hesap_kodu ORDER BY hesap_kodu ASC''',
    );

    double toplamDonenVarliklar = 0.0;
    double toplamDuranVarliklar = 0.0;
    double toplamKisaVadeliBorclar = 0.0;
    double toplamUzunVadeliBorclar = 0.0;
    double toplamOzkaynaklar = 0.0;
    double toplamGelirler = 0.0;
    double toplamGiderler = 0.0;
    final List<Map<String, dynamic>> aktifHesaplar = [];
    final List<Map<String, dynamic>> pasifHesaplar = [];
    final List<Map<String, dynamic>> gelirHesaplari = [];
    final List<Map<String, dynamic>> giderHesaplari = [];

    for (var row in result) {
      final kod = row['hesap_kodu']?.toString() ?? '';
      final ad = row['hesap_adi']?.toString() ?? 'Muhtelif Hesap';
      final borc = ((row['toplam_borc'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final alacak =
          ((row['toplam_alacak'] as num?)?.toDouble() ?? 0.0) / 100.0;
      final netFark = borc - alacak;

      if (kod.startsWith('1') || kod.startsWith('2')) {
        final bakiye = (kod == '103') ? (alacak - borc) * -1 : netFark;
        if (bakiye.abs() > 0.01) {
          aktifHesaplar.add({'kod': kod, 'ad': ad, 'tutar': bakiye});
          if (kod.startsWith('1')) {
            toplamDonenVarliklar += bakiye;
          }
          if (kod.startsWith('2')) {
            toplamDuranVarliklar += bakiye;
          }
        }
      } else if (kod.startsWith('3') ||
          kod.startsWith('4') ||
          kod.startsWith('5')) {
        final bakiye = alacak - borc;
        if (bakiye.abs() > 0.01) {
          pasifHesaplar.add({'kod': kod, 'ad': ad, 'tutar': bakiye});
          if (kod.startsWith('3')) {
            toplamKisaVadeliBorclar += bakiye;
          }
          if (kod.startsWith('4')) {
            toplamUzunVadeliBorclar += bakiye;
          }
          if (kod.startsWith('5')) {
            toplamOzkaynaklar += bakiye;
          }
        }
      } else if (kod.startsWith('6')) {
        final gelirTutar = alacak - borc;
        if (gelirTutar.abs() > 0.01) {
          gelirHesaplari.add({'kod': kod, 'ad': ad, 'tutar': gelirTutar});
          toplamGelirler += gelirTutar;
        }
      } else if (kod.startsWith('7')) {
        final giderTutar = borc - alacak;
        if (giderTutar.abs() > 0.01) {
          giderHesaplari.add({'kod': kod, 'ad': ad, 'tutar': giderTutar});
          toplamGiderler += giderTutar;
        }
      }
    }
    final netKarZarar = toplamGelirler - toplamGiderler;
    if (netKarZarar.abs() > 0.01) {
      pasifHesaplar.add({
        'kod': netKarZarar > 0 ? '590' : '591',
        'ad': netKarZarar > 0 ? 'Dönem Net Kârı' : 'Dönem Net Zararı (-)',
        'tutar': netKarZarar,
      });
      toplamOzkaynaklar += netKarZarar;
    }
    return {
      'donen_varliklar': toplamDonenVarliklar,
      'duran_varliklar': toplamDuranVarliklar,
      'toplam_aktif': toplamDonenVarliklar + toplamDuranVarliklar,
      'kisa_borclar': toplamKisaVadeliBorclar,
      'uzun_borclar': toplamUzunVadeliBorclar,
      'ozkaynaklar': toplamOzkaynaklar,
      'toplam_pasif':
          toplamKisaVadeliBorclar + toplamUzunVadeliBorclar + toplamOzkaynaklar,
      'gelirler': toplamGelirler,
      'giderler': toplamGiderler,
      'net_kar_zarar': netKarZarar,
      'aktif_hesaplar': aktifHesaplar,
      'pasif_hesaplar': pasifHesaplar,
      'gelir_hesaplari': gelirHesaplari,
      'gider_hesaplari': giderHesaplari,
    };
  }

  Future<bool> islemSil(int hareketId, {int firmaId = 1}) async {
    final db = await getDatabase(firmaId: firmaId);
    final list = await db.query(
      'cari_hareketler',
      where: 'id = ?',
      whereArgs: [hareketId],
    );
    if (list.isEmpty) {
      return false;
    }
    final hareket = list.first;
    final cariId = hareket['cari_id'] as int;
    final borc = (hareket['borc'] as num?)?.toDouble() ?? 0.0;
    final alacak = (hareket['alacak'] as num?)?.toDouble() ?? 0.0;
    final netFark = borc - alacak;

    final cariList = await db.query(
      'cariler',
      where: 'id = ?',
      whereArgs: [cariId],
    );
    if (cariList.isNotEmpty) {
      final mevcutBakiye =
          (cariList.first['bakiye'] as num?)?.toDouble() ?? 0.0;
      await db.update(
        'cariler',
        {'bakiye': mevcutBakiye - netFark},
        where: 'id = ?',
        whereArgs: [cariId],
      );
    }
    await db.delete(
      'yevmiye_kayitlari',
      where: 'hareket_id = ?',
      whereArgs: [hareketId],
    );
    await db.delete('cari_hareketler', where: 'id = ?', whereArgs: [hareketId]);
    return true;
  }
}
