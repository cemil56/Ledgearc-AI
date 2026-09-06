import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yevmiye_kaydi.dart';
import '../repositories/yevmiye_repository.dart';
import 'firma_provider.dart';

final yevmiyeRepositoryProvider = Provider((ref) => YevmiyeRepository());

final yevmiyeProvider =
    AsyncNotifierProvider<YevmiyeNotifier, List<YevmiyeKaydi>>(() {
      return YevmiyeNotifier();
    });

class YevmiyeNotifier extends AsyncNotifier<List<YevmiyeKaydi>> {
  @override
  Future<List<YevmiyeKaydi>> build() async {
    final firmaId = ref.watch(firmaProvider).aktifFirmaId;
    final repo = ref.read(yevmiyeRepositoryProvider);
    return await repo.getYevmiyeKayitlari(firmaId);
  }

  void yenile() {
    ref.invalidateSelf();
  }
}
