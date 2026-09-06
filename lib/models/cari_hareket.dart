class CariHareket {
  final int? id;
  final int cariId;
  final String faturaNo;
  final String tarih;
  final String vadeTarihi;
  final String odemeYontemi;
  final String islemTuru;
  final double borc;
  final double alacak;
  final String aciklama;
  final String? belgeYolu;

  CariHareket({
    this.id,
    required this.cariId,
    this.faturaNo = '',
    required this.tarih,
    this.vadeTarihi = '',
    this.odemeYontemi = 'AÇIK_HESAP',
    required this.islemTuru,
    this.borc = 0.0,
    this.alacak = 0.0,
    this.aciklama = '',
    this.belgeYolu,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cari_id': cariId,
      'fatura_no': faturaNo,
      'tarih': tarih,
      'vade_tarihi': vadeTarihi,
      'odeme_yontemi': odemeYontemi,
      'islem_turu': islemTuru,
      'borc': (borc * 100).round(), // Kuruşa Çevir
      'alacak': (alacak * 100).round(), // Kuruşa Çevir
      'aciklama': aciklama,
      'belge_yolu': belgeYolu,
    };
  }

  factory CariHareket.fromMap(Map<String, dynamic> map) {
    return CariHareket(
      id: map['id'] as int?,
      cariId: map['cari_id'] as int,
      faturaNo: map['fatura_no'] as String? ?? '',
      tarih: map['tarih'] as String,
      vadeTarihi: map['vade_tarihi'] as String? ?? '',
      odemeYontemi: map['odeme_yontemi'] as String? ?? 'AÇIK_HESAP',
      islemTuru: map['islem_turu'] as String,
      borc: map['borc'] != null ? (map['borc'] as num).toDouble() / 100.0 : 0.0,
      alacak: map['alacak'] != null
          ? (map['alacak'] as num).toDouble() / 100.0
          : 0.0,
      aciklama: map['aciklama'] as String? ?? '',
      belgeYolu: map['belge_yolu'] as String?,
    );
  }
}
