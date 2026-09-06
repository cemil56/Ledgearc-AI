// lib/services/rag_service.dart

class MevzuatBelgesi {
  final String baslik;
  final String icerik;

  const MevzuatBelgesi({required this.baslik, required this.icerik});
}

class RagService {
  static const List<MevzuatBelgesi> mevzuatKorpusu = [
    MevzuatBelgesi(
      baslik: "VUK 213 / Mükerrer Madde 257 - Tevsik Zorunluluğu",
      icerik: "7.000 TL ve üzerindeki her türlü mal/hizmet bedeli, avans, pey akçesi ve cari hesap ödemeleri banka, finans kurumları veya PTT aracı kılınarak tevsik edilmek zorundadır. Aksi takdirde işlem tutarının %10'u oranında Özel Usulsüzlük Cezası kesilir.",
    ),
    MevzuatBelgesi(
      baslik: "TTK 6102 - Madde 376 Sermaye Kaybı ve Borca Batıklık",
      icerik: "Son yıllık bilançodan sermaye ile kanuni yedek akçeler toplamının 2/3'ünün zarar sebebiyle karşılıksız kaldığı anlaşılırsa genel kurul toplantıya çağrılır; sermaye tamamlanmazsa şirket doğrudan infisah eder.",
    ),
    MevzuatBelgesi(
      baslik: "KDVK 3065 - Madde 9 KDV Tevkifat Uygulaması",
      icerik: "Yapım işleri, temizlik, güvenlik, danışmanlık, makine bakım-onarım ve personel temin hizmetlerinde KDV oranının belirli bir kısmı (2/10, 5/10, 9/10 vb.) alıcı tarafından tevkif edilerek 2 No'lu KDV beyannamesi ile devlete ödenir.",
    ),
    MevzuatBelgesi(
      baslik: "4458 Sayılı Gümrük Kanunu & TGTC - CIF Kıymeti ve Tarife",
      icerik: "İthal eşyasının vergi matrahı, fatura bedeline navlun ve sigorta giderlerinin eklenmesiyle oluşan CIF kıymetidir. Vadeli ithalatlarda ayrıca %6 KKDF matraha eklenir.",
    ),
    MevzuatBelgesi(
      baslik: "4857 Sayılı İş Kanunu - Madde 14 & 17 Tazminatlar",
      icerik: "En az 1 yıl çalışan işçiye haklı fesih olmaksızın işten ayrılışta çalıştığı her yıl için 30 günlük brüt giydirilmiş ücret üzerinden kıdem tazminatı ve bildirim sürelerine göre ihbar tazminatı ödenir.",
    ),
  ];

  /// Kullanıcının girdiği metne göre en alakalı mevzuat maddelerini puanlayıp döndürür.
  static List<MevzuatBelgesi> ara(String sorgu, {int topK = 2}) {
    if (sorgu.trim().isEmpty) return [];

    final kelimeler = RegExp(r'\w+')
        .allMatches(sorgu.toLowerCase())
        .map((m) => m.group(0)!)
        .where((k) => k.length > 2)
        .toList();

    if (kelimeler.isEmpty) return [];

    final List<MapEntry<int, MevzuatBelgesi>> puanliSonuclar = [];

    for (final doc in mevzuatKorpusu) {
      final baslikKucuk = doc.baslik.toLowerCase();
      final icerikKucuk = doc.icerik.toLowerCase();
      int skor = 0;

      for (final k in kelimeler) {
        if (baslikKucuk.contains(k)) {
          skor += 2;
        }
        if (icerikKucuk.contains(k)) {
          skor += 1;
        }
      }

      if (skor > 0) {
        puanliSonuclar.add(MapEntry(skor, doc));
      }
    }

    // Skorlara göre azalan sırada sırala
    puanliSonuclar.sort((a, b) => b.key.compareTo(a.key));

    return puanliSonuclar.take(topK).map((e) => e.value).toList();
  }

  /// Gemini için metin bağlamı üretir
  static String baglamUret(String sorgu) {
    final sonuclar = ara(sorgu);
    if (sonuclar.isEmpty) return '';
    return sonuclar.map((m) => '[${m.baslik}]: ${m.icerik}').join('\n');
  }
}
