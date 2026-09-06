import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/firma_provider.dart';
import '../providers/ledger_provider.dart';
import '../services/database_service.dart';

class KasaScreen extends ConsumerStatefulWidget {
  const KasaScreen({super.key});

  @override
  ConsumerState<KasaScreen> createState() => _KasaScreenState();
}

class _KasaScreenState extends ConsumerState<KasaScreen> {
  final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  bool _isLoading = true;
  String _aktifSekme = '100'; // '100' -> Nakit Kasa, '102' -> Bankalar

  Map<String, double> _ozet = {'kasa': 0.0, 'banka': 0.0, 'toplam': 0.0};
  List<Map<String, dynamic>> _hareketler = [];

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    setState(() => _isLoading = true);
    try {
      final firmaId = ref.read(firmaProvider).aktifFirmaId;
      final ozetData = await DatabaseService.instance.getKasaBankaOzet(
        firmaId: firmaId,
      );
      final hareketData = await DatabaseService.instance
          .getKasaBankaHareketleri(firmaId: firmaId, hesapKodu: _aktifSekme);

      if (mounted) {
        setState(() {
          _ozet = ozetData;
          _hareketler = hareketData;
        });
      }
    } catch (e) {
      debugPrint("Kasa & Banka yükleme hatası: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _virmanModalAc() {
    final tutarController = TextEditingController();
    final aciklamaController = TextEditingController();
    final bankaController = TextEditingController(text: 'Garanti BBVA');
    String kaynak =
        'KASA'; // 'KASA' -> Kasa'dan Bankaya, 'BANKA' -> Banka'dan Kasaya

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              "Nakit Virman & Transfer",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Transfer Yönü:",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("Kasa ➔ Banka")),
                          selected: kaynak == 'KASA',
                          onSelected: (val) {
                            if (val) setModalState(() => kaynak = 'KASA');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text("Banka ➔ Kasa")),
                          selected: kaynak == 'BANKA',
                          onSelected: (val) {
                            if (val) setModalState(() => kaynak = 'BANKA');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: tutarController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Transfer Tutarı",
                      prefixText: "₺ ",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankaController,
                    decoration: const InputDecoration(
                      labelText: "İlgili Banka Adı",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aciklamaController,
                    decoration: const InputDecoration(
                      labelText: "Açıklama (Opsiyonel)",
                      hintText: "Örn: Gün sonu hasılat yatırma",
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
                  "Vazgeç",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final tutar = DatabaseService.parsePara(tutarController.text);

                  final firmaId = ref.read(firmaProvider).aktifFirmaId;
                  await DatabaseService.instance.kasaBankaVirmanYap(
                    firmaId: firmaId,
                    tutar: tutar,
                    kaynak: kaynak,
                    bankaAdi: bankaController.text.trim(),
                    aciklama: aciklamaController.text.trim(),
                  );

                  ref.read(ledgerProvider.notifier).yenile();
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);

                  if (!mounted) return;
                  _verileriYukle();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Virman kaydı yevmiyeye işlendi."),
                      backgroundColor: Color(0xFF0F172A),
                    ),
                  );
                },
                child: const Text("Virmanı Tamamla"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          "🏦 Kasa & Banka Yönetimi",
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
                // 1. Özet Varlık Kartları
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildOzetKarti(
                        baslik: "Nakit Kasa (100)",
                        tutar: _ozet['kasa'] ?? 0.0,
                        renk: const Color(0xFF059669),
                        ikon: Icons.payments_outlined,
                      ),
                      const SizedBox(width: 12),
                      _buildOzetKarti(
                        baslik: "Bankalar (102)",
                        tutar: _ozet['banka'] ?? 0.0,
                        renk: const Color(0xFF2563EB),
                        ikon: Icons.account_balance_outlined,
                      ),
                      const SizedBox(width: 12),
                      _buildOzetKarti(
                        baslik: "Toplam Likidite",
                        tutar: _ozet['toplam'] ?? 0.0,
                        renk: const Color(0xFF0F172A),
                        ikon: Icons.savings_outlined,
                      ),
                    ],
                  ),
                ),

                // 2. Sekme Seçimi & Virman Butonu
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          _buildTabChip("100 Nakit Kasa", '100'),
                          const SizedBox(width: 8),
                          _buildTabChip("102 Banka Hesapları", '102'),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _virmanModalAc,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text(
                          "Para Transferi / Virman",
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Hesap Hareket Dökümü
                Expanded(
                  child: _hareketler.isEmpty
                      ? Center(
                          child: Text(
                            "${_aktifSekme == '100' ? 'Kasa' : 'Banka'} hesabına ait hareket bulunamadı.",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          itemCount: _hareketler.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final row = _hareketler[index];
                            final borc = (row['borc'] as num? ?? 0).toDouble();
                            final alacak = (row['alacak'] as num? ?? 0)
                                .toDouble();
                            final isGiris = borc > 0;
                            final tutar = isGiris ? borc : alacak;

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
                                      color: isGiris
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFFEF2F2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isGiris
                                          ? Icons.arrow_downward_rounded
                                          : Icons.arrow_upward_rounded,
                                      color: isGiris
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row['aciklama'] ?? 'Hareket Kaydı',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${row['tarih']} • Fiş: ${row['fis_no']}",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    "${isGiris ? '+' : '-'} ${fmt.format(tutar)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: isGiris
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
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

  Widget _buildTabChip(String label, String kod) {
    final isSelected = _aktifSekme == kod;
    return InkWell(
      onTap: () {
        setState(() => _aktifSekme = kod);
        _verileriYukle();
      },
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
