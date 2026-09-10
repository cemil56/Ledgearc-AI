import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'ai_islem_plani.dart';
import 'database_service.dart';

final aiKayitRevision = ValueNotifier<int>(0);

class AiKayitService {
  static const createLog = '''CREATE TABLE IF NOT EXISTS ai_kayitlar (
    request_id TEXT PRIMARY KEY, kategori TEXT NOT NULL, hareket_id INTEGER,
    sonuc TEXT NOT NULL, tarih TEXT NOT NULL)''';

  // Compare the physical document, independently of its received/issued
  // direction, counterparty, amount, date or settlement status.
  // Formatting differences are tolerated; issuer names are not fuzzy-matched.
  static String _kimlikMetni(Object? value) {
    var normalized = (value?.toString() ?? '').trim().toUpperCase();
    const letters = {'İ': 'I', 'Ş': 'S', 'Ğ': 'G', 'Ü': 'U', 'Ö': 'O', 'Ç': 'C'};
    for (final entry in letters.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized
        .replaceAll('\u0307', '')
        .replaceAll(RegExp(r"[\s\u00a0\u200b.,;:'’()/\\-]+"), '');
  }

  static String _evrakNumarasi(Object? value) =>
      (value?.toString() ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static Future<void> _mukerrerEvrakKontrolu(
    Transaction txn, Map<String, dynamic> d, String number,
  ) async {
    final type = AiIslemPlani.text(d, 'evrak_turu');
    final cheque = type == 'MUSTERI_CEKI' || type == 'BORC_CEKI';
    final family = cheque
        ? const ['MUSTERI_CEKI', 'BORC_CEKI']
        : const ['MUSTERI_SENEDI', 'BORC_SENEDI'];
    final issuer = _kimlikMetni(d['kesideci']);
    final bank = _kimlikMetni(d['banka_adi']);
    final serial = _evrakNumarasi(number);
    if (issuer.isEmpty || (cheque && bank.isEmpty)) {
      throw const FormatException('Keşideci ve banka bilgilerini kontrol edin.');
    }
    final candidates = await txn.query('cek_senet_bordro',
      columns: ['id', 'evrak_no', 'evrak_turu', 'banka_adi', 'kesideci'],
      where: 'evrak_turu IN (?, ?)', whereArgs: family);
    for (final existing in candidates) {
      if (_evrakNumarasi(existing['evrak_no']) != serial ||
          _kimlikMetni(existing['kesideci']) != issuer ||
          (cheque && _kimlikMetni(existing['banka_adi']) != bank)) continue;
      final direction = existing['evrak_turu'].toString().startsWith('MUSTERI')
          ? 'alınan' : 'verilen';
      throw FormatException(
        '$number numaralı ${cheque ? 'çek' : 'senet'} aynı keşideci'
        '${cheque ? ' ve banka' : ''} ile bu firmada zaten kayıtlı '
        '(kayıt #${existing['id']}, $direction). '
        'Yönünü değiştirerek tekrar kaydedemezsiniz. Mevcut evrak kaydını kontrol edin.',
      );
    }
  }

  static Future<Map<String, dynamic>> kaydet(Map<String, dynamic> data, int activeFirma) async {
    final snapshot = Map<String, dynamic>.from(data);
    if (snapshot['firma_id'] != activeFirma || activeFirma <= 0) {
      throw const FormatException('Taslağın oluşturulduğu firmaya geçin.');
    }
    AiIslemPlani.build(snapshot);
    final id = AiIslemPlani.requiredText(snapshot, 'request_id', 'İşlem kimliği');
    if (!RegExp(r'^[a-zA-Z0-9-]{16,80}$').hasMatch(id)) throw const FormatException('İşlem kimliği geçersiz.');
    final db = await DatabaseService.instance.getDatabase(firmaId: activeFirma);
    // Keep attachment copies independent of Downloads, clipboard and WhatsApp temp files.
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(docs.path, 'LedgerArc', 'belgeler', 'firma_$activeFirma', id));
    await folder.create(recursive: true);
    final files = (snapshot['attached_file_paths'] as List?)?.whereType<String>().toList() ?? [];
    final copied = <String>[];
    for (var index = 0; index < files.length; index++) {
      final dest = p.join(folder.path, '$index${p.extension(files[index])}');
      if (!await File(dest).exists()) await File(files[index]).copy(dest);
      copied.add(dest);
    }
    snapshot['belge_yolu'] = copied.isEmpty ? null : copied.first;
    snapshot['belgeler'] = copied;
    final result = await kaydetDb(db, snapshot, activeFirma);
    aiKayitRevision.value++;
    return result;
  }

  /// Single SQLite transaction; also callable against an in-memory database in tests.
  static Future<Map<String, dynamic>> kaydetDb(Database db, Map<String, dynamic> d, int activeFirma) async {
    if (d['firma_id'] != activeFirma || activeFirma <= 0) throw const FormatException('Firma uyuşmuyor.');
    final id = AiIslemPlani.requiredText(d, 'request_id', 'İşlem kimliği');
    final plan = AiIslemPlani.build(d);
    return db.transaction((txn) async {
      await txn.execute(createLog);
      final previous = await txn.query('ai_kayitlar', where: 'request_id = ?', whereArgs: [id]);
      if (previous.isNotEmpty) return Map<String, dynamic>.from(jsonDecode(previous.first['sonuc'] as String) as Map);
      final cat = plan['category'] as String;
      int? movement;
      final result = <String, dynamic>{'request_id': id, 'category': cat};
      if (cat == 'STOK_DEPO_ISLEMI') {
        result.addAll(await _stock(txn, d, plan));
      } else {
        final name = AiIslemPlani.text(d, 'cari_unvan');
        int? cariId;
        if (cat != 'VIRMAN') {
          if (d['cari_id'] is int) {
            final matches = await txn.query('cariler', where: 'id = ?', whereArgs: [d['cari_id']]);
            if (matches.length != 1 || matches.first['unvan'] != name) throw const FormatException('Seçilen cari değişti. Yeniden seçin.');
            cariId = matches.first['id'] as int;
          } else {
            final matches = await txn.query('cariler', where: 'unvan = ?', whereArgs: [name]);
            if (matches.isNotEmpty) throw const FormatException('Bu cari zaten var; listeden mevcut cariyi seçin.');
            // The issuer's VKN must never be assigned to the counterparty by inference.
            cariId = await txn.insert('cariler', {'unvan': name, 'grup_adi': DatabaseService.grupAdiCikar(name),
              'bakiye': 0, 'olusturma_tarihi': DateTime.now().toIso8601String()});
          }
        }
        final number = plan['number'] as String;
        if (cat == 'CEK_SENET') {
          await _mukerrerEvrakKontrolu(txn, d, number);
        } else if (number.isNotEmpty && const ['TICARI_CARI', 'ISLETME_GIDERI'].contains(cat)) {
          final exists = await txn.query('cari_hareketler', where: 'cari_id = ? AND fatura_no = ?', whereArgs: [cariId, number]);
          if (exists.isNotEmpty) throw const FormatException('Bu cari ve belge numarası için kayıt zaten var.');
        }
        final summary = AiIslemPlani.text(d, 'summary');
        movement = await txn.insert('cari_hareketler', {
          'cari_id': cariId, 'fatura_no': number, 'tarih': plan['date'], 'vade_tarihi': plan['due'],
          'odeme_yontemi': plan['payment'], 'islem_turu': 'AI_$cat',
          'borc': plan['debit'], 'alacak': plan['credit'], 'aciklama': summary,
          'belge_yolu': d['belge_yolu'], 'guvenli_baglanti': 0,
        });
        if (cariId != null) await txn.rawUpdate('UPDATE cariler SET bakiye = bakiye + ? WHERE id = ?',
          [(plan['debit'] as int) - (plan['credit'] as int), cariId]);
        if ((cat == 'TAHSILAT_ODEME' || cat == 'CEK_SENET') && d['kapatilacak_hareket_id'] is int) {
          final target = d['kapatilacak_hareket_id'] as int;
          final invoices = await txn.query('cari_hareketler', where: 'id = ? AND cari_id = ? AND odeme_yontemi = ?',
            whereArgs: [target, cariId, 'AÇIK_HESAP']);
          if (invoices.length != 1) throw const FormatException('Eşleştirilecek fatura bu caride bulunamadı.');
          final invoice = invoices.first;
          final net = (invoice['borc'] as num).toInt() - (invoice['alacak'] as num).toInt();
          final incoming = cat == 'CEK_SENET' ? AiIslemPlani.text(d, 'evrak_turu').startsWith('MUSTERI') : d['yon'] == 'TAHSILAT';
          if ((net > 0) != incoming) throw const FormatException('Fatura ve ödeme yönleri uyuşmuyor.');
          final allocations = await txn.rawQuery('SELECT COALESCE(SUM(tutar),0) AS tutar FROM ai_odeme_eslestirme WHERE fatura_id = ?', [target]);
          final remaining = net.abs() - (allocations.first['tutar'] as num).toInt();
          if ((plan['amount'] as int) > remaining) throw const FormatException('Ödeme, faturanın kalan tutarını aşıyor.');
          await txn.insert('ai_odeme_eslestirme', {'odeme_id': movement, 'fatura_id': target, 'tutar': plan['amount']});
        }
        if (cat == 'CEK_SENET') {
          result['cek_id'] = await txn.insert('cek_senet_bordro', {
            'cari_id': cariId, 'hareket_id': movement, 'evrak_turu': d['evrak_turu'], 'evrak_no': number,
            'banka_adi': AiIslemPlani.text(d, 'banka_adi'), 'kesideci': AiIslemPlani.text(d, 'kesideci'),
            'tutar': plan['amount'], 'vade_tarihi': plan['due'], 'belge_yolu': d['belge_yolu'],
            'durum': 'PORTFOYDE', 'olusturma_tarihi': DateTime.now().toIso8601String(),
          });
        }
        final receipt = 'AI-$id';
        for (final row in plan['rows'] as List<Map<String, dynamic>>) {
          await txn.insert('yevmiye_kayitlari', {'hareket_id': movement, 'fis_no': receipt,
            'tarih': plan['date'], 'hesap_kodu': row['code'], 'hesap_adi': row['name'],
            'borc': row['debit'], 'alacak': row['credit'], 'aciklama': '$number $summary'.trim(),
            'belge_yolu': d['belge_yolu']});
        }
        result.addAll({'hareket_id': movement, 'cari_id': cariId, 'fis_no': receipt});
      }
      await txn.insert('ai_kayitlar', {'request_id': id, 'kategori': cat, 'hareket_id': movement,
        'sonuc': jsonEncode(result), 'tarih': DateTime.now().toIso8601String()});
      // Keep the exact approved values and all attachment references for review.
      await txn.execute('CREATE TABLE IF NOT EXISTS ai_onaylar (request_id TEXT PRIMARY KEY, veri TEXT NOT NULL)');
      final approved = Map<String, dynamic>.from(d)..remove('is_saving');
      await txn.insert('ai_onaylar', {'request_id': id, 'veri': jsonEncode(approved)});
      return result;
    });
  }

  static Future<Map<String, dynamic>> _stock(Transaction txn, Map<String, dynamic> d, Map<String, dynamic> plan) async {
    final action = plan['action'];
    int stockId;
    if (action == 'YENI_STOK_KARTI') {
      final code = AiIslemPlani.text(d, 'stok_kodu');
      final existing = await txn.query('stok_kartlari', where: 'stok_kodu = ?', whereArgs: [code]);
      if (existing.isNotEmpty) throw const FormatException('Bu stok kodu zaten var.');
      stockId = await txn.insert('stok_kartlari', {'stok_kodu': code,
        'stok_adi': AiIslemPlani.text(d, 'stok_adi'), 'birim': AiIslemPlani.text(d, 'birim'),
        'alis_fiyati': plan['buy'], 'satis_fiyati': plan['sell']});
    } else {
      stockId = d['stok_id'] as int;
      final existing = await txn.query('stok_kartlari', where: 'id = ?', whereArgs: [stockId]);
      if (existing.length != 1) throw const FormatException('Stok kartı bulunamadı.');
      if (action == 'FIYAT_GUNCELLE') {
        await txn.update('stok_kartlari', {'alis_fiyati': plan['buy'], 'satis_fiyati': plan['sell']}, where: 'id = ?', whereArgs: [stockId]);
      } else {
        final depotId = d['depo_id'] as int;
        final depots = await txn.query('depolar', where: 'id = ?', whereArgs: [depotId]);
        if (depots.length != 1) throw const FormatException('Depo bulunamadı.');
        if (action == 'STOK_CIKIS') {
          final totals = await txn.rawQuery("SELECT COALESCE(SUM(CASE WHEN hareket_tipi = 'GIRIS' THEN miktar WHEN hareket_tipi = 'CIKIS' THEN -miktar ELSE 0 END), 0) AS miktar FROM stok_hareketleri WHERE stok_id = ? AND depo_id = ?", [stockId, depotId]);
          if ((totals.first['miktar'] as num).toDouble() + 0.0000001 < (plan['quantity'] as double)) {
            throw const FormatException('Seçilen depoda yeterli stok yok.');
          }
        }
        await txn.insert('stok_hareketleri', {'stok_id': stockId, 'depo_id': depotId,
          'hareket_tipi': action == 'STOK_GIRIS' ? 'GIRIS' : 'CIKIS', 'miktar': plan['quantity'],
          'birim_fiyat': plan['unit_price'], 'toplam_tutar': ((plan['quantity'] as double) * (plan['unit_price'] as int)).round(),
          'tarih': plan['date'], 'belge_no': plan['number'], 'aciklama': AiIslemPlani.text(d, 'summary')});
      }
    }
    return {'stok_id': stockId};
  }
}
