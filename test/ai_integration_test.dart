import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_app/services/ai_islem_plani.dart';
import 'package:test_app/services/ai_kayit_service.dart';

Map<String, dynamic> draft(String id, {String category = 'CEK_SENET'}) => {
  'request_id': id, 'firma_id': 1, 'islem_kategorisi': category,
  'islem_tarihi': '2026-09-07', 'cari_unvan': 'Örnek Müşteri', 'yeni_cari_onay': true,
  'kesideci': 'Örnek Keşideci', 'evrak_no': '000123', 'banka_adi': 'Örnek Banka',
  'tutar': 95000, 'vade_tarihi': '2026-10-01', 'evrak_turu': 'MUSTERI_CEKI',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final sql = File('test/fixtures/ai_schema.sql').readAsStringSync();
    for (final statement in sql.split(';').where((s) => s.trim().isNotEmpty)) {
      await db.execute(statement);
    }
    await db.insert('depolar', {'depo_adi': 'Merkez', 'varsayilan': 1});
  });
  tearDown(() => db.close());

  test('cheque links issuer, actual counterparty, calendar and balanced journal', () async {
    final result = await AiKayitService.kaydetDb(db, draft('cheque-test-000001'), 1);
    final cheque = (await db.query('cek_senet_bordro')).single;
    final cari = (await db.query('cariler')).single;
    expect(cari['unvan'], 'Örnek Müşteri');
    expect(cheque['kesideci'], 'Örnek Keşideci');
    expect(cheque['hareket_id'], result['hareket_id']);
    expect(cheque['tutar'], 9500000);
    expect(cari['bakiye'], -9500000);
    final rows = await db.query('yevmiye_kayitlari');
    expect(rows.map((r) => r['hesap_kodu']), ['101', '120']);
    expect(rows.fold<int>(0, (s, r) => s + (r['borc'] as int) - (r['alacak'] as int)), 0);
    expect(rows.where((r) => r['hesap_kodu'] == '100' || r['hesap_kodu'] == '102'), isEmpty);
  });

  test('received promissory note has receivable direction', () async {
    final d = draft('note-test-0000001')
      ..['evrak_turu'] = 'MUSTERI_SENEDI'
      ..['banka_adi'] = '';
    await AiKayitService.kaydetDb(db, d, 1);
    expect((await db.query('cariler')).single['bakiye'], -9500000);
    expect((await db.query('yevmiye_kayitlari')).first['hesap_kodu'], '121');
  });

  test('same request can commit only once', () async {
    final d = draft('same-request-00001');
    final first = await AiKayitService.kaydetDb(db, d, 1);
    final second = await AiKayitService.kaydetDb(db, d, 1);
    expect(second, first);
    expect((await db.query('cari_hareketler')).length, 1);
    expect((await db.query('cariler')).single['bakiye'], -9500000);
  });

  test('same cheque with another request and another new cari rolls back', () async {
    await AiKayitService.kaydetDb(db, draft('first-request-001'), 1);
    final duplicate = draft('other-request-001')
      ..['cari_unvan'] = 'Başka Cari';
    await expectLater(AiKayitService.kaydetDb(db, duplicate, 1), throwsFormatException);
    expect((await db.query('cariler')).length, 1);
    expect((await db.query('cari_hareketler')).length, 1);
  });

  test('journal failure rolls back cheque, cari and balance together', () async {
    await db.execute("CREATE TRIGGER reject_rows BEFORE INSERT ON yevmiye_kayitlari BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    await expectLater(AiKayitService.kaydetDb(db, draft('failed-request-001'), 1), throwsA(isA<DatabaseException>()));
    expect(await db.query('cariler'), isEmpty);
    expect(await db.query('cek_senet_bordro'), isEmpty);
    expect(await db.query('cari_hareketler'), isEmpty);
  });

  test('company mismatch, missing direction and invalid dates do not write', () async {
    await expectLater(AiKayitService.kaydetDb(db, draft('bad-company-00001'), 2), throwsFormatException);
    final date = draft('bad-date-00000001')
      ..['vade_tarihi'] = '2026-02-31';
    await expectLater(AiKayitService.kaydetDb(db, date, 1), throwsFormatException);
    final direction = draft('bad-type-00000001')..remove('evrak_turu');
    await expectLater(AiKayitService.kaydetDb(db, direction, 1), throwsFormatException);
    expect(await db.query('cariler'), isEmpty);
  });

  test('gross sale and partial payment retain remaining invoice amount', () async {
    final sale = draft('sale-request-001', category: 'TICARI_CARI')
      
      ..['tutar'] = 1200
      ..['kdv_tutari'] = 200
      ..['yon'] = 'SATIS'
      ..['odeme_yontemi'] = 'AÇIK_HESAP';
    final saved = await AiKayitService.kaydetDb(db, sale, 1);
    final payment = draft('payment-request-01', category: 'TAHSILAT_ODEME')
      
      ..['cari_id'] = saved['cari_id']
      ..['yeni_cari_onay'] = false
      
      ..['tutar'] = 400
      ..['yon'] = 'TAHSILAT'
      ..['odeme_yontemi'] = 'HAVALE'
      
      ..['kapatilacak_hareket_id'] = saved['hareket_id'];
    await AiKayitService.kaydetDb(db, payment, 1);
    expect((await db.query('cariler')).single['bakiye'], 80000);
    expect((await db.query('ai_odeme_eslestirme')).single['tutar'], 40000);
    expect((await db.rawQuery("SELECT SUM(borc-alacak) AS n FROM yevmiye_kayitlari WHERE hesap_kodu='102'")).single['n'], 40000);
    payment['request_id'] = 'overpayment-00001';
    payment['tutar'] = 900;
    await expectLater(AiKayitService.kaydetDb(db, payment, 1), throwsFormatException);
    expect((await db.query('cariler')).single['bakiye'], 80000);
  });

  test('stock movement is atomic and insufficient stock does not post', () async {
    final create = draft('stock-create-00001', category: 'STOK_DEPO_ISLEMI')
      
      ..['action_type'] = 'YENI_STOK_KARTI'
      ..['stok_adi'] = 'Örnek Ürün'
      ..['stok_kodu'] = 'TEST001'
      
      ..['birim'] = 'Adet'
      ..['alis_fiyati'] = 10
      ..['satis_fiyati'] = 15;
    final result = await AiKayitService.kaydetDb(db, create, 1);
    final entry = Map<String, dynamic>.from(create)
      ..['request_id'] = 'stock-entry-00001'
      
      ..['action_type'] = 'STOK_GIRIS'
      ..['stok_id'] = result['stok_id']
      ..['depo_id'] = 1
      
      ..['miktar'] = 5
      ..['birim_fiyat'] = 10;
    await AiKayitService.kaydetDb(db, entry, 1);
    final exit = Map<String, dynamic>.from(entry)
      ..['request_id'] = 'stock-exit-000001'
      
      ..['action_type'] = 'STOK_CIKIS'
      ..['miktar'] = 6;
    await expectLater(AiKayitService.kaydetDb(db, exit, 1), throwsFormatException);
    expect((await db.query('stok_hareketleri')).length, 1);
    expect(await db.query('yevmiye_kayitlari'), isEmpty);
  });

  test('cash transfer affects no customer or profit', () async {
    final d = draft('transfer-00000001', category: 'VIRMAN')
      ..['yon'] = 'KASA_BANKA'
      ..['tutar'] = 100;
    await AiKayitService.kaydetDb(db, d, 1);
    expect(await db.query('cariler'), isEmpty);
    expect((await db.query('yevmiye_kayitlari')).map((r) => r['hesap_kodu']), ['102', '100']);
  });

  test('ambiguous separators never turn 1000 into 1', () {
    expect(AiIslemPlani.kurus('95000,50'), 9500050);
    expect(AiIslemPlani.kurus(95000.0), 9500000);
    expect(() => AiIslemPlani.kurus('1.000'), throwsFormatException);
    expect(() => AiIslemPlani.kurus('1.000,50'), throwsFormatException);
    expect(() => AiIslemPlani.kurus(double.nan), throwsFormatException);
  });
}
