// lib/screens/main_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/firma_provider.dart';
import 'cariler_screen.dart';
import 'chat_screen.dart';
import 'depo_stok_screen.dart';
import 'kasa_screen.dart';
import 'mali_tablolar_screen.dart';
import 'mizan_screen.dart';
import 'takvim_screen.dart';
import 'yevmiye_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _seciliSekme = 0;

  final List<Widget> _sayfalar = const [
    ChatScreen(),
    CarilerScreen(),
    TakvimScreen(),
    YevmiyeScreen(),
    MizanScreen(),
    KasaScreen(),
    MaliTablolarScreen(),
    DepoStokScreen(),
  ];

  void _firmaAyarModaliAc() {
    final firmaState = ref.read(firmaProvider);

    final unvanCtrl = TextEditingController(text: firmaState.aktifFirmaUnvan);
    final vknCtrl = TextEditingController(text: firmaState.vkn);
    final vergiDairesiCtrl = TextEditingController(
      text: firmaState.vergiDairesi,
    );
    final kullaniciAdiCtrl = TextEditingController(
      text: firmaState.apiKullanici,
    );
    final sifreCtrl = TextEditingController(text: firmaState.apiSifre);

    String seciliEntegrator = firmaState.entegrator;
    bool eFaturaAktif = firmaState.eFaturaAktif;
    bool eArsivAktif = firmaState.eArsivAktif;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Container(
              width: 620,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.business_outlined,
                            color: Color(0xFF111827),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Firma & E-Dönüşüm Ayarları",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Text(
                                "Şirket profili ve resmi entegratör konfigürasyonu",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 16),

                    const Text(
                      "ŞİRKET BİLGİLERİ",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B5563),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildInput(
                      controller: unvanCtrl,
                      label: "Resmi Şirket Unvanı",
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInput(
                            controller: vknCtrl,
                            label: "Vergi Kimlik No / TCKN",
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildInput(
                            controller: vergiDairesiCtrl,
                            label: "Vergi Dairesi",
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      "E-FATURA / E-ARŞİV ENTEGRATÖRÜ",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B5563),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: seciliEntegrator,
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF111827),
                      ),
                      decoration: _inputDecoration("Entegratör Servisi"),
                      items: const [
                        DropdownMenuItem(
                          value: "GİB Test Portalı (Simülasyon)",
                          child: Text("GİB Test Portalı (Yerel Simülasyon)"),
                        ),
                        DropdownMenuItem(
                          value: "Sovos / Foriba API",
                          child: Text("Sovos / Foriba E-Fatura API"),
                        ),
                        DropdownMenuItem(
                          value: "KolayBi Entegrasyon",
                          child: Text("KolayBi Cloud API"),
                        ),
                        DropdownMenuItem(
                          value: "Uyumsoft Bilgi Sistemleri",
                          child: Text("Uyumsoft Web Servisleri"),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => seciliEntegrator = val);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInput(
                            controller: kullaniciAdiCtrl,
                            label: "Kullanıcı Adı / API Key",
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildInput(
                            controller: sifreCtrl,
                            label: "Şifre / Secret Key",
                            obscure: true,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "e-Fatura Mükellefi",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  Text(
                                    "Gelen faturalar otomatik taranır",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: eFaturaAktif,
                                activeThumbColor: const Color(0xFF111111),
                                onChanged: (val) =>
                                    setModalState(() => eFaturaAktif = val),
                              ),
                            ],
                          ),
                          const Divider(height: 1, color: Color(0xFFE5E7EB)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "e-Arşiv Portal Modu",
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  Text(
                                    "5.000 TL üzeri belgeleri arşivler",
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                              Switch(
                                value: eArsivAktif,
                                activeThumbColor: const Color(0xFF111111),
                                onChanged: (val) =>
                                    setModalState(() => eArsivAktif = val),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("Vazgeç"),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF111111),
                          ),
                          onPressed: () {
                            ref
                                .read(firmaProvider.notifier)
                                .firmaGuncelle(
                                  unvan: unvanCtrl.text.trim(),
                                  vkn: vknCtrl.text.trim(),
                                  vergiDairesi: vergiDairesiCtrl.text.trim(),
                                  entegrator: seciliEntegrator,
                                  apiKullanici: kullaniciAdiCtrl.text.trim(),
                                  apiSifre: sifreCtrl.text.trim(),
                                  eFaturaAktif: eFaturaAktif,
                                  eArsivAktif: eArsivAktif,
                                );
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "✅ ${unvanCtrl.text.trim()} ayarları güncellendi.",
                                ),
                              ),
                            );
                          },
                          child: const Text("Kaydet"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF111827), width: 1.5),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
      decoration: _inputDecoration(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firma = ref.watch(firmaProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        titleSpacing: 16,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const Text(
              "LedgerArc AI",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildTabBtn(0, "AI Asistan"),
                    _buildTabBtn(1, "📁 Klasörlü Cariler"),
                    _buildTabBtn(2, "🗓️ Ödeme Takvimi"),
                    _buildTabBtn(3, "📑 Yevmiye Defteri"),
                    _buildTabBtn(4, "⚖️ Mizan"),
                    _buildTabBtn(5, "🏦 Kasa & Banka"),
                    _buildTabBtn(6, "📊 Mali Tablolar"),
                    _buildTabBtn(7, "📦 Depo & Stok"),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _firmaAyarModaliAc,
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(
                    firma.aktifFirmaUnvan,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "PRO",
                      style: TextStyle(
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _seciliSekme, children: _sayfalar),
    );
  }

  Widget _buildTabBtn(int index, String label) {
    final secili = _seciliSekme == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: secili
              ? const Color(0xFF111111)
              : const Color(0xFFF3F4F6),
          foregroundColor: secili ? Colors.white : const Color(0xFF4B5563),
          side: BorderSide(
            color: secili ? const Color(0xFF111111) : const Color(0xFFE5E7EB),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        ),
        onPressed: () {
          setState(() => _seciliSekme = index);
        },
        child: Text(
          label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
