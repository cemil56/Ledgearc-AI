import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/firma_provider.dart';
import '../services/database_service.dart';
import '../services/efatura_service.dart';

class DepoStokScreen extends ConsumerStatefulWidget {
  const DepoStokScreen({super.key});
  @override
  ConsumerState<DepoStokScreen> createState() => _DepoStokScreenState();
}

class _DepoStokScreenState extends ConsumerState<DepoStokScreen> {
  final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  bool _isLoading = true;
  List<Map<String, dynamic>> _stoklar = [];
  List<Map<String, dynamic>> _depolar = [];

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    setState(() => _isLoading = true);
    try {
      final firmaId = ref.read(firmaProvider).aktifFirmaId;
      final depolar = await DatabaseService.instance.getDepolar(
        firmaId: firmaId,
      );
      final stoklar = await DatabaseService.instance.getStokListesi(
        firmaId: firmaId,
      );
      if (mounted) {
        setState(() {
          _depolar = depolar;
          _stoklar = stoklar;
        });
      }
    } catch (e) {
      debugPrint("Stok Hata: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _hareketModalAc(Map<String, dynamic> stok) {
    final miktarCtrl = TextEditingController();
    final aciklamaCtrl = TextEditingController();
    String tip = 'GIRIS';
    int seciliDepoId = _depolar.isNotEmpty ? (_depolar.first['id'] as int) : 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              "${stok['stok_adi']} - Stok Hareketi",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("📥 Stok Girişi")),
                          selected: tip == 'GIRIS',
                          selectedColor: const Color(0xFFD1FAE5),
                          onSelected: (val) {
                            if (val) {
                              setModalState(() => tip = 'GIRIS');
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("📤 Stok Çıkışı")),
                          selected: tip == 'CIKIS',
                          selectedColor: const Color(0xFFFEE2E2),
                          onSelected: (val) {
                            if (val) {
                              setModalState(() => tip = 'CIKIS');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: miktarCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: "Miktar (${stok['birim']})",
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aciklamaCtrl,
                    decoration: const InputDecoration(
                      labelText: "Açıklama / Belge",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "İptal",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tip == 'GIRIS'
                      ? const Color(0xFF059669)
                      : const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final miktar = DatabaseService.parsePara(
                    miktarCtrl.text,
                  ); // 🚨 Virgül korumalı okuma
                  if (miktar <= 0) {
                    return;
                  }
                  final firmaId = ref.read(firmaProvider).aktifFirmaId;
                  final alisFiyati = (stok['alis_fiyati'] as num? ?? 0)
                      .toDouble();

                  await DatabaseService.instance.stokHareketiEkle(
                    firmaId: firmaId,
                    stokId: stok['id'],
                    depoId: seciliDepoId,
                    hareketTipi: tip,
                    miktar: miktar,
                    birimFiyat: alisFiyati,
                    tarih: DateTime.now().toIso8601String().substring(0, 10),
                    aciklama: aciklamaCtrl.text.trim(),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _verileriYukle();
                  }
                },
                child: Text(tip == 'GIRIS' ? "Girişi Onayla" : "Çıkışı Onayla"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _faturaModalAc([Map<String, dynamic>? baslangicStok]) async {
    final firmaId = ref.read(firmaProvider).aktifFirmaId;
    final db = await DatabaseService.instance.getDatabase(firmaId: firmaId);
    final cariler = await db.query('cariler', orderBy: 'unvan ASC');
    if (cariler.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Lütfen önce Cariler sekmesinden bir cari hesap ekleyin.",
          ),
        ),
      );
      return;
    }
    if (_stoklar.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Fatura kesebilmek için en az bir stok kartı olmalı."),
        ),
      );
      return;
    }

    String tip = 'SATIS';
    int seciliCariId = cariler.first['id'] as int;
    String seciliCariUnvan = cariler.first['unvan']?.toString() ?? '';
    String seciliCariVkn =
        cariler.first['vergi_no']?.toString() ?? '11111111111';
    if (seciliCariVkn.isEmpty || seciliCariVkn == 'Belirtilmedi') {
      seciliCariVkn = '11111111111';
    }

    List<Map<String, dynamic>> faturaKalemleri = [
      {
        'stokId': baslangicStok != null
            ? baslangicStok['id']
            : _stoklar.first['id'],
        'miktarCtrl': TextEditingController(text: '1'),
        'fiyatCtrl': TextEditingController(
          text:
              ((baslangicStok != null
                              ? baslangicStok['satis_fiyati']
                              : _stoklar.first['satis_fiyati'])
                          as num? ??
                      100)
                  .toString(),
        ),
        'kdvOrani':
            ((baslangicStok != null
                            ? baslangicStok['kdv_orani']
                            : _stoklar.first['kdv_orani'])
                        as num? ??
                    20.0)
                .toDouble(),
      },
    ];

    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          double araToplam = 0;
          double kdvToplami = 0;
          for (var item in faturaKalemleri) {
            final m = DatabaseService.parsePara(
              (item['miktarCtrl'] as TextEditingController).text,
            ); // 🚨 Virgül korumalı
            final f = DatabaseService.parsePara(
              (item['fiyatCtrl'] as TextEditingController).text,
            ); // 🚨 Virgül korumalı
            final kdv = (item['kdvOrani'] as num).toDouble();
            final tutar = m * f;
            araToplam += tutar;
            kdvToplami += tutar * (kdv / 100);
          }
          final genelToplam = araToplam + kdvToplami;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Yeni Fatura Düzenle",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tip == 'SATIS'
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tip == 'SATIS' ? "SATIŞ FATURASI" : "ALIŞ FATURASI",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tip == 'SATIS'
                          ? const Color(0xFF059669)
                          : const Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 750,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: tip,
                            decoration: const InputDecoration(
                              labelText: "Fatura Tipi",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'SATIS',
                                child: Text("Satış Faturası"),
                              ),
                              DropdownMenuItem(
                                value: 'ALIS',
                                child: Text("Alış Faturası"),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() {
                                  tip = val;
                                  for (var k in faturaKalemleri) {
                                    final st = _stoklar.firstWhere(
                                      (s) => s['id'] == k['stokId'],
                                    );
                                    (k['fiyatCtrl'] as TextEditingController)
                                            .text =
                                        ((tip == 'SATIS'
                                                        ? st['satis_fiyati']
                                                        : st['alis_fiyati'])
                                                    as num? ??
                                                0)
                                            .toString();
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
                            initialValue: seciliCariId,
                            isExpanded: true, // 🚨 TAŞMA ÇÖZÜMÜ
                            decoration: const InputDecoration(
                              labelText: "Cari Hesap",
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: cariler
                                .map(
                                  (c) => DropdownMenuItem<int>(
                                    value: c['id'] as int,
                                    child: Text(
                                      c['unvan']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() {
                                  seciliCariId = val;
                                  final sCari = cariler.firstWhere(
                                    (c) => c['id'] == val,
                                  );
                                  seciliCariUnvan =
                                      sCari['unvan']?.toString() ?? '';
                                  seciliCariVkn =
                                      sCari['vergi_no']?.toString() ??
                                      '11111111111';
                                  if (seciliCariVkn.isEmpty ||
                                      seciliCariVkn == 'Belirtilmedi') {
                                    seciliCariVkn = '11111111111';
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Fatura Kalemleri",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...faturaKalemleri.asMap().entries.map((entry) {
                      final i = entry.key;
                      final k = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<int>(
                                initialValue: k['stokId'] as int,
                                isExpanded: true, // 🚨 TAŞMA ÇÖZÜMÜ
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                                items: _stoklar
                                    .map(
                                      (s) => DropdownMenuItem<int>(
                                        value: s['id'] as int,
                                        child: Text(
                                          s['stok_adi']?.toString() ?? '',
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setModalState(() {
                                      k['stokId'] = val;
                                      final st = _stoklar.firstWhere(
                                        (s) => s['id'] == val,
                                      );
                                      (k['fiyatCtrl'] as TextEditingController)
                                              .text =
                                          ((tip == 'SATIS'
                                                          ? st['satis_fiyati']
                                                          : st['alis_fiyati'])
                                                      as num? ??
                                                  0)
                                              .toString();
                                      k['kdvOrani'] =
                                          (st['kdv_orani'] as num? ?? 20.0)
                                              .toDouble();
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller:
                                    k['miktarCtrl'] as TextEditingController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setModalState(() {}),
                                decoration: const InputDecoration(
                                  labelText: "Miktar",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller:
                                    k['fiyatCtrl'] as TextEditingController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setModalState(() {}),
                                decoration: const InputDecoration(
                                  labelText: "Fiyat (₺)",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (faturaKalemleri.length > 1)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setModalState(
                                    () => faturaKalemleri.removeAt(i),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setModalState(() {
                        final ilkStok = _stoklar.first;
                        faturaKalemleri.add({
                          'stokId': ilkStok['id'],
                          'miktarCtrl': TextEditingController(text: '1'),
                          'fiyatCtrl': TextEditingController(
                            text:
                                ((tip == 'SATIS'
                                                ? ilkStok['satis_fiyati']
                                                : ilkStok['alis_fiyati'])
                                            as num? ??
                                        0)
                                    .toString(),
                          ),
                          'kdvOrani': (ilkStok['kdv_orani'] as num? ?? 20.0)
                              .toDouble(),
                        });
                      }),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        "Yeni Kalem Ekle",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "Ara Toplam: ${fmt.format(araToplam)}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                          Text(
                            "Hesaplanan KDV: ${fmt.format(kdvToplami)}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "GENEL TOPLAM: ${fmt.format(genelToplam)}",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "İptal",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (genelToplam <= 0) {
                    return;
                  }
                  final List<Map<String, dynamic>> islenecekKalemler = [];
                  for (var k in faturaKalemleri) {
                    final m = DatabaseService.parsePara(
                      (k['miktarCtrl'] as TextEditingController).text,
                    );
                    final f = DatabaseService.parsePara(
                      (k['fiyatCtrl'] as TextEditingController).text,
                    );
                    if (m > 0 && f > 0) {
                      islenecekKalemler.add({
                        'stokId': k['stokId'],
                        'miktar': m,
                        'birimFiyat': f,
                        'kdvOrani': k['kdvOrani'],
                      });
                    }
                  }
                  if (islenecekKalemler.isEmpty) {
                    return;
                  }

                  final eFaturaSonuc = await EFaturaService.instance
                      .faturaGonder(
                        aliciUnvan: seciliCariUnvan,
                        aliciVknTckn: seciliCariVkn,
                        faturaTipi: tip,
                        kalemler: islenecekKalemler,
                        matrah: araToplam,
                        kdv: kdvToplami,
                        genelToplam: genelToplam,
                      );
                  await DatabaseService.instance.cokluFaturaIsle(
                    firmaId: firmaId,
                    fisNo: eFaturaSonuc.faturaNo,
                    tarih: DateTime.now().toIso8601String().substring(0, 10),
                    faturaTipi: tip,
                    cariId: seciliCariId,
                    cariUnvan: seciliCariUnvan,
                    kalemler: islenecekKalemler,
                  );

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _verileriYukle();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF059669),
                        content: Text(
                          "✅ Fatura Başarıyla Kesildi! Resmi No: ${eFaturaSonuc.faturaNo} (Test Modu)",
                        ),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
                child: const Text("Faturayı Kes & Resmi Gönder"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _yeniStokKartModal() {
    final kodCtrl = TextEditingController(
      text:
          'STK-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
    );
    final adCtrl = TextEditingController();
    final birimCtrl = TextEditingController(text: 'Adet');
    final kdvCtrl = TextEditingController(text: '20');
    final alisCtrl = TextEditingController(text: '0.00'); // Virgül uyumlu
    final satisCtrl = TextEditingController(text: '0.00'); // Virgül uyumlu
    final kritikCtrl = TextEditingController(text: '10');
    String seciliHesapKodu = '153';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              "Yeni Stok Kartı Tanımla",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: seciliHesapKodu,
                    decoration: const InputDecoration(
                      labelText: "Stok Kart Türü (TDHP)",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '150',
                        child: Text("150 - İlk Madde & Hammadde"),
                      ),
                      DropdownMenuItem(
                        value: '152',
                        child: Text("152 - Üretilen Mamul"),
                      ),
                      DropdownMenuItem(
                        value: '153',
                        child: Text("153 - Ticari Mallar"),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          seciliHesapKodu = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: kodCtrl,
                    decoration: const InputDecoration(
                      labelText: "Stok Kodu",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: adCtrl,
                    decoration: const InputDecoration(
                      labelText: "Ürün / Malzeme Adı",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: birimCtrl,
                          decoration: const InputDecoration(
                            labelText: "Birim (Adet, Kg)",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: kdvCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "KDV %",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: alisCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Alış Fiyatı (₺)",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: satisCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Satış Fiyatı (₺)",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: kritikCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Kritik Seviye Uyarısı",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("İptal"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (adCtrl.text.trim().isEmpty) {
                    return;
                  }
                  await DatabaseService.instance.stokKartiEkle(
                    firmaId: ref.read(firmaProvider).aktifFirmaId,
                    stokKodu: kodCtrl.text.trim(),
                    stokAdi: adCtrl.text.trim(),
                    birim: birimCtrl.text.trim(),
                    kdvOrani: DatabaseService.parsePara(kdvCtrl.text),
                    alisFiyati: DatabaseService.parsePara(
                      alisCtrl.text,
                    ), // 🚨 Virgül korumalı okuma
                    satisFiyati: DatabaseService.parsePara(
                      satisCtrl.text,
                    ), // 🚨 Virgül korumalı okuma
                    kritikSeviye: DatabaseService.parsePara(kritikCtrl.text),
                    hesapKodu: seciliHesapKodu,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _verileriYukle();
                  }
                },
                child: const Text("Kaydet"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double toplamEnvanterDegeri = 0;
    int kritikStokSayisi = 0;
    for (var s in _stoklar) {
      final double miktar = (s['mevcut_miktar'] as num? ?? 0).toDouble();
      final double alis = (s['alis_fiyati'] as num? ?? 0).toDouble();
      final double kritik = (s['kritik_seviye'] as num? ?? 0).toDouble();
      toplamEnvanterDegeri += (miktar * alis);
      if (miktar <= kritik) {
        kritikStokSayisi++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          "📦 Depo & Stok Yönetimi",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _verileriYukle,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildMetrikKarti(
                        "Toplam Stok Çeşidi",
                        "${_stoklar.length} Kalem",
                        const Color(0xFF2563EB),
                        Icons.category_outlined,
                      ),
                      const SizedBox(width: 12),
                      _buildMetrikKarti(
                        "Envanter Değeri",
                        fmt.format(toplamEnvanterDegeri),
                        const Color(0xFF059669),
                        Icons.inventory_2_outlined,
                      ),
                      const SizedBox(width: 12),
                      _buildMetrikKarti(
                        "Kritik Stok Uyarısı",
                        "$kritikStokSayisi Kalem",
                        kritikStokSayisi > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF6B7280),
                        Icons.warning_amber_rounded,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Aktif Depo: ${_depolar.isNotEmpty ? _depolar.first['depo_adi'] : 'Merkez Depo'}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _faturaModalAc(),
                            icon: const Icon(Icons.receipt_long, size: 16),
                            label: const Text(
                              "Fatura Kes",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _yeniStokKartModal,
                            icon: const Icon(Icons.add_box_outlined, size: 18),
                            label: const Text(
                              "Yeni Stok Kartı",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _stoklar.isEmpty
                      ? const Center(
                          child: Text(
                            "Henüz stok kartı eklenmedi.",
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: _stoklar.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final s = _stoklar[index];
                            final double miktar =
                                (s['mevcut_miktar'] as num? ?? 0).toDouble();
                            final double kritik =
                                (s['kritik_seviye'] as num? ?? 0).toDouble();
                            final bool kritikmi = miktar <= kritik;
                            final String hesapKodu =
                                s['hesap_kodu']?.toString() ?? '153';
                            String tipEtiketi = "Ticari Mal (153)";
                            Color tipRenk = Colors.blueGrey;
                            if (hesapKodu == '150') {
                              tipEtiketi = "Hammadde (150)";
                              tipRenk = Colors.orange.shade800;
                            } else if (hesapKodu == '152') {
                              tipEtiketi = "Mamul (152)";
                              tipRenk = Colors.purple.shade700;
                            }

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: kritikmi
                                          ? const Color(0xFFFEF2F2)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.inventory_rounded,
                                      color: kritikmi
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF475569),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              s['stok_adi'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: tipRenk.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: tipRenk.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                tipEtiketi,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: tipRenk,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Kod: ${s['stok_kodu']} • Alış: ${fmt.format(s['alis_fiyati'])} • Satış: ${fmt.format(s['satis_fiyati'])}",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "$miktar ${s['birim']}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: kritikmi
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFF059669),
                                        ),
                                      ),
                                      if (kritikmi)
                                        const Text(
                                          "Kritik Seviye!",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFFDC2626),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    onPressed: () => _hareketModalAc(s),
                                    icon: const Icon(
                                      Icons.sync_alt_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      "Giriş/Çıkış",
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F172A),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                    ),
                                    onPressed: () => _faturaModalAc(s),
                                    icon: const Icon(
                                      Icons.receipt_long_rounded,
                                      size: 15,
                                    ),
                                    label: const Text(
                                      "Fatura Kes",
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetrikKarti(
    String baslik,
    String deger,
    Color renk,
    IconData ikon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: renk.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: renk.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(ikon, color: renk, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    baslik,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    deger,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: renk,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
