import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/firma_provider.dart';
import '../services/database_service.dart';

class MizanScreen extends ConsumerStatefulWidget {
  const MizanScreen({super.key});

  @override
  ConsumerState<MizanScreen> createState() => _MizanScreenState();
}

class _MizanScreenState extends ConsumerState<MizanScreen> {
  final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  List<Map<String, dynamic>> _mizanVerileri = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _mizanYukle();
  }

  Future<void> _mizanYukle() async {
    setState(() => _isLoading = true);
    try {
      final firmaId = ref.read(firmaProvider).aktifFirmaId;
      final data = await DatabaseService.instance.getMizanListesi(
        firmaId: firmaId,
      );
      if (mounted) {
        setState(() {
          _mizanVerileri = data;
        });
      }
    } catch (e) {
      debugPrint("Mizan yükleme hatası: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double genelBorc = 0;
    double genelAlacak = 0;
    double genelBorcBakiye = 0;
    double genelAlacakBakiye = 0;

    for (var m in _mizanVerileri) {
      genelBorc += (m['toplam_borc'] as num? ?? 0).toDouble();
      genelAlacak += (m['toplam_alacak'] as num? ?? 0).toDouble();
      genelBorcBakiye += (m['borc_bakiye'] as num? ?? 0).toDouble();
      genelAlacakBakiye += (m['alacak_bakiye'] as num? ?? 0).toDouble();
    }

    final bool mizanDengede =
        (genelBorc - genelAlacak).abs() < 0.01 &&
        (genelBorcBakiye - genelAlacakBakiye).abs() < 0.01;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          "⚖️ Genel Geçici Mizan (TDHP)",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Yenile",
            onPressed: _mizanYukle,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Mizan Durum Özeti (Denklik Kartı)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            mizanDengede
                                ? Icons.check_circle_rounded
                                : Icons.warning_rounded,
                            color: mizanDengede
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            mizanDengede
                                ? "Mizan Dengede (Borç = Alacak)"
                                : "Mizan Dengesiz!",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: mizanDengede
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "Toplam ${_mizanVerileri.length} Ana Hesap",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // 2. Tablo Başlıkları
                Container(
                  color: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 65,
                        child: Text(
                          "Kod",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          "Hesap Adı",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Borç Tutarı",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Alacak Tutarı",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Borç Bakiye",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          "Alacak Bakiye",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Hesap Satırları
                Expanded(
                  child: _mizanVerileri.isEmpty
                      ? const Center(
                          child: Text(
                            "Mizanda gösterilecek yevmiye kaydı bulunamadı.",
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _mizanVerileri.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (context, index) {
                            final h = _mizanVerileri[index];
                            final double bBakiye = h['borc_bakiye'];
                            final double aBakiye = h['alacak_bakiye'];

                            return Container(
                              color: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 65,
                                    child: Text(
                                      h['hesap_kodu'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      h['hesap_adi'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF334155),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      fmt.format(h['toplam_borc']),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      fmt.format(h['toplam_alacak']),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      bBakiye > 0 ? fmt.format(bBakiye) : '-',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      aBakiye > 0 ? fmt.format(aBakiye) : '-',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // 4. Genel Toplam Çubuğu
                Container(
                  color: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 4,
                        child: Text(
                          "GENEL TOPLAM",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          fmt.format(genelBorc),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          fmt.format(genelAlacak),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          fmt.format(genelBorcBakiye),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          fmt.format(genelAlacakBakiye),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFFF87171),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
