import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test_app/services/ai_kayit_service.dart';

Map<String, dynamic> _draft(String id) => {
  'request_id': id,
  'firma_id': 1,
  'islem_kategorisi': 'CEK_SENET',
  'islem_tarihi': '2026-09-10',
  'cari_unvan': 'Örnek Cari',
  'yeni_cari_onay': true,
  'kesideci': 'Örnek Keşideci A.Ş.',
  'evrak_no': '000123',
  'banka_adi': 'TÜRKİYE İŞ BANKASI',
  'tutar': 95000,
  'vade_tarihi': '2026-10-01',
  'evrak_turu': 'MUSTERI_CEKI',
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
  });
  tearDown(() => db.close());

  Future<void> expectOnlyOriginal() async {
    expect((await db.query('cariler')).length, 1);
    expect((await db.query('cariler')).single['bakiye'], -9500000);
    expect((await db.query('cek_senet_bordro')).length, 1);
    expect((await db.query('cari_hareketler')).length, 1);
    expect((await db.query('yevmiye_kayitlari')).length, 2);
    expect((await db.query('ai_kayitlar')).length, 1);
    expect((await db.query('ai_onaylar')).length, 1);
  }

  test('same physical cheque cannot be entered again as an issued cheque', () async {
    await AiKayitService.kaydetDb(db, _draft('received-cheque-01'), 1);
    final other = _draft('issued-cheque-001')
      ..['evrak_turu'] = 'BORC_CEKI'
      ..['cari_unvan'] = 'Başka Cari';
    await expectLater(AiKayitService.kaydetDb(db, other, 1), throwsFormatException);
    await expectOnlyOriginal();
  });

  test('Turkish case, ASCII spelling, spacing and punctuation do not bypass the guard', () async {
    await AiKayitService.kaydetDb(db, _draft('original-cheque-01'), 1);
    final other = _draft('formatted-cheque-01')
      ..['cari_unvan'] = 'Başka Cari'
      ..['evrak_no'] = ' 000 123 '
      ..['banka_adi'] = ' turkiye is bankasi '
      ..['kesideci'] = 'ORNEK\n KESIDECI AS';
    await expectLater(AiKayitService.kaydetDb(db, other, 1), throwsFormatException);
    await expectOnlyOriginal();
  });

  test('a settled cheque remains protected when amount and date change', () async {
    await AiKayitService.kaydetDb(db, _draft('settled-cheque-01'), 1);
    await db.update('cek_senet_bordro', {'durum': 'TAHSIL_EDILDI'});
    final other = _draft('reentered-cheque-01')
      ..['cari_unvan'] = 'Başka Cari'
      ..['tutar'] = 100000
      ..['vade_tarihi'] = '2026-11-01'
      ..['islem_tarihi'] = '2026-09-11';
    await expectLater(AiKayitService.kaydetDb(db, other, 1), throwsFormatException);
    await expectOnlyOriginal();
  });

  test('two distinct cheques can be saved against the same existing customer', () async {
    final first = await AiKayitService.kaydetDb(db, _draft('first-serial-001'), 1);
    final second = _draft('second-serial-001')
      ..['evrak_no'] = '000124'
      ..['cari_id'] = first['cari_id']
      ..['yeni_cari_onay'] = false;
    await AiKayitService.kaydetDb(db, second, 1);
    expect((await db.query('cariler')).length, 1);
    expect((await db.query('cariler')).single['bakiye'], -19000000);
    expect((await db.query('cek_senet_bordro')).length, 2);
    expect((await db.query('cari_hareketler')).length, 2);
    expect((await db.query('yevmiye_kayitlari')).length, 4);
  });

  test('the same serial at another bank is not automatically a duplicate', () async {
    final first = await AiKayitService.kaydetDb(db, _draft('first-bank-00001'), 1);
    final second = _draft('second-bank-0001')
      ..['banka_adi'] = 'Başka Banka'
      ..['cari_id'] = first['cari_id']
      ..['yeni_cari_onay'] = false;
    await AiKayitService.kaydetDb(db, second, 1);
    expect((await db.query('cek_senet_bordro')).length, 2);
  });

  test('a different issuer with the same serial and bank remains distinct', () async {
    final first = await AiKayitService.kaydetDb(db, _draft('first-issuer-001'), 1);
    final second = _draft('other-issuer-001')
      ..['kesideci'] = 'Başka Keşideci'
      ..['cari_id'] = first['cari_id']
      ..['yeni_cari_onay'] = false;
    await AiKayitService.kaydetDb(db, second, 1);
    expect((await db.query('cek_senet_bordro')).length, 2);
  });

  test('note direction or irrelevant bank text cannot bypass the guard', () async {
    final original = _draft('original-note-001')
      ..['evrak_turu'] = 'MUSTERI_SENEDI'
      ..['banka_adi'] = '';
    await AiKayitService.kaydetDb(db, original, 1);
    final other = _draft('reentered-note-001')
      ..['evrak_turu'] = 'BORC_SENEDI'
      ..['cari_unvan'] = 'Başka Cari'
      ..['banka_adi'] = 'İlgisiz banka bilgisi';
    await expectLater(AiKayitService.kaydetDb(db, other, 1), throwsFormatException);
    await expectOnlyOriginal();
  });

  test('cheque and promissory note can have the same serial', () async {
    final first = await AiKayitService.kaydetDb(db, _draft('cheque-family-001'), 1);
    final note = _draft('note-family-00001')
      ..['evrak_turu'] = 'MUSTERI_SENEDI'
      ..['banka_adi'] = ''
      ..['cari_id'] = first['cari_id']
      ..['yeni_cari_onay'] = false;
    await AiKayitService.kaydetDb(db, note, 1);
    expect((await db.query('cek_senet_bordro')).length, 2);
  });

  test('leading zeros in serial numbers are not discarded', () async {
    final first = await AiKayitService.kaydetDb(db, _draft('padded-serial-001'), 1);
    final second = _draft('short-serial-0001')
      ..['evrak_no'] = '123'
      ..['cari_id'] = first['cari_id']
      ..['yeni_cari_onay'] = false;
    await AiKayitService.kaydetDb(db, second, 1);
    expect((await db.query('cek_senet_bordro')).length, 2);
  });

  test('concurrent duplicate requests commit only one set of records', () async {
    Future<bool> save(Map<String, dynamic> data) async {
      try {
        await AiKayitService.kaydetDb(db, data, 1);
        return true;
      } on FormatException {
        return false;
      }
    }
    final second = _draft('parallel-second-01')..['cari_unvan'] = 'Başka Cari';
    final results = await Future.wait([
      save(_draft('parallel-first-001')),
      save(second),
    ]);
    expect(results.where((saved) => saved).length, 1);
    await expectOnlyOriginal();
  });
}
