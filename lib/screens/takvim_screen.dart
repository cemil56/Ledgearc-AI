import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/firma_provider.dart';
import '../services/database_service.dart';
import '../providers/ledger_provider.dart';

class TakvimScreen extends ConsumerStatefulWidget {
  const TakvimScreen({super.key});

  @override
  ConsumerState<TakvimScreen> createState() => _TakvimScreenState();
}

class _TakvimScreenState extends ConsumerState<TakvimScreen> {
  final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  List<Map<String, dynamic>> _tumKayitlar = [];
  bool _isLoading = true;
  String _filtre = 'HEPSİ';

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    setState(() => _isLoading = true);
    try {
      final firmaId = ref.read(firmaProvider).aktifFirmaId;
      final data = await DatabaseService.instance.getOdemeTakvimi(
        firmaId: firmaId,
      );
      if (mounted) {
        setState(() {
          _tumKayitlar = data;
        });
      }
    } catch (e) {
      debugPrint("Takvim yükleme hatası: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _durumGuncelleModalAc({
    required Map<String, dynamic> item,
    required bool isTahsilat,
  }) async {
    final firmaId = ref.read(firmaProvider).aktifFirmaId;
    final cekId = item['cek_id'] as int? ?? item['id'] as int? ?? 0;
    final cariUnvan = item['cari_unvan']?.toString() ?? 'Cari';
    final tutar = isTahsilat
        ? (item['borc'] as num? ?? 0).toDouble()
        : (item['alacak'] as num? ?? 0).toDouble();

    // Ciro edilecek cari listesini önceden çek
    List<Map<String, dynamic>> cariListesi = [];
    if (isTahsilat) {
      cariListesi = await DatabaseService.instance.ciroIcinCarileriGetir(
        firmaId: firmaId,
      );
    }

    String secilenIslemTuru =
        'NORMAL'; // 'NORMAL', 'KIRDIR', 'CIRO', 'KARSILIKSIZ'
    String secilenYer = 'BANKA';
    int? secilenCariId = cariListesi.isNotEmpty
        ? cariListesi.first['id'] as int?
        : null;
    String? secilenCariUnvan = cariListesi.isNotEmpty
        ? cariListesi.first['unvan']?.toString()
        : null;

    final bankaController = TextEditingController(
      text: item['banka_adi']?.toString() ?? '',
    );
    final komisyonController = TextEditingController(text: '0');

    if (!mounted) return;

    final sonuc = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final komisyon = DatabaseService.parsePara(komisyonController.text);
          final netTutar = tutar - komisyon;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              isTahsilat
                  ? 'Çek / Senet Tahsilat & Kapanış'
                  : 'Çek / Senet Ödemesi',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$cariUnvan firmasına ait ${fmt.format(tutar)} tutarındaki evrak işlem görecek.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // İşlem Tipi Seçimi (Tahsilat ve Ödemeye Göre Dinamik)
                  const Text(
                    'İşlem Tipi:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: isTahsilat
                          ? [
                              ChoiceChip(
                                label: const Text('Normal Tahsil'),
                                selected: secilenIslemTuru == 'NORMAL',
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(
                                      () => secilenIslemTuru = 'NORMAL',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Kırdır (İskonto)'),
                                selected: secilenIslemTuru == 'KIRDIR',
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(
                                      () => secilenIslemTuru = 'KIRDIR',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Ciro Et (Devret)'),
                                selected: secilenIslemTuru == 'CIRO',
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(
                                      () => secilenIslemTuru = 'CIRO',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Karşılıksız / Protesto'),
                                selected: secilenIslemTuru == 'KARSILIKSIZ',
                                selectedColor: const Color(0xFFFEE2E2),
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(
                                      () => secilenIslemTuru = 'KARSILIKSIZ',
                                    );
                                  }
                                },
                              ),
                            ]
                          : [
                              ChoiceChip(
                                label: const Text('Normal Ödeme'),
                                selected: secilenIslemTuru == 'NORMAL',
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(
                                      () => secilenIslemTuru = 'NORMAL',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Ödenemedi / Karşılıksız'),
                                selected: secilenIslemTuru == 'KARSILIKSIZ',
                                selectedColor: const Color(0xFFFEE2E2),
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(
                                      () => secilenIslemTuru = 'KARSILIKSIZ',
                                    );
                                  }
                                },
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 1. Kırdırma Seçildiyse: Komisyon ve Net Giriş Kutuları
                  if (secilenIslemTuru == 'KIRDIR') ...[
                    TextField(
                      controller: komisyonController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Kesinti / Komisyon Tutarı (780)',
                        prefixText: '₺ ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Hesaba Geçecek Net:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            fmt.format(netTutar < 0 ? 0.0 : netTutar),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // 2. Ciro Seçildiyse: Hedef Cari Seçimi (320 Satıcı)
                  if (secilenIslemTuru == 'CIRO') ...[
                    const Text(
                      'Ciro Edilecek Cari (Satıcı/Tedarikçi):',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (cariListesi.isEmpty)
                      const Text(
                        'Kayıtlı cari bulunamadı.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      )
                    else
                      DropdownButtonFormField<int>(
                        initialValue: secilenCariId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: cariListesi.map((c) {
                          return DropdownMenuItem<int>(
                            value: c['id'] as int,
                            child: Text(
                              "${c['unvan']}",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              secilenCariId = val;
                              final secilen = cariListesi.firstWhere(
                                (e) => e['id'] == val,
                              );
                              secilenCariUnvan = secilen['unvan']?.toString();
                            });
                          }
                        },
                      ),
                    const SizedBox(height: 14),
                  ],

                  // 3. Kasa/Banka Seçimi (Ciro veya Karşılıksız değilse gösterilir)
                  if (secilenIslemTuru != 'CIRO' &&
                      secilenIslemTuru != 'KARSILIKSIZ') ...[
                    const Text(
                      'Tahsilat / Ödeme Kanalı:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Banka Hesabı')),
                            selected: secilenYer == 'BANKA',
                            onSelected: (val) {
                              if (val) {
                                setModalState(() => secilenYer = 'BANKA');
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Kasa (Nakit)')),
                            selected: secilenYer == 'KASA',
                            onSelected: (val) {
                              if (val) {
                                setModalState(() => secilenYer = 'KASA');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    if (secilenYer == 'BANKA') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: bankaController,
                        decoration: InputDecoration(
                          labelText: secilenIslemTuru == 'KIRDIR'
                              ? 'Banka / Faktoring Adı'
                              : 'Banka Adı / Şube',
                          hintText: secilenIslemTuru == 'KIRDIR'
                              ? 'Örn: Garanti Faktoring'
                              : 'Örn: Garanti BBVA',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Vazgeç',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTahsilat
                      ? const Color(0xFF059669)
                      : const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (secilenIslemTuru == 'CIRO' && secilenCariId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Lütfen ciro edilecek cariyi seçin.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(
                  secilenIslemTuru == 'KARSILIKSIZ'
                      ? (isTahsilat
                            ? 'Karşılıksız Olarak İşle'
                            : 'Ödenemedi Olarak Kaydet')
                      : secilenIslemTuru == 'CIRO'
                      ? 'Ciro Kaydını Tamamla'
                      : secilenIslemTuru == 'KIRDIR'
                      ? 'Kırdırma Kaydet'
                      : (isTahsilat ? 'Tahsil Et' : 'Ödemeyi Tamamla'),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (sonuc == true) {
      if (secilenIslemTuru == 'KARSILIKSIZ') {
        if (isTahsilat) {
          await DatabaseService.instance.cekSenetKarsiliksizYap(
            firmaId: firmaId,
            cekId: cekId,
          );
        } else {
          await DatabaseService.instance.kendiCekSenetOdenemedi(
            firmaId: firmaId,
            cekId: cekId,
          );
        }
      } else if (secilenIslemTuru == 'CIRO') {
        await DatabaseService.instance.cekSenetCiroEt(
          firmaId: firmaId,
          cekId: cekId,
          hedefCariId: secilenCariId!,
          hedefCariUnvan: secilenCariUnvan ?? 'Cari',
        );
      } else if (secilenIslemTuru == 'KIRDIR') {
        final komisyon = DatabaseService.parsePara(komisyonController.text);
        await DatabaseService.instance.cekSenetKirdir(
          firmaId: firmaId,
          cekId: cekId,
          komisyonTutari: komisyon,
          odemeYeri: secilenYer,
          kurumAdi: secilenYer == 'BANKA' ? bankaController.text.trim() : null,
        );
      } else {
        await DatabaseService.instance.cekSenetDurumGuncelle(
          firmaId: firmaId,
          cekId: cekId,
          yeniDurum: isTahsilat ? 'TAHSIL_EDILDI' : 'ODENDI',
          odemeYeri: secilenYer,
          bankaAdi: secilenYer == 'BANKA' ? bankaController.text.trim() : null,
        );
      }

      ref.read(ledgerProvider.notifier).yenile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              secilenIslemTuru == 'KARSILIKSIZ'
                  ? (isTahsilat
                        ? 'Evrak karşılıksız/protestolu olarak işaretlendi ve cariye devredildi.'
                        : 'Kendi evrakımızın ödenemediği kaydedildi ve satıcı borcu tekrar açıldı.')
                  : secilenIslemTuru == 'CIRO'
                  ? 'Evrak başarıyla ciro edildi (320 Satıcı borcu düşüldü).'
                  : secilenIslemTuru == 'KIRDIR'
                  ? 'Faktoring / İskonto virman fişi oluşturuldu.'
                  : (isTahsilat
                        ? 'Tahsilat virman kaydı oluşturuldu.'
                        : 'Ödeme virman kaydı oluşturuldu.'),
            ),
            backgroundColor: const Color(0xFF0F172A),
          ),
        );
        _verileriYukle();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bugunStr = DateTime.now().toIso8601String().substring(0, 10);

    final filtrelenmis = _tumKayitlar.where((k) {
      final isTahsilat = (k['borc'] as num? ?? 0) > 0;
      if (_filtre == 'TAHSİLAT') return isTahsilat;
      if (_filtre == 'ÖDEME') return !isTahsilat;
      return true;
    }).toList();

    double toplamGelecekTahsilat = 0;
    double toplamGelecekOdeme = 0;

    for (var k in _tumKayitlar) {
      final borc = (k['borc'] as num? ?? 0).toDouble();
      final alacak = (k['alacak'] as num? ?? 0).toDouble();
      toplamGelecekTahsilat += borc;
      toplamGelecekOdeme += alacak;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          "📅 Vade & Ödeme Takvimi",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Yenile",
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
                      _buildOzetKarti(
                        baslik: "Beklenen Tahsilat",
                        tutar: toplamGelecekTahsilat,
                        renk: const Color(0xFF059669),
                        ikon: Icons.arrow_downward_rounded,
                      ),
                      const SizedBox(width: 12),
                      _buildOzetKarti(
                        baslik: "Yapılacak Ödeme",
                        tutar: toplamGelecekOdeme,
                        renk: const Color(0xFFDC2626),
                        ikon: Icons.arrow_upward_rounded,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _buildFilterChip("Tümü", 'HEPSİ'),
                      const SizedBox(width: 8),
                      _buildFilterChip("Gelecek Tahsilatlar", 'TAHSİLAT'),
                      const SizedBox(width: 8),
                      _buildFilterChip("Yapılacak Ödemeler", 'ÖDEME'),
                    ],
                  ),
                ),
                Expanded(
                  child: filtrelenmis.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _filtre == 'ÖDEME'
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.event_available_rounded,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _filtre == 'ÖDEME'
                                    ? 'Yaklaşan Borç / Ödeme Evrakı Bulunmuyor'
                                    : _filtre == 'TAHSİLAT'
                                    ? 'Bekleyen Tahsilat Evrakı Bulunmuyor'
                                    : 'Vadesi yaklaşan herhangi bir kayıt bulunamadı.',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _filtre == 'ÖDEME'
                                    ? 'Tüm borç çekleri ve senetleri kapatılmış veya henüz girilmemiş.'
                                    : 'Portföydeki evraklar güncel.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: filtrelenmis.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = filtrelenmis[index];
                            final vadeTarihi =
                                item['vade_tarihi']?.toString() ?? '';
                            final isTahsilat = (item['borc'] as num? ?? 0) > 0;
                            final tutar = isTahsilat
                                ? (item['borc'] as num? ?? 0).toDouble()
                                : (item['alacak'] as num? ?? 0).toDouble();

                            final isGecmis = vadeTarihi.compareTo(bugunStr) < 0;
                            final isBugun = vadeTarihi == bugunStr;

                            Color durumRengi;
                            String durumMetni;
                            if (isGecmis) {
                              durumRengi = const Color(0xFFDC2626);
                              durumMetni = "VADESİ GEÇTİ";
                            } else if (isBugun) {
                              durumRengi = const Color(0xFFD97706);
                              durumMetni = "BUGÜN VADESİ";
                            } else {
                              durumRengi = const Color(0xFF2563EB);
                              durumMetni = "YAKLAŞIYOR";
                            }

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isGecmis
                                      ? const Color(0xFFFECACA)
                                      : const Color(0xFFE5E7EB),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isTahsilat
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFFEF2F2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isTahsilat
                                          ? Icons.call_received_rounded
                                          : Icons.call_made_rounded,
                                      color: isTahsilat
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
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
                                            Expanded(
                                              child: Text(
                                                item['cari_unvan'] ??
                                                    'Belirtilmemiş Cari',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: durumRengi.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                durumMetni,
                                                style: TextStyle(
                                                  color: durumRengi,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${item['odeme_yontemi'] ?? 'AÇIK_HESAP'} • Vade: $vadeTarihi",
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        fmt.format(tutar),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isTahsilat
                                              ? const Color(0xFF059669)
                                              : const Color(0xFFDC2626),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: () => _durumGuncelleModalAc(
                                          item: item,
                                          isTahsilat: isTahsilat,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isTahsilat
                                                ? const Color(0xFF059669)
                                                : const Color(0xFFDC2626),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            isTahsilat ? 'Tahsil Et' : 'Öde',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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

  Widget _buildOzetKarti({
    required String baslik,
    required double tutar,
    required Color renk,
    required IconData ikon,
  }) {
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
                    fmt.format(tutar),
                    style: TextStyle(
                      fontSize: 15,
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

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filtre == value;
    return InkWell(
      onTap: () => setState(() => _filtre = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF111827)
                : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
