"""Smoke-check production schema/migration SQL; does not execute Dart/Flutter."""
from pathlib import Path
import re
import sqlite3

source = (Path(__file__).parents[1] / 'lib/services/database_service.dart').read_text()
schema = re.findall(r"'''(CREATE TABLE IF NOT EXISTS .*?)'''", source)
migration = re.findall(r"await db.execute\('(ALTER TABLE .*?|CREATE INDEX IF NOT EXISTS .*?)'\)", source)
assert len(schema) == 7 and len(migration) == 3
db = sqlite3.connect(':memory:')
for sql in schema:
    db.execute(sql)
db.execute("INSERT INTO cariler(id,unvan,bakiye) VALUES(1,'Test',12000)")
db.execute("INSERT INTO cari_hareketler(id,cari_id,borc,alacak) VALUES(1,1,12000,0)")
for sql in migration:
    db.execute(sql)
assert db.execute('SELECT guvenli_baglanti FROM cari_hareketler').fetchone() == (0,)
assert db.execute('SELECT bakiye FROM cariler').fetchone() == (12000,)
# Linked rows with identical invoice numbers must remain distinguishable.
for ident in (1, 2):
    db.execute("INSERT INTO yevmiye_kayitlari(hareket_id,fis_no) VALUES(?,'SAME')", (ident,))
    db.execute("INSERT INTO stok_hareketleri(stok_id,depo_id,hareket_tipi,miktar,birim_fiyat,toplam_tutar,tarih,belge_no,hareket_id) VALUES(1,1,'GIRIS',1,100,100,'2026-09-06','SAME',?)", (ident,))
db.commit()
update = re.search(r"'UPDATE cariler SET bakiye = bakiye - \? WHERE id = \?'", source).group()[1:-1]
try:
    with db:
        db.execute(update, (12000, 1))
        db.execute('DELETE FROM stok_hareketleri WHERE hareket_id = ?', (1,))
        raise RuntimeError('Simulated interrupted delete')
except RuntimeError:
    pass
assert db.execute('SELECT bakiye FROM cariler').fetchone() == (12000,)
assert db.execute('SELECT COUNT(*) FROM stok_hareketleri').fetchone() == (2,)
with db:
    db.execute(update, (12000, 1))
    for table in ('stok_hareketleri', 'yevmiye_kayitlari'):
        db.execute(f'DELETE FROM {table} WHERE hareket_id = ?', (1,))
    db.execute('DELETE FROM cari_hareketler WHERE id = ?', (1,))
assert db.execute('SELECT bakiye FROM cariler').fetchone() == (0,)
for table in ('stok_hareketleri', 'yevmiye_kayitlari'):
    assert db.execute(f'SELECT hareket_id FROM {table}').fetchall() == [(2,)]
print('PASS: migration preserves legacy rows; linked SQL deletion and rollback')
