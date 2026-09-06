import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/database_service.dart';
import 'firma_provider.dart';

class LikiditeState {
  final double kasa100;
  final double banka102;
  final double acikAlacaklar;
  final double acikBorclar;
  final double netLikidite;
  final bool isLoading;

  const LikiditeState({
    this.kasa100 = 0.0,
    this.banka102 = 0.0,
    this.acikAlacaklar = 0.0,
    this.acikBorclar = 0.0,
    this.netLikidite = 0.0,
    this.isLoading = false,
  });
}

class LedgerNotifier extends Notifier<LikiditeState> {
  final _db = DatabaseService.instance;

  @override
  LikiditeState build() {
    final firma = ref.watch(firmaProvider);
    yukle(firma.aktifFirmaId);
    return const LikiditeState(isLoading: true);
  }

  Future<void> yukle(int firmaId) async {
    final veri = await _db.getKasaBankaDurumu(firmaId: firmaId);

    // 🚨 KURUŞ KORUMASI: DB'den Kuruş olarak gelen değerleri State'e (UI'a) yazarken 100'e bölerek TL yapıyoruz!
    state = LikiditeState(
      kasa100: (veri['kasa_100'] as num).toDouble() / 100.0,
      banka102: (veri['banka_102'] as num).toDouble() / 100.0,
      acikAlacaklar: (veri['acik_alacaklar'] as num).toDouble() / 100.0,
      acikBorclar: (veri['acik_borclar'] as num).toDouble() / 100.0,
      netLikidite: (veri['net_likidite'] as num).toDouble() / 100.0,
      isLoading: false,
    );
  }

  Future<void> yenile() async {
    final firma = ref.read(firmaProvider);
    await yukle(firma.aktifFirmaId);
  }
}

final ledgerProvider = NotifierProvider<LedgerNotifier, LikiditeState>(() {
  return LedgerNotifier();
});
