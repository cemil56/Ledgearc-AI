/// Deterministic validation and posting plan; the model never supplies SQL or ledger rows.
class AiIslemPlani {
  static String text(Map<String, dynamic> d, String k) => d[k]?.toString().trim() ?? '';
  static String requiredText(Map<String, dynamic> d, String k, String label) {
    final v = text(d, k);
    if (v.isEmpty || v.toLowerCase() == 'null') throw FormatException('$label gerekli.');
    return v;
  }

  static int kurus(dynamic value, {bool zero = false}) {
    // Strings use ungrouped decimal notation only. Never silently reinterpret 1.000.
    final raw = value?.toString().trim().replaceAll(',', '.') ?? '';
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) {
      throw const FormatException('Tutarı binlik ayırıcı olmadan yazın: 95000,50.');
    }
    final parts = raw.split('.');
    final n = int.parse(parts[0]) * 100 + int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
    if (n < (zero ? 0 : 1) || n > 9000000000000) throw const FormatException('Tutar geçerli aralıkta değil.');
    return n;
  }

  static String date(Map<String, dynamic> d, String key, String label) {
    final raw = requiredText(d, key, label);
    final v = DateTime.tryParse(raw);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) || v == null ||
        v.toIso8601String().substring(0, 10) != raw) {
      throw FormatException('$label geçerli bir YYYY-MM-DD tarihi olmalı.');
    }
    return raw;
  }

  static double quantity(dynamic value) {
    final v = double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
    if (v == null || !v.isFinite || v <= 0 || v > 1000000000) {
      throw const FormatException('Miktar pozitif bir sayı olmalı.');
    }
    return v;
  }

  static Map<String, dynamic> build(Map<String, dynamic> d) {
    final cat = requiredText(d, 'islem_kategorisi', 'Kategori');
    final day = date(d, 'islem_tarihi', 'Kayıt tarihi');
    final plan = <String, dynamic>{'category': cat, 'date': day, 'rows': <Map<String, dynamic>>[],
      'debit': 0, 'credit': 0, 'payment': 'AÇIK_HESAP', 'due': '', 'number': text(d, 'evrak_no')};
    if (cat == 'STOK_DEPO_ISLEMI') {
      final action = text(d, 'action_type');
      if (!const ['YENI_STOK_KARTI', 'FIYAT_GUNCELLE', 'STOK_GIRIS', 'STOK_CIKIS'].contains(action)) {
        throw const FormatException('Stok işlem türünü seçin.');
      }
      requiredText(d, 'stok_adi', 'Stok adı');
      if (action == 'YENI_STOK_KARTI') {
        requiredText(d, 'stok_kodu', 'Stok kodu');
        requiredText(d, 'birim', 'Birim');
      } else if (d['stok_id'] is! int) {
        throw const FormatException('Mevcut stok kartını seçin.');
      }
      if (action == 'STOK_GIRIS' || action == 'STOK_CIKIS') {
        if (d['depo_id'] is! int) throw const FormatException('Depoyu seçin.');
        plan['quantity'] = quantity(d['miktar']);
        plan['unit_price'] = kurus(d['birim_fiyat'], zero: true);
      } else {
        plan['buy'] = kurus(d['alis_fiyati'], zero: true);
        plan['sell'] = kurus(d['satis_fiyati'], zero: true);
      }
      plan['action'] = action;
      return plan;
    }
    if (!const ['CEK_SENET', 'TICARI_CARI', 'ISLETME_GIDERI', 'PERSONEL', 'TAHSILAT_ODEME', 'VIRMAN'].contains(cat)) {
      throw const FormatException('Bu işlem kategorisi desteklenmiyor.');
    }
    final amount = kurus(d['tutar']);
    plan['amount'] = amount;
    if (cat != 'VIRMAN') {
      requiredText(d, 'cari_unvan', 'Karşı taraf');
      if (d['cari_id'] is! int && d['yeni_cari_onay'] != true) {
        throw const FormatException('Mevcut cariyi seçin veya yeni cari açılmasını onaylayın.');
      }
    }
    final rows = plan['rows'] as List<Map<String, dynamic>>;
    void row(String code, String name, int debit, int credit) {
      if (debit != 0 || credit != 0) rows.add({'code': code, 'name': name, 'debit': debit, 'credit': credit});
    }
    if (cat == 'CEK_SENET') {
      final type = text(d, 'evrak_turu');
      if (!const ['MUSTERI_CEKI', 'BORC_CEKI', 'MUSTERI_SENEDI', 'BORC_SENEDI'].contains(type)) {
        throw const FormatException('Alınan/verilen çek veya senet türünü seçin.');
      }
      plan['number'] = requiredText(d, 'evrak_no', 'Evrak numarası');
      requiredText(d, 'kesideci', 'Keşideci');
      if (type.contains('CEK')) requiredText(d, 'banka_adi', 'Banka');
      plan['due'] = date(d, 'vade_tarihi', 'Vade tarihi');
      plan['payment'] = type.contains('CEK') ? 'CEK' : 'SENET';
      final received = type.startsWith('MUSTERI');
      plan['credit'] = received ? amount : 0;
      plan['debit'] = received ? 0 : amount;
      if (received) {
        row(type.contains('CEK') ? '101' : '121', type.contains('CEK') ? 'Alınan Çekler' : 'Alacak Senetleri', amount, 0);
        row('120', 'Alıcılar', 0, amount);
      } else {
        row('320', 'Satıcılar', amount, 0);
        row(type.contains('CEK') ? '103' : '321', type.contains('CEK') ? 'Verilen Çekler' : 'Borç Senetleri', 0, amount);
      }
    } else {
      final payment = text(d, 'odeme_yontemi');
      if (cat != 'VIRMAN' && !const ['NAKİT', 'HAVALE', 'AÇIK_HESAP'].contains(payment)) {
        throw const FormatException('Ödeme yöntemini seçin.');
      }
      final paid = payment != 'AÇIK_HESAP';
      final cash = payment == 'NAKİT' ? '100' : '102';
      final cashName = payment == 'NAKİT' ? 'Kasa' : 'Bankalar';
      plan['payment'] = payment;
      if (cat == 'VIRMAN') {
        final direction = text(d, 'yon');
        if (!const ['KASA_BANKA', 'BANKA_KASA'].contains(direction)) throw const FormatException('Virman yönünü seçin.');
        final toBank = direction == 'KASA_BANKA';
        row(toBank ? '102' : '100', toBank ? 'Bankalar' : 'Kasa', amount, 0);
        row(toBank ? '100' : '102', toBank ? 'Kasa' : 'Bankalar', 0, amount);
        plan['payment'] = 'VIRMAN';
      } else if (cat == 'TAHSILAT_ODEME') {
        if (!paid) throw const FormatException('Tahsilat/ödeme için kasa veya banka seçin.');
        final incoming = text(d, 'yon') == 'TAHSILAT';
        if (!const ['TAHSILAT', 'ODEME'].contains(text(d, 'yon'))) throw const FormatException('Tahsilat/ödeme yönünü seçin.');
        plan[incoming ? 'credit' : 'debit'] = amount;
        row(incoming ? cash : '320', incoming ? cashName : 'Satıcılar', amount, 0);
        row(incoming ? '120' : cash, incoming ? 'Alıcılar' : cashName, 0, amount);
      } else if (cat == 'PERSONEL') {
        if (!paid) throw const FormatException('Personel ödemesi için kasa veya banka seçin.');
        final action = text(d, 'action_type');
        if (!const ['PERSONEL_AVANS', 'MAAS_ODEME'].contains(action)) throw const FormatException('Personel işlem türünü seçin.');
        row(action == 'PERSONEL_AVANS' ? '196' : '335', action == 'PERSONEL_AVANS' ? 'Personel Avansları' : 'Personele Borçlar', amount, 0);
        row(cash, cashName, 0, amount);
        plan['debit'] = amount;
      } else {
        final tax = kurus(d['kdv_tutari'], zero: true);
        if (tax >= amount) throw const FormatException('KDV tutarı toplamdan küçük olmalı.');
        final sale = cat == 'TICARI_CARI' && text(d, 'yon') == 'SATIS';
        if (cat == 'TICARI_CARI' && !const ['ALIS', 'SATIS'].contains(text(d, 'yon'))) throw const FormatException('Alış/satış yönünü seçin.');
        plan['number'] = requiredText(d, 'evrak_no', 'Belge numarası');
        if (!paid) plan['due'] = date(d, 'vade_tarihi', 'Vade tarihi');
        if (sale) {
          row('120', 'Alıcılar', amount, 0);
          row('600', 'Yurtiçi Satışlar', 0, amount - tax);
          row('391', 'Hesaplanan KDV', 0, tax);
          plan['debit'] = amount;
          if (paid) { row(cash, cashName, amount, 0); row('120', 'Alıcılar', 0, amount); plan['credit'] = amount; }
        } else {
          final account = text(d, 'hesap_kodu');
          if (!const ['153', '740', '760', '770'].contains(account)) throw const FormatException('Alış/gider hesabını seçin.');
          const names = {'153': 'Ticari Mallar', '740': 'Hizmet Üretim Maliyeti', '760': 'Pazarlama Satış Dağıtım Giderleri', '770': 'Genel Yönetim Giderleri'};
          row(account, names[account]!, amount - tax, 0);
          row('191', 'İndirilecek KDV', tax, 0);
          row('320', 'Satıcılar', 0, amount);
          plan['credit'] = amount;
          if (paid) { row('320', 'Satıcılar', amount, 0); row(cash, cashName, 0, amount); plan['debit'] = amount; }
        }
      }
    }
    final debit = rows.fold<int>(0, (sum, r) => sum + (r['debit'] as int));
    final credit = rows.fold<int>(0, (sum, r) => sum + (r['credit'] as int));
    if (debit <= 0 || debit != credit) throw const FormatException('Kayıt dengesi doğrulanamadı.');
    return plan;
  }
}
