import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/firma_provider.dart';
import '../services/database_service.dart';

class MaliTablolarScreen extends ConsumerStatefulWidget {
  const MaliTablolarScreen({super.key});

  @override
  ConsumerState<MaliTablolarScreen> createState() => _MaliTablolarScreenState();
}

class _MaliTablolarScreenState extends ConsumerState<MaliTablolarScreen> {
  final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  bool _isLoading = true;
  int _seciliSekme = 0; // 0: Gelir Tablosu, 1: Bilanço
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _isLoading = true);
    try {
      final firmaId = ref.read(firmaProvider).aktifFirmaId;
      final res = await DatabaseService.instance.getMaliTablolar(
        firmaId: firmaId,
      );
      if (mounted) setState(() => _data = res);
    } catch (e) {
      debugPrint("Mali tablolar hatası: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          "📊 Mali Tablolar (Gelir Tablosu & Bilanço)",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _yukle),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text("📈 Gelir Tablosu"),
                        selected: _seciliSekme == 0,
                        onSelected: (val) => setState(() => _seciliSekme = 0),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("🏛️ Bilanço (Aktif / Pasif)"),
                        selected: _seciliSekme == 1,
                        onSelected: (val) => setState(() => _seciliSekme = 1),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _seciliSekme == 0
                      ? _buildGelirTablosu()
                      : _buildBilanco(),
                ),
              ],
            ),
    );
  }

  Widget _buildGelirTablosu() {
    final double gelirler = _data['gelirler'] ?? 0.0;
    final double giderler = _data['giderler'] ?? 0.0;
    final double netKar = _data['net_kar_zarar'] ?? 0.0;
    final bool karVar = netKar >= 0;

    final List gelirList = _data['gelir_hesaplari'] ?? [];
    final List giderList = _data['gider_hesaplari'] ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: karVar ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: karVar ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    karVar ? "DÖNEM NET KÂRI" : "DÖNEM NET ZARARI",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: karVar
                          ? const Color(0xFF065F46)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fmt.format(netKar.abs()),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: karVar
                          ? const Color(0xFF047857)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              Icon(
                karVar
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: karVar
                    ? const Color(0xFF047857)
                    : const Color(0xFFDC2626),
                size: 36,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildGrupBaslik(
          "6xx Gelirler Toplamı: ${fmt.format(gelirler)}",
          const Color(0xFF059669),
        ),
        ...gelirList.map(
          (h) => _buildKalemSatiri(
            h['kod'],
            h['ad'],
            h['tutar'],
            const Color(0xFF059669),
          ),
        ),
        const SizedBox(height: 16),
        _buildGrupBaslik(
          "7xx Giderler Toplamı: ${fmt.format(giderler)}",
          const Color(0xFFDC2626),
        ),
        ...giderList.map(
          (h) => _buildKalemSatiri(
            h['kod'],
            h['ad'],
            h['tutar'],
            const Color(0xFFDC2626),
          ),
        ),
      ],
    );
  }

  Widget _buildBilanco() {
    final double aktif = _data['toplam_aktif'] ?? 0.0;
    final double pasif = _data['toplam_pasif'] ?? 0.0;
    final List aktifList = _data['aktif_hesaplar'] ?? [];
    final List pasifList = _data['pasif_hesaplar'] ?? [];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGrupBaslik(
                "AKTİF (VARLIKLAR): ${fmt.format(aktif)}",
                const Color(0xFF1E293B),
              ),
              const SizedBox(height: 8),
              ...aktifList.map(
                (h) => _buildKalemSatiri(
                  h['kod'],
                  h['ad'],
                  h['tutar'],
                  const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGrupBaslik(
                "PASİF (KAYNAKLAR): ${fmt.format(pasif)}",
                const Color(0xFF1E293B),
              ),
              const SizedBox(height: 8),
              ...pasifList.map(
                (h) => _buildKalemSatiri(
                  h['kod'],
                  h['ad'],
                  h['tutar'],
                  const Color(0xFFD97706),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrupBaslik(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: color,
        ),
      ),
    );
  }

  Widget _buildKalemSatiri(String kod, String ad, double tutar, Color renk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              "$kod - $ad",
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            fmt.format(tutar),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: renk,
            ),
          ),
        ],
      ),
    );
  }
}
