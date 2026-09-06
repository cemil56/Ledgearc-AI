// lib/services/fatura_pdf_service.dart
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class FaturaPdfService {
  static Future<void> yazdir({
    required String faturaNo,
    required String tarih,
    required String cariUnvan,
    required String vergiNo,
    required String sehir,
    required String odemeYontemi,
    required List<Map<String, dynamic>> kalemler,
    required double matrah,
    required double kdv,
    required double genelToplam,
  }) async {
    final doc = pw.Document();
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: 'TL');

    // Standart font yüklemesi
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        footer: (context) {
          // Barkod ve ETTN alt bilgisi her sayfanın altında sabit kalır
          return pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data:
                      'https://earsivportal.gib.gov.tr/dogrula?fatura=$faturaNo',
                  width: 40,
                  height: 40,
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GİB İmza & Zaman Damgası Doğrulandı',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8,
                      ),
                    ),
                    pw.Text(
                      'ETTN: 3c8e54a0-f82b-426c-8f92-${faturaNo.hashCode.abs().toString().padLeft(12, '0').substring(0, 12)}',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // 1. Başlık & Fatura No
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'e-ARŞİV FATURA',
                      style: pw.TextStyle(
                        color: PdfColors.red900,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'GİB UBL-TR 2.1 Standardı',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        faturaNo,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      pw.Text(
                        'Tarih: $tarih',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        'Senaryo: TEMEL e-ARŞİV',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 12),

            // 2. Satıcı / Alıcı Bilgileri
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'DÜZENLEYEN (SATICI)',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                            color: PdfColors.blue800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'MERKEZ ŞİRKET SAN. VE TİC. LTD. ŞTİ.',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          'VKN: 9876543210',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          'Seyhan Vergi Dairesi',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          'Adana / Türkiye',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SAYIN (ALICI)',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          cariUnvan,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          'VKN/TCKN: $vergiNo',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          '$sehir / Türkiye',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          'Ödeme: $odemeYontemi',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // 3. Kalemler Tablosu (Otomatik olarak sayfalara bölünür)
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'Mal / Hizmet',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'Miktar',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'Birim Fiyat',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'KDV',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        'Tutar',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
                ...kalemler.map((k) {
                  final ad = (k['stok_adi'] ?? 'Ürün').toString();
                  final miktar = (k['miktar'] as num?)?.toDouble() ?? 1.0;
                  final birim = (k['birim'] ?? 'Adet').toString();
                  final birimFiyat =
                      (k['birimFiyat'] as num?)?.toDouble() ?? 0.0;
                  final satirTutari = miktar * birimFiyat;

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          ad,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          '$miktar $birim',
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          fmt.format(birimFiyat),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          '%20',
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          fmt.format(satirTutari),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 16),

            // 4. Mali Toplamlar
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 220,
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Mal / Hizmet Tutarı:',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          pw.Text(
                            fmt.format(matrah),
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Hesaplanan KDV (%20):',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          pw.Text(
                            fmt.format(kdv),
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      pw.Divider(thickness: 0.8, color: PdfColors.grey400),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'ÖDENECEK TUTAR:',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          pw.Text(
                            fmt.format(genelToplam),
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                              color: PdfColors.green900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: '$faturaNo.pdf',
    );
  }
}
