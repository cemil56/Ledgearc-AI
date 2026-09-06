import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cari.dart';
import '../repositories/cari_repository.dart';
import 'firma_provider.dart';
import '../services/database_service.dart';

final cariRepositoryProvider = Provider((ref) => CariRepository());

final carilerProvider =
    AsyncNotifierProvider<CariNotifier, Map<String, List<Cari>>>(() {
      return CariNotifier();
    });

class CariNotifier extends AsyncNotifier<Map<String, List<Cari>>> {
  @override
  Future<Map<String, List<Cari>>> build() async {
    final firmaId = ref.watch(firmaProvider).aktifFirmaId;
    final repo = ref.read(cariRepositoryProvider);
    final cariler = await repo.getCariler(firmaId);

    final Map<String, List<Cari>> gruplar = {};
    for (var cari in cariler) {
      final grup = cari.grupAdi.isNotEmpty
          ? cari.grupAdi
          : DatabaseService.grupAdiCikar(cari.unvan);
      if (!gruplar.containsKey(grup)) {
        gruplar[grup] = [];
      }
      gruplar[grup]!.add(cari);
    }
    return gruplar;
  }

  Future<void> cariEkle({
    required String unvan,
    required String vergiNo,
    required String sehir,
    required String grupAdi,
  }) async {
    final firmaId = ref.read(firmaProvider).aktifFirmaId;
    final repo = ref.read(cariRepositoryProvider);

    await repo.cariEkle(
      firmaId: firmaId,
      unvan: unvan,
      grupAdi: grupAdi,
      vergiNo: vergiNo,
      sehir: sehir,
    );

    ref.invalidateSelf(); // İşlem bitince arayüzü otomatik olarak tetikler
  }

  void yenile() {
    ref.invalidateSelf();
  }
}
