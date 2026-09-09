import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/firma_provider.dart';
import '../providers/cari_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/yevmiye_provider.dart';
import '../services/ai_islem_plani.dart';
import '../services/ai_kayit_service.dart';
import '../services/database_service.dart';

class AiOnayKarti extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  const AiOnayKarti({super.key, required this.item});
  @override
  ConsumerState<AiOnayKarti> createState() => _AiOnayKartiState();
}

class _AiOnayKartiState extends ConsumerState<AiOnayKarti> {
  Map<String, dynamic> get d => widget.item;
  final controllers = <String, TextEditingController>{};
  List<Map<String, dynamic>> cariler = [], stocks = [], depots = [], invoices = [];
  bool loading = true, busy = false;
  String? error;
  final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  @override
  void initState() {
    super.initState();
    d['islem_tarihi'] ??= DateTime.now().toIso8601String().substring(0, 10);
    if (AiIslemPlani.text(d, 'evrak_no').isEmpty) d['evrak_no'] = d['fatura_no'];
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await DatabaseService.instance.getDatabase(firmaId: d['firma_id'] as int);
      final values = await Future.wait([
        db.query('cariler', orderBy: 'unvan'),
        db.query('stok_kartlari', orderBy: 'stok_adi'),
        db.query('depolar', orderBy: 'depo_adi'),
        db.query('cari_hareketler', where: 'odeme_yontemi = ? AND borc != alacak', whereArgs: ['AÇIK_HESAP']),
      ]);
      if (mounted) setState(() { cariler = values[0]; stocks = values[1]; depots = values[2]; invoices = values[3]; });
    } catch (_) {
      if (mounted) setState(() => error = 'Cari/stok listeleri yüklenemedi. Kartı yeniden açın.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) { c.dispose(); }
    super.dispose();
  }

  bool get locked => busy || d['is_saved'] == true;
  Widget field(String key, String label, {bool readOnly = false}) {
    final c = controllers.putIfAbsent(key, () => TextEditingController(text: AiIslemPlani.text(d, key)));
    return Padding(padding: const EdgeInsets.only(top: 8), child: TextField(
      controller: c, enabled: !locked && !readOnly,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      onChanged: (value) { d[key] = value.trim(); },
    ));
  }

  Widget choice(String key, String label, Map<String, String> values) {
    final current = AiIslemPlani.text(d, key);
    return Padding(padding: const EdgeInsets.only(top: 8), child: DropdownButtonFormField<String>(
      key: ValueKey('$key:$current'),
      initialValue: values.containsKey(current) ? current : null,
      isExpanded: true, decoration: InputDecoration(labelText: label),
      items: values.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: locked ? null : (v) => setState(() { d[key] = v; error = null; }),
    ));
  }

  Widget catalogue(String key, String label, List<Map<String, dynamic>> rows, String title) {
    final ids = rows.map((r) => r['id']).toSet();
    return Padding(padding: const EdgeInsets.only(top: 8), child: DropdownButtonFormField<int>(
      key: ValueKey('$key:${d[key]}'), initialValue: ids.contains(d[key]) ? d[key] as int : null,
      isExpanded: true, decoration: InputDecoration(labelText: label),
      items: rows.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r[title].toString(), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: locked ? null : (v) => setState(() {
        d[key] = v;
        final selected = rows.firstWhere((r) => r['id'] == v);
        if (key == 'cari_id') {
          d.remove('kapatilacak_hareket_id');
          d['cari_unvan'] = selected['unvan'];
          d['yeni_cari_onay'] = false;
          controllers['cari_unvan']?.text = selected['unvan'].toString();
        }
        if (key == 'stok_id') {
          d['stok_adi'] = selected['stok_adi'];
          controllers['stok_adi']?.text = selected['stok_adi'].toString();
          for (final price in ['alis_fiyati', 'satis_fiyati']) {
            if (AiIslemPlani.text(d, price).isEmpty) {
              d[price] = ((selected[price] as num?)?.toDouble() ?? 0) / 100;
              controllers[price]?.text = d[price].toString();
            }
          }
        }
      }),
    ));
  }

  Future<void> save() async {
    if (locked || loading) return;
    setState(() { busy = true; error = null; });
    try {
      final firma = ref.read(firmaProvider);
      if (d['firma_id'] != firma.aktifFirmaId) throw const FormatException('Belgenin ait olduğu firmaya geçin.');
      final snapshot = Map<String, dynamic>.from(d);
      final plan = AiIslemPlani.build(snapshot);
      final rows = plan['rows'] as List<Map<String, dynamic>>;
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Kaydı onayla'),
        content: SizedBox(width: 540, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Firma: ${firma.aktifFirmaUnvan}'),
            Text('Karşı taraf: ${AiIslemPlani.text(snapshot, 'cari_unvan')}'),
            if (plan['amount'] != null) Text('Tutar: ${money.format((plan['amount'] as int) / 100)}'),
            Text('Kayıt tarihi: ${plan['date']}'),
            if ((plan['due'] as String).isNotEmpty) Text('Vade: ${plan['due']}'),
            if (rows.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Deftere işlenecek satırlar:')),
            ...rows.map((r) => Text('${r['code']} ${r['name']} — Borç ${money.format((r['debit'] as int) / 100)} / Alacak ${money.format((r['credit'] as int) / 100)}')),
            if (plan['category'] == 'STOK_DEPO_ISLEMI') const Text('Stok işlemi kaydedilecek. Tek başına mali defter kaydı oluşturmaz.'),
            const SizedBox(height: 12),
            const Text('Onayladığınızda bilgiler veritabanına kaydedilir. Bu işlem resmî e-fatura göndermez.'),
          ],
        ))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Onayla ve Kaydet'))],
      ));
      if (confirmed != true || !mounted) return;
      final result = await AiKayitService.kaydet(snapshot, ref.read(firmaProvider).aktifFirmaId);
      d['is_saved'] = true;
      d['save_result'] = result;
      if (!mounted) return;
      ref.read(carilerProvider.notifier).yenile();
      ref.read(ledgerProvider.notifier).yenile();
      ref.read(yevmiyeProvider.notifier).yenile();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt tamamlandı. İlgili ekranlar yenilendi.')));
    } catch (e) {
      if (mounted) setState(() => error = e is FormatException ? e.message : 'Kayıt tamamlanamadı. Dosya ve veritabanı erişimini kontrol edin.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = AiIslemPlani.text(d, 'islem_kategorisi');
    final cheque = cat == 'CEK_SENET', stock = cat == 'STOK_DEPO_ISLEMI';
    final invoice = cat == 'TICARI_CARI' || cat == 'ISLETME_GIDERI';
    final active = ref.watch(firmaProvider).aktifFirmaId == d['firma_id'];
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('İşlem onay kartı', style: TextStyle(fontWeight: FontWeight.bold)),
        if (loading) const LinearProgressIndicator(),
        if (!active) const Text('Bu taslak başka firmaya ait. Kaydetmek için ilgili firmaya geçin.'),
        field('islem_tarihi', 'Kayıt tarihi (YYYY-MM-DD)'),
        if (!stock && cat != 'VIRMAN') ...[
          catalogue('cari_id', 'Mevcut cari seçin', cariler, 'unvan'),
          CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Bu adla yeni cari açılmasını onaylıyorum'),
            value: d['yeni_cari_onay'] == true,
            onChanged: locked ? null : (v) => setState(() { d['yeni_cari_onay'] = v; if (v == true) d.remove('cari_id'); })),
          field('cari_unvan', 'Karşı taraf (cari)', readOnly: d['cari_id'] != null),
        ],
        if (stock) ...[
          choice('action_type', 'Stok işlemi', const {'YENI_STOK_KARTI': 'Yeni stok kartı', 'FIYAT_GUNCELLE': 'Fiyat güncelle', 'STOK_GIRIS': 'Stok girişi', 'STOK_CIKIS': 'Stok çıkışı'}),
          if (d['action_type'] != 'YENI_STOK_KARTI') catalogue('stok_id', 'Stok kartı', stocks, 'stok_adi'),
          field('stok_adi', 'Stok adı', readOnly: d['action_type'] != 'YENI_STOK_KARTI'),
          if (d['action_type'] == 'YENI_STOK_KARTI') ...[field('stok_kodu', 'Stok kodu'), field('birim', 'Birim (Adet, Kg...)')],
          if (const ['STOK_GIRIS', 'STOK_CIKIS'].contains(d['action_type'])) ...[
            catalogue('depo_id', 'Depo', depots, 'depo_adi'), field('miktar', 'Miktar'), field('birim_fiyat', 'Birim fiyat (TL)'),
          ] else ...[field('alis_fiyati', 'Alış fiyatı (TL)'), field('satis_fiyati', 'Satış fiyatı (TL)')],
        ] else field('tutar', 'Toplam tutar (TL; binlik ayırıcı kullanmayın)'),
        if (cheque || invoice) field('evrak_no', 'Belge / evrak numarası'),
        if (cheque) ...[
          field('kesideci', 'Keşideci (çeki/senedi düzenleyen)'), field('banka_adi', 'Banka (çek için gerekli)'),
          choice('evrak_turu', 'Evrak yönü', const {'MUSTERI_CEKI': 'Alınan müşteri çeki', 'BORC_CEKI': 'Verilen kendi çekimiz', 'MUSTERI_SENEDI': 'Alınan senet', 'BORC_SENEDI': 'Verilen senet'}),
          field('vade_tarihi', 'Vade tarihi (YYYY-MM-DD)'),
        ],
        if (cat == 'TICARI_CARI') choice('yon', 'Fatura yönü', const {'ALIS': 'Alış', 'SATIS': 'Satış'}),
        if (cat == 'TAHSILAT_ODEME') choice('yon', 'İşlem yönü', const {'TAHSILAT': 'Müşteriden tahsilat', 'ODEME': 'Satıcıya ödeme'}),
        if (cat == 'TAHSILAT_ODEME' || cheque) ...[
          catalogue('kapatilacak_hareket_id', 'Ödemeyi faturaya bağla (isteğe bağlı)',
            invoices.where((r) => r['cari_id'] == d['cari_id']).map((r) => <String, dynamic>{...r,
              'etiket': '${r['fatura_no']} • ${r['tarih']}'}).toList(), 'etiket'),
          TextButton(onPressed: locked ? null : () => setState(() => d.remove('kapatilacak_hareket_id')),
            child: const Text('Fatura eşleştirmesini kaldır')),
          const Text('Fatura seçilmezse yalnızca cari bakiyesi değişir; açık faturanın takvim tutarı kapanmaz.'),
        ],
        if (cat == 'VIRMAN') choice('yon', 'Transfer yönü', const {'KASA_BANKA': 'Kasadan bankaya', 'BANKA_KASA': 'Bankadan kasaya'}),
        if (cat == 'PERSONEL') ...[
          choice('action_type', 'Personel işlemi', const {'PERSONEL_AVANS': 'Personel avansı', 'MAAS_ODEME': 'Tahakkuk etmiş maaşın ödenmesi'}),
          const Text('Maaş bordrosu, vergi veya SGK tahakkuku oluşturulmaz.'),
        ],
        if (invoice) ...[
          field('kdv_tutari', 'Belgedeki KDV tutarı (yoksa 0 yazın)'),
          if (cat == 'ISLETME_GIDERI' || d['yon'] == 'ALIS') choice('hesap_kodu', 'Alış / gider hesabı', const {
            '153': '153 Ticari Mallar', '740': '740 Hizmet Üretim Maliyeti', '760': '760 Pazarlama Satış Dağıtım', '770': '770 Genel Yönetim Giderleri'}),
          const Text('Bu kart tek toplam ve KDV içindir. Tevkifat/istisna/iade belgeleri için kullanmayın. Stok miktarını ayrı stok işlemiyle kaydedin.'),
        ],
        if (!cheque && !stock && cat != 'VIRMAN') choice('odeme_yontemi', 'Ödeme yöntemi', const {'NAKİT': 'Nakit', 'HAVALE': 'Banka', 'AÇIK_HESAP': 'Açık hesap'}),
        if (invoice && d['odeme_yontemi'] == 'AÇIK_HESAP') field('vade_tarihi', 'Vade tarihi (YYYY-MM-DD)'),
        field('summary', 'Açıklama'),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 8),
        FilledButton(onPressed: locked || loading || !active ? null : save,
          child: Text(d['is_saved'] == true ? 'Kaydedildi' : busy ? 'İşleniyor…' : 'Kontrol Et ve Kaydet')),
      ],
    )));
  }
}
