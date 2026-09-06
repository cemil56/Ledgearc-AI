class YevmiyeKaydi {
  final int? id;
  final int? hareketId;
  final String fisNo;
  final String tarih;
  final String hesapKodu;
  final String hesapAdi;
  final double borc;
  final double alacak;
  final String aciklama;
  final String? belgeYolu;

  YevmiyeKaydi({
    this.id,
    this.hareketId,
    required this.fisNo,
    required this.tarih,
    required this.hesapKodu,
    required this.hesapAdi,
    this.borc = 0.0,
    this.alacak = 0.0,
    this.aciklama = '',
    this.belgeYolu,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hareket_id': hareketId,
      'fis_no': fisNo,
      'tarih': tarih,
      'hesap_kodu': hesapKodu,
      'hesap_adi': hesapAdi,
      'borc': (borc * 100).round(), // Kuruşa Çevir
      'alacak': (alacak * 100).round(), // Kuruşa Çevir
      'aciklama': aciklama,
      'belge_yolu': belgeYolu,
    };
  }

  factory YevmiyeKaydi.fromMap(Map<String, dynamic> map) {
    return YevmiyeKaydi(
      id: map['id'] as int?,
      hareketId: map['hareket_id'] as int?,
      fisNo: map['fis_no'] as String,
      tarih: map['tarih'] as String,
      hesapKodu: map['hesap_kodu'] as String,
      hesapAdi: map['hesap_adi'] as String,
      borc: map['borc'] != null ? (map['borc'] as num).toDouble() / 100.0 : 0.0,
      alacak: map['alacak'] != null
          ? (map['alacak'] as num).toDouble() / 100.0
          : 0.0,
      aciklama: map['aciklama'] as String? ?? '',
      belgeYolu: map['belge_yolu'] as String?,
    );
  }
}
