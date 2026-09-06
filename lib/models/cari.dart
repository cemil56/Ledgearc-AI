class Cari {
  final int? id;
  final String unvan;
  final String grupAdi;
  final String vergiNo;
  final String sehir;
  final double bakiye; // Ekranda bozulmasın diye UI için TL (double) kalıyor
  final String olusturmaTarihi;

  Cari({
    this.id,
    required this.unvan,
    required this.grupAdi,
    this.vergiNo = '',
    this.sehir = 'Genel',
    this.bakiye = 0.0,
    required this.olusturmaTarihi,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'unvan': unvan,
      'grup_adi': grupAdi,
      'vergi_no': vergiNo,
      'sehir': sehir,
      // 🚨 Veritabanına (SQLite) Kuruş (Integer) olarak gönderiyoruz!
      'bakiye': (bakiye * 100).round(),
      'olusturma_tarihi': olusturmaTarihi,
    };
  }

  factory Cari.fromMap(Map<String, dynamic> map) {
    return Cari(
      id: map['id'] as int?,
      unvan: map['unvan'] as String,
      grupAdi: map['grup_adi'] as String? ?? '',
      vergiNo: map['vergi_no'] as String? ?? '',
      sehir: map['sehir'] as String? ?? 'Genel',
      // 🚨 Veritabanından Kuruş (Integer) geliyor, biz UI için TL'ye (Double) çeviriyoruz!
      bakiye: map['bakiye'] != null
          ? (map['bakiye'] as num).toDouble() / 100.0
          : 0.0,
      olusturmaTarihi: map['olusturma_tarihi'] as String? ?? '',
    );
  }
}
