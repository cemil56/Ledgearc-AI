import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yevmiye_kaydi.dart';
import '../providers/yevmiye_provider.dart';

class YevmiyeScreen extends ConsumerStatefulWidget {
  const YevmiyeScreen({super.key});

  @override
  ConsumerState<YevmiyeScreen> createState() => _YevmiyeScreenState();
}

class _YevmiyeScreenState extends ConsumerState<YevmiyeScreen> {
  String _secilenKategori = 'TÜMÜ';

  String _kategoriBelirle(List<YevmiyeKaydi> maddeler, String aciklama) {
    final kodlar = maddeler.map((m) => m.hesapKodu).toList();
    final aciklamaUp = aciklama.toUpperCase();

    if (kodlar.any(
          (k) => k == '101' || k == '103' || k == '121' || k == '321',
        ) ||
        aciklamaUp.contains('ÇEK') ||
        aciklamaUp.contains('SENET') ||
        aciklamaUp.contains('EVR-')) {
      return 'ÇEK & SENET';
    }
    if (kodlar.any((k) => k.startsWith('770') || k.startsWith('191')) ||
        aciklamaUp.contains('GİDER') ||
        aciklamaUp.contains('AKARYAKIT') ||
        aciklamaUp.contains('KİRA')) {
      return 'İŞLETME GİDERİ';
    }
    if (kodlar.any((k) => k == '196' || k == '335' || k == '381') ||
        aciklamaUp.contains('PERSONEL') ||
        aciklamaUp.contains('MAAŞ') ||
        aciklamaUp.contains('AVANS')) {
      return 'PERSONEL';
    }
    return 'CARİ & TİCARİ';
  }

  Color _kategoriRengi(String kategori) {
    switch (kategori) {
      case 'ÇEK & SENET':
        return Colors.teal;
      case 'İŞLETME GİDERİ':
        return Colors.orange.shade800;
      case 'PERSONEL':
        return Colors.blue.shade700;
      default:
        return Colors.indigo;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 Clean Architecture: Veriyi artık DatabaseService'den değil, Riverpod State'ten dinliyoruz!
    final yevmiyeState = ref.watch(yevmiyeProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Yevmiye Defteri (TDHP)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.read(yevmiyeProvider.notifier).yenile();
            },
          ),
        ],
      ),
      body: yevmiyeState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Hata: $err')),
        data: (rawList) {
          if (rawList.isEmpty) {
            return const Center(child: Text('Henüz yevmiye kaydı bulunmuyor.'));
          }

          final Map<String, List<YevmiyeKaydi>> fisGruplari = {};
          for (var item in rawList) {
            final fisNo = item.fisNo.isNotEmpty ? item.fisNo : 'DİĞER';
            fisGruplari.putIfAbsent(fisNo, () => []).add(item);
          }

          int cekSayisi = 0;
          int giderSayisi = 0;
          int personelSayisi = 0;
          int cariSayisi = 0;

          final Map<String, String> fisKategoriMap = {};
          fisGruplari.forEach((fisNo, maddeler) {
            final aciklama = maddeler.first.aciklama;
            final kat = _kategoriBelirle(maddeler, aciklama);
            fisKategoriMap[fisNo] = kat;

            if (kat == 'ÇEK & SENET') {
              cekSayisi++;
            } else if (kat == 'İŞLETME GİDERİ')
              giderSayisi++;
            else if (kat == 'PERSONEL')
              personelSayisi++;
            else
              cariSayisi++;
          });

          final filtrelenmisFisler = fisGruplari.keys.where((fisNo) {
            if (_secilenKategori == 'TÜMÜ') return true;
            return fisKategoriMap[fisNo] == _secilenKategori;
          }).toList();

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildOzetKutu(
                        baslik: 'Tüm Kayıtlar',
                        adet: fisGruplari.length,
                        seciliMi: _secilenKategori == 'TÜMÜ',
                        renk: Colors.blueGrey,
                        onTap: () => setState(() => _secilenKategori = 'TÜMÜ'),
                      ),
                      const SizedBox(width: 8),
                      _buildOzetKutu(
                        baslik: 'Çek & Senet',
                        adet: cekSayisi,
                        seciliMi: _secilenKategori == 'ÇEK & SENET',
                        renk: Colors.teal,
                        onTap: () =>
                            setState(() => _secilenKategori = 'ÇEK & SENET'),
                      ),
                      const SizedBox(width: 8),
                      _buildOzetKutu(
                        baslik: 'İşletme Gideri',
                        adet: giderSayisi,
                        seciliMi: _secilenKategori == 'İŞLETME GİDERİ',
                        renk: Colors.orange.shade800,
                        onTap: () =>
                            setState(() => _secilenKategori = 'İŞLETME GİDERİ'),
                      ),
                      const SizedBox(width: 8),
                      _buildOzetKutu(
                        baslik: 'Personel',
                        adet: personelSayisi,
                        seciliMi: _secilenKategori == 'PERSONEL',
                        renk: Colors.blue.shade700,
                        onTap: () =>
                            setState(() => _secilenKategori = 'PERSONEL'),
                      ),
                      const SizedBox(width: 8),
                      _buildOzetKutu(
                        baslik: 'Cari & Fatura',
                        adet: cariSayisi,
                        seciliMi: _secilenKategori == 'CARİ & TİCARİ',
                        renk: Colors.indigo,
                        onTap: () =>
                            setState(() => _secilenKategori = 'CARİ & TİCARİ'),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
              Expanded(
                child: filtrelenmisFisler.isEmpty
                    ? Center(
                        child: Text(
                          '$_secilenKategori kategorisinde kayıt bulunamadı.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtrelenmisFisler.length,
                        itemBuilder: (context, index) {
                          final fisNo = filtrelenmisFisler[index];
                          final maddeler = fisGruplari[fisNo]!;
                          final ilk = maddeler.first;
                          final kategori = fisKategoriMap[fisNo]!;
                          final katRenk = _kategoriRengi(kategori);

                          double toplamBorc = 0;
                          double toplamAlacak = 0;
                          for (var m in maddeler) {
                            toplamBorc += m.borc; // Modelden TL olarak geldiği için doğrudan topluyoruz
                            toplamAlacak += m.alacak;
                          }

                          return Card(
                            elevation: 0,
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: katRenk.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: katRenk.withValues(
                                                  alpha: 0.3,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              kategori,
                                              style: TextStyle(
                                                color: katRenk,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Fiş: $fisNo',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        ilk.tarih.split('T').first,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    ilk.aciklama,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      children: [
                                        SizedBox(
                                          width: 50,
                                          child: Text(
                                            'KOD',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'HESAP ADI',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 85,
                                          child: Text(
                                            'BORÇ',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 85,
                                          child: Text(
                                            'ALACAK',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...maddeler.map((m) {
                                    final b = m.borc;
                                    final a = m.alacak;
                                    final kod = m.hesapKodu;
                                    String hesapAdi = m.hesapAdi;

                                    if (hesapAdi.isEmpty ||
                                        hesapAdi == 'null') {
                                      const hesapSozlugu = {
                                        '100': 'Kasa Hesabı',
                                        '101': 'Alınan Çekler',
                                        '102': 'Banka Hesabı',
                                        '103': 'Verilen Çekler (-)',
                                        '108': 'Kredi Kartı/POS',
                                        '120': 'Alıcılar',
                                        '121': 'Alacak Senetleri',
                                        '191': 'İndirilecek KDV',
                                        '196': 'Personel Avans',
                                        '320': 'Satıcılar',
                                        '321': 'Borç Senetleri',
                                        '335': 'Personele Borçlar',
                                        '770': 'Genel Gider',
                                      };
                                      hesapAdi =
                                          hesapSozlugu[kod] ?? 'Muhtelif Hesap';
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 50,
                                            child: Text(
                                              kod,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              hesapAdi,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF334155),
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 85,
                                            child: Text(
                                              b > 0
                                                  ? '₺${b.toStringAsFixed(2)}'
                                                  : '-',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 85,
                                            child: Text(
                                              a > 0
                                                  ? '₺${a.toStringAsFixed(2)}'
                                                  : '-',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'TOPLAM: ₺${toplamBorc.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        '₺${toplamAlacak.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOzetKutu({
    required String baslik,
    required int adet,
    required bool seciliMi,
    required Color renk,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: seciliMi ? renk.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seciliMi ? renk : Colors.grey.shade300,
            width: seciliMi ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              baslik,
              style: TextStyle(
                fontSize: 12,
                fontWeight: seciliMi ? FontWeight.bold : FontWeight.w500,
                color: seciliMi ? renk : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$adet Fiş',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: seciliMi ? renk : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
