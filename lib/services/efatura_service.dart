import 'dart:math';

import 'package:uuid/uuid.dart';

class EFaturaSonuc {
  final bool basarili;
  final String faturaNo;
  final String? mesaj;
  final String? ublXml;
  final String? uuid; // ETTN (UUID) eklendi

  EFaturaSonuc({
    required this.basarili,
    required this.faturaNo,
    this.mesaj,
    this.ublXml,
    this.uuid,
  });
}

class EFaturaService {
  static final EFaturaService instance = EFaturaService._init();
  EFaturaService._init();

  bool testModu = true;
  final _uuidGen = const Uuid();

  // Faturayı Entegratöre veya Test Sunucusuna Gönder
  Future<EFaturaSonuc> faturaGonder({
    required String aliciUnvan,
    required String aliciVknTckn,
    required String faturaTipi, // 'SATIS' veya 'ALIS'
    required List<Map<String, dynamic>> kalemler,
    required double matrah,
    required double kdv,
    required double genelToplam,
  }) async {
    // 1. ETTN (UUID) ve GİB Formatında Fatura No Üretimi
    final String uretilenUuid = _uuidGen.v4();
    final int rastgeleNo = Random().nextInt(899999) + 100000;
    final String uretilenFaturaNo = "GIB${DateTime.now().year}$rastgeleNo";

    // 2. Kusursuz UBL-TR 2.1 XML Verisini Oluştur
    final xml = _ublXmlUret(
      faturaNo: uretilenFaturaNo,
      uuid: uretilenUuid,
      aliciUnvan: aliciUnvan,
      aliciVknTckn: aliciVknTckn,
      kalemler: kalemler,
      matrah: matrah,
      kdv: kdv,
      genelToplam: genelToplam,
    );

    if (testModu) {
      await Future.delayed(
        const Duration(milliseconds: 1500),
      ); // Ağ gecikmesi simülasyonu

      print("===== OLUŞTURULAN UBL-TR 2.1 XML =====");
      print(xml);
      print("======================================");

      return EFaturaSonuc(
        basarili: true,
        faturaNo: uretilenFaturaNo,
        uuid: uretilenUuid,
        mesaj: "Test Modu: Fatura XML başarıyla oluşturuldu ve GİB simülatörüne iletildi.",
        ublXml: xml,
      );
    }

    // CANLI ORTAM İÇİN (İleride EDM, Uyumsoft veya GİB Login API buraya gelecek)
    return EFaturaSonuc(
      basarili: false,
      faturaNo: '',
      mesaj: "Canlı ortam kimlik bilgileri yapılandırılmadı.",
    );
  }

  String _xmlTemizle(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  // Standart GİB UBL-TR 2.1 XML Üretici (Maliye Uyumlu)
  String _ublXmlUret({
    required String faturaNo,
    required String uuid,
    required String aliciUnvan,
    required String aliciVknTckn,
    required List<Map<String, dynamic>> kalemler,
    required double matrah,
    required double kdv,
    required double genelToplam,
  }) {
    final simdi = DateTime.now();
    final tarih = simdi.toIso8601String().substring(0, 10);
    final saat =
        "${simdi.hour.toString().padLeft(2, '0')}:${simdi.minute.toString().padLeft(2, '0')}:${simdi.second.toString().padLeft(2, '0')}";

    // Vergi Nosu 10 hane ise VKN, 11 hane ise TCKN'dir
    final isVkn = aliciVknTckn.replaceAll(RegExp(r'[^0-9]'), '').length == 10;
    final schemeID = isVkn ? "VKN" : "TCKN";

    StringBuffer kalemlerXml = StringBuffer();
    for (int i = 0; i < kalemler.length; i++) {
      final k = kalemler[i];
      final miktar = (k['miktar'] as num).toDouble();
      final birimFiyat = (k['birimFiyat'] as num).toDouble();
      final satirTutari = miktar * birimFiyat;
      final kdvOrani = (k['kdvOrani'] as num).toDouble();
      final satirKdvTutari = satirTutari * (kdvOrani / 100);

      kalemlerXml.write('''
  <cac:InvoiceLine>
    <cbc:ID>${i + 1}</cbc:ID>
    <cbc:InvoicedQuantity unitCode="NIU">$miktar</cbc:InvoicedQuantity>
    <cbc:LineExtensionAmount currencyID="TRY">${satirTutari.toStringAsFixed(2)}</cbc:LineExtensionAmount>
    <cac:TaxTotal>
      <cbc:TaxAmount currencyID="TRY">${satirKdvTutari.toStringAsFixed(2)}</cbc:TaxAmount>
      <cac:TaxSubtotal>
        <cbc:TaxableAmount currencyID="TRY">${satirTutari.toStringAsFixed(2)}</cbc:TaxableAmount>
        <cbc:TaxAmount currencyID="TRY">${satirKdvTutari.toStringAsFixed(2)}</cbc:TaxAmount>
        <cac:TaxCategory>
          <cbc:Percent>${kdvOrani.toStringAsFixed(0)}</cbc:Percent>
          <cac:TaxScheme>
            <cbc:Name>KDV</cbc:Name>
            <cbc:TaxTypeCode>0015</cbc:TaxTypeCode>
          </cac:TaxScheme>
        </cac:TaxCategory>
      </cac:TaxSubtotal>
    </cac:TaxTotal>
    <cac:Item>
<cbc:Name>${_xmlTemizle((k['stok_adi'] ?? 'Muhtelif Mal/Hizmet').toString())}</cbc:Name>    </cac:Item>
    <cac:Price>
      <cbc:PriceAmount currencyID="TRY">${birimFiyat.toStringAsFixed(2)}</cbc:PriceAmount>
    </cac:Price>
  </cac:InvoiceLine>''');
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
         xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
         xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:UBLVersionID>2.1</cbc:UBLVersionID>
  <cbc:CustomizationID>TR1.2</cbc:CustomizationID>
  <cbc:ProfileID>EARSIVFATURA</cbc:ProfileID>
  <cbc:ID>$faturaNo</cbc:ID>
  <cbc:CopyIndicator>false</cbc:CopyIndicator>
  <cbc:UUID>$uuid</cbc:UUID>
  <cbc:IssueDate>$tarih</cbc:IssueDate>
  <cbc:IssueTime>$saat</cbc:IssueTime>
  <cbc:InvoiceTypeCode>SATIS</cbc:InvoiceTypeCode>
  <cbc:Note>LedgerArc AI Tarafindan Uretilmistir.</cbc:Note>
  <cbc:DocumentCurrencyCode>TRY</cbc:DocumentCurrencyCode>
  <cac:AccountingSupplierParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="VKN">9876543210</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
        <cbc:Name>MERKEZ ŞİRKET SAN. VE TİC. LTD. ŞTİ.</cbc:Name>
      </cac:PartyName>
    </cac:Party>
  </cac:AccountingSupplierParty>
  <cac:AccountingCustomerParty>
    <cac:Party>
      <cac:PartyIdentification>
        <cbc:ID schemeID="$schemeID">$aliciVknTckn</cbc:ID>
      </cac:PartyIdentification>
      <cac:PartyName>
<cbc:Name>${_xmlTemizle(aliciUnvan)}</cbc:Name>      </cac:PartyName>
    </cac:Party>
  </cac:AccountingCustomerParty>
  <cac:TaxTotal>
    <cbc:TaxAmount currencyID="TRY">${kdv.toStringAsFixed(2)}</cbc:TaxAmount>
    <cac:TaxSubtotal>
      <cbc:TaxableAmount currencyID="TRY">${matrah.toStringAsFixed(2)}</cbc:TaxableAmount>
      <cbc:TaxAmount currencyID="TRY">${kdv.toStringAsFixed(2)}</cbc:TaxAmount>
      <cac:TaxCategory>
        <cbc:Percent>20</cbc:Percent>
        <cac:TaxScheme>
          <cbc:Name>KDV</cbc:Name>
          <cbc:TaxTypeCode>0015</cbc:TaxTypeCode>
        </cac:TaxScheme>
      </cac:TaxCategory>
    </cac:TaxSubtotal>
  </cac:TaxTotal>
  <cac:LegalMonetaryTotal>
    <cbc:LineExtensionAmount currencyID="TRY">${matrah.toStringAsFixed(2)}</cbc:LineExtensionAmount>
    <cbc:TaxExclusiveAmount currencyID="TRY">${matrah.toStringAsFixed(2)}</cbc:TaxExclusiveAmount>
    <cbc:TaxInclusiveAmount currencyID="TRY">${genelToplam.toStringAsFixed(2)}</cbc:TaxInclusiveAmount>
    <cbc:PayableAmount currencyID="TRY">${genelToplam.toStringAsFixed(2)}</cbc:PayableAmount>
  </cac:LegalMonetaryTotal>
${kalemlerXml.toString()}
</Invoice>''';
  }
}
