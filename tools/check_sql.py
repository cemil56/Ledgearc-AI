"""Runs the actual schema and calendar SELECTs extracted from database_service.dart.
Does not substitute for flutter test: Dart transaction logic is tested separately.
"""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'lib/services/database_service.dart').read_text(encoding='utf-8')
SCHEMA = (ROOT / 'test/fixtures/ai_schema.sql').read_text(encoding='utf-8')
section = SOURCE[SOURCE.index('getOdemeTakvimi'):SOURCE.index('getYevmiyeDefteri')]
QUERIES = re.findall(r'"""(.*?)"""', section, re.S)

class SqlTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        self.db.execute("INSERT INTO cariler(id,unvan,bakiye) VALUES(1,'Actual counterparty',0)")

    def tearDown(self):
        self.db.close()

    def test_calendar_uses_actual_counterparty_and_preserves_leading_zero(self):
        self.db.execute("INSERT INTO cek_senet_bordro(cari_id,evrak_no,evrak_turu,kesideci,banka_adi,tutar,vade_tarihi) VALUES(1,'000123','MUSTERI_SENEDI','Issuer','',9500000,'2026-10-01')")
        row = self.db.execute(QUERIES[1]).fetchone()
        self.assertEqual(row['cari_unvan'], 'Actual counterparty')
        self.assertEqual(row['borc'], 9500000)
        self.assertEqual(row['alacak'], 0)
        self.assertEqual(row['fatura_no'], '000123')
        self.db.execute("UPDATE cek_senet_bordro SET durum='TAHSIL_EDILDI'")
        self.assertEqual(self.db.execute(QUERIES[1]).fetchall(), [])

    def test_partial_payment_and_closed_invoice(self):
        self.db.execute("INSERT INTO cari_hareketler(id,cari_id,borc,alacak,odeme_yontemi) VALUES(1,1,120000,0,'AÇIK_HESAP')")
        self.db.execute("INSERT INTO cari_hareketler(id,cari_id,borc,alacak,odeme_yontemi) VALUES(2,1,0,40000,'HAVALE')")
        self.db.execute("INSERT INTO ai_odeme_eslestirme VALUES(2,1,40000)")
        rows = self.db.execute(QUERIES[0]).fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['borc'], 80000)
        self.db.execute("INSERT INTO ai_odeme_eslestirme VALUES(3,1,80000)")
        self.assertEqual(self.db.execute(QUERIES[0]).fetchall(), [])

    def test_schema_migration_retains_existing_rows(self):
        old = sqlite3.connect(':memory:')
        old.executescript(';'.join(s for s in SCHEMA.split(';') if s.strip() and 'ALTER TABLE' not in s and 'ai_odeme_eslestirme' not in s) + ';')
        old.execute("INSERT INTO cariler(unvan,bakiye) VALUES('Existing',1234)")
        for statement in SCHEMA.split(';'):
            if 'ALTER TABLE' in statement or 'ai_odeme_eslestirme' in statement:
                old.execute(statement)
        self.assertEqual(old.execute('SELECT bakiye FROM cariler').fetchone()[0], 1234)
        old.close()

if __name__ == '__main__':
    assert len(QUERIES) == 2
    unittest.main()
