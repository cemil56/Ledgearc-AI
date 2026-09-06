import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/firma_provider.dart';
import '../providers/ledger_provider.dart';
import '../providers/cari_provider.dart';
import '../models/cari.dart';
import '../models/cari_hareket.dart';
import '../services/fatura_pdf_service.dart';

class CarilerScreen extends ConsumerStatefulWidget {
  const CarilerScreen({super.key});

  @override
  ConsumerState<CarilerScreen> createState() => _CarilerScreenState();
}

class _CarilerScreenState extends ConsumerState<CarilerScreen> {
  void _yeniCariModalAc() {
    final unvanCtrl = TextEditingController();
    final vknCtrl = TextEditingController();
    final sehirCtrl = TextEditingController(text: "Adana");
    final grupCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          "Yeni Cari Kartı Oluştur",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: unvanCtrl,
                decoration: const InputDecoration(
                  labelText: "Cari Unvan / Adı Soyadı",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: vknCtrl,
                decoration: const InputDecoration(
                  labelText: "VKN / TCKN",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sehirCtrl,
                decoration: const InputDecoration(
                  labelText: "Şehir",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: grupCtrl,
                decoration: const InputDecoration(
                  labelText: "Özel Grup (Boşsa otomatik atanır)",
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
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
            ),
            onPressed: () async {
              final unvan = unvanCtrl.text.trim();
              if (unvan.isEmpty) return;

              // Yeni Cari'yi veritabanına gönderme işlemi artık Provider üzerinden!
              await ref
                  .read(carilerProvider.notifier)
                  .cariEkle(
                    unvan: unvan,
                    vergiNo: vknCtrl.text.trim(),
                    sehir: sehirCtrl.text.trim(),
                    grupAdi: grupCtrl.text.trim(),
                  );

              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
  }

  void _belgeyiGoster(BuildContext context, String dosyaYolu) {
    final file = File(dosyaYolu);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Belge dosyası yerel diskte bulunamadı."),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final uzanti = dosyaYolu.toLowerCase();
    final isResim =
        uzanti.endsWith('.jpg') ||
        uzanti.endsWith('.jpeg') ||
        uzanti.endsWith('.png');

    if (isResim) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  constraints: const BoxConstraints(
                    maxHeight: 600,
                    maxWidth: 700,
                  ),
                  child: InteractiveViewer(
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "📄 Ekli Belge: ${file.path.split(Platform.pathSeparator).last}",
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _eArsivFaturaGoster(
    BuildContext context,
    Cari cari,
    CariHareket hareket,
  ) async {
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    String faturaNo = hareket.faturaNo;
    if (faturaNo.isEmpty || faturaNo == '-') {
      final aciklama = hareket.aciklama;
      if (aciklama.contains('GIB')) {
        final baslangic = aciklama.indexOf('GIB');
        faturaNo = aciklama
            .substring(
              baslangic,
              (baslangic + 16 <= aciklama.length)
                  ? baslangic + 16
                  : aciklama.length,
            )
            .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      } else {
        faturaNo = 'GIB2026000000000';
      }
    }

    final firmaId = ref.read(firmaProvider).aktifFirmaId;
    // Fatura kalemlerini de repository'den temizce alıyoruz
    final kalemler = await ref
        .read(cariRepositoryProvider)
        .getFaturaKalemleri(firmaId, faturaNo);

    if (!context.mounted) return;

    final tarih = hareket.tarih.split('T').first;
    final borc = hareket.borc;
    final alacak = hareket.alacak;
    final double genelToplam = borc > 0 ? borc : alacak;
    final double matrah = genelToplam / 1.20;
    final double kdv = genelToplam - matrah;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 780,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.account_balance,
                            color: Color(0xFFDC2626),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "e-ARŞİV FATURA",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFDC2626),
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              "GİB UBL-TR 2.1 Standardı (Test Ortamı)",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFFF9FAFB),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            faturaNo,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Tarih: $tarih",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                          Text(
                            "Senaryo: TEMEL e-ARŞİV",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "DÜZENLEYEN (SATICI)",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              "MERKEZ ŞİRKET SAN. VE TİC. LTD. ŞTİ.",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              "VKN: 9876543210",
                              style: TextStyle(fontSize: 11),
                            ),
                            const Text(
                              "Seyhan Vergi Dairesi",
                              style: TextStyle(fontSize: 11),
                            ),
                            Text(
                              "Adana / Türkiye",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "SAYIN (ALICI)",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cari.unvan,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "VKN/TCKN: ${cari.vergiNo.isNotEmpty ? cari.vergiNo : '11111111111'}",
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              "${cari.sehir} / Türkiye",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              "Ödeme: ${hareket.odemeYontemi}",
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(7),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                "Mal / Hizmet",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                "Miktar",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                "Birim Fiyat",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "KDV",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                "Tutar",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (kalemler.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            hareket.aciklama.isEmpty
                                ? 'Kalem bilgisi'
                                : hareket.aciklama,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ...kalemler.map((k) {
                          final ad = (k['stok_adi'] ?? 'Ürün').toString();
                          final miktar =
                              (k['miktar'] as num?)?.toDouble() ?? 1.0;
                          final birim = (k['birim'] ?? 'Adet').toString();
                          final birimFiyat =
                              (k['birimFiyat'] as num?)?.toDouble() ?? 0.0;
                          final satirTutari = miktar * birimFiyat;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Color(0xFFF3F4F6)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    ad,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    "$miktar $birim",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    fmt.format(birimFiyat),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Expanded(
                                  flex: 1,
                                  child: Text(
                                    "%20",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    fmt.format(satirTutari),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 280,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Mal / Hizmet Tutarı:",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                            Text(
                              fmt.format(matrah),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Hesaplanan KDV (%20):",
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                            Text(
                              fmt.format(kdv),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "ÖDENECEK TUTAR:",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text(
                              fmt.format(genelToplam),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.qr_code_2,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "GİB İmza & Zaman Damgası Doğrulandı",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              "ETTN: 3c8e54a0-f82b-426c-8f92-${faturaNo.hashCode.abs().toString().padLeft(12, '0').substring(0, 12)}",
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        "Kapat",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text("Yazdır / PDF"),
                      onPressed: () {
                        FaturaPdfService.yazdir(
                          faturaNo: faturaNo,
                          tarih: tarih,
                          cariUnvan: cari.unvan,
                          vergiNo: cari.vergiNo.isNotEmpty
                              ? cari.vergiNo
                              : '11111111111',
                          sehir: cari.sehir,
                          odemeYontemi: hareket.odemeYontemi,
                          kalemler: kalemler,
                          matrah: matrah,
                          kdv: kdv,
                          genelToplam: genelToplam,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _ekstreGoster(BuildContext context, Cari cari) async {
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final firmaId = ref.read(firmaProvider).aktifFirmaId;

    // Repository üzerinden temiz veri çekişi (Kuruş->TL hazır)
    final hareketler = await ref
        .read(cariRepositoryProvider)
        .getCariHareketler(firmaId, cari.id!);

    if (!context.mounted) return;

    final cariBakiye = cari.bakiye;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 900,
          constraints: const BoxConstraints(maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "📊 Cari Hesap Ekstresi: ${cari.unvan}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "VKN: ${cari.vergiNo} • Güncel Net Bakiye: ${fmt.format(cariBakiye)}",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cariBakiye >= 0
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 28),
              if (hareketler.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      "Bu cariye ait henüz işlem hareketi bulunmuyor.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.2),
                        1: FlexColumnWidth(1.4),
                        2: FlexColumnWidth(1.2),
                        3: FlexColumnWidth(2.0),
                        4: FlexColumnWidth(1.3),
                        5: FlexColumnWidth(1.3),
                        6: FlexColumnWidth(0.8),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFFE5E7EB),
                                width: 1.5,
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Tarih",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Fatura No",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Yöntem",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Açıklama",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Borç",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Alacak",
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                "Belge",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ...hareketler.map((h) {
                          final borc = h.borc;
                          final alacak = h.alacak;
                          final tarih = h.tarih.split('T').first;
                          final belgeYolu = h.belgeYolu;
                          final belgeVar =
                              belgeYolu != null && belgeYolu.isNotEmpty;

                          String faturaNo = h.faturaNo;
                          if (faturaNo.isEmpty &&
                              (h.aciklama.contains('GIB'))) {
                            final aciklama = h.aciklama;
                            final baslangic = aciklama.indexOf('GIB');
                            faturaNo = aciklama.substring(
                              baslangic,
                              baslangic + 13,
                            );
                          }

                          return TableRow(
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFF3F4F6)),
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  tarih,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  faturaNo.isNotEmpty ? faturaNo : '-',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  h.odemeYontemi,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  h.aciklama.isEmpty ? '-' : h.aciklama,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  borc > 0 ? fmt.format(borc) : "-",
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  alacak > 0 ? fmt.format(alacak) : "-",
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Center(
                                  child: faturaNo.startsWith('GIB')
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.picture_as_pdf_rounded,
                                            size: 20,
                                            color: Color(0xFFDC2626),
                                          ),
                                          tooltip: "GİB e-Arşiv Faturasını Görüntüle",
                                          onPressed: () => _eArsivFaturaGoster(
                                            context,
                                            cari,
                                            h,
                                          ),
                                        )
                                      : belgeVar
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.attach_file,
                                            size: 18,
                                            color: Color(0xFF2563EB),
                                          ),
                                          tooltip: "Ekli Belgeyi Gör",
                                          onPressed: () => _belgeyiGoster(
                                            context,
                                            belgeYolu,
                                          ),
                                        )
                                      : const Text(
                                          "-",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      ledgerProvider,
      (_, _) => ref.read(carilerProvider.notifier).yenile(),
    );

    // 🚨 ARTIK SQL YOK: Arayüz sadece asenkron Provider'ı dinliyor!
    final carilerState = ref.watch(carilerProvider);
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "📁 Klasörlü Cari Şirket Grupları",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Aynı holdinge veya gruba bağlı firmalar otomatik klasörlenmiştir. Detaylı hesap ekstresi için cariye tıklayın.",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Yeni Cari"),
                  onPressed: _yeniCariModalAc,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              // 🚨 Riverpod AsyncValue yapısı: Yükleniyor, Hata ve Data durumlarını otomatik yönetir!
              child: carilerState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text("Hata oluştu: $err")),
                data: (gruplar) {
                  if (gruplar.isEmpty) {
                    return const Center(
                      child: Text("Henüz kayıtlı cari bulunmuyor."),
                    );
                  }
                  return ListView(
                    children: gruplar.entries.map((entry) {
                      final grupAdi = entry.key;
                      final cariler = entry.value;
                      final toplamBakiye = cariler.fold<double>(
                        0.0,
                        (toplam, item) => toplam + item.bakiye,
                      );

                      return Card(
                        elevation: 0,
                        color: const Color(0xFFF9FAFB),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ExpansionTile(
                          shape: const Border(),
                          title: Row(
                            children: [
                              Text(
                                "📂 $grupAdi",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  "${cariler.length} Firma",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Text(
                            fmt.format(toplamBakiye),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: toplamBakiye >= 0
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                          children: cariler.map((cari) {
                            return InkWell(
                              onTap: () => _ekstreGoster(context, cari),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            cari.unvan,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            "VKN: ${cari.vergiNo} • Şehir: ${cari.sehir}",
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      fmt.format(cari.bakiye),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: cari.bakiye >= 0
                                            ? const Color(0xFF059669)
                                            : const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
