// lib/providers/firma_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirmaState {
  final int aktifFirmaId;
  final String aktifFirmaUnvan;
  final String vkn;
  final String vergiDairesi;
  final String entegrator;
  final String apiKullanici;
  final String apiSifre;
  final bool eFaturaAktif;
  final bool eArsivAktif;

  const FirmaState({
    this.aktifFirmaId = 1,
    this.aktifFirmaUnvan = "Merkez Şirket",
    this.vkn = "1234567890",
    this.vergiDairesi = "Seyhan V.D.",
    this.entegrator = "GİB Test Portalı (Simülasyon)",
    this.apiKullanici = "entegrator_user",
    this.apiSifre = "••••••••",
    this.eFaturaAktif = true,
    this.eArsivAktif = true,
  });

  FirmaState copyWith({
    int? aktifFirmaId,
    String? aktifFirmaUnvan,
    String? vkn,
    String? vergiDairesi,
    String? entegrator,
    String? apiKullanici,
    String? apiSifre,
    bool? eFaturaAktif,
    bool? eArsivAktif,
  }) {
    return FirmaState(
      aktifFirmaId: aktifFirmaId ?? this.aktifFirmaId,
      aktifFirmaUnvan: aktifFirmaUnvan ?? this.aktifFirmaUnvan,
      vkn: vkn ?? this.vkn,
      vergiDairesi: vergiDairesi ?? this.vergiDairesi,
      entegrator: entegrator ?? this.entegrator,
      apiKullanici: apiKullanici ?? this.apiKullanici,
      apiSifre: apiSifre ?? this.apiSifre,
      eFaturaAktif: eFaturaAktif ?? this.eFaturaAktif,
      eArsivAktif: eArsivAktif ?? this.eArsivAktif,
    );
  }
}

class FirmaNotifier extends Notifier<FirmaState> {
  @override
  FirmaState build() => const FirmaState();

  void firmaGuncelle({
    required String unvan,
    required String vkn,
    required String vergiDairesi,
    required String entegrator,
    required String apiKullanici,
    required String apiSifre,
    required bool eFaturaAktif,
    required bool eArsivAktif,
  }) {
    state = state.copyWith(
      aktifFirmaUnvan: unvan,
      vkn: vkn,
      vergiDairesi: vergiDairesi,
      entegrator: entegrator,
      apiKullanici: apiKullanici,
      apiSifre: apiSifre,
      eFaturaAktif: eFaturaAktif,
      eArsivAktif: eArsivAktif,
    );
  }
}

final firmaProvider = NotifierProvider<FirmaNotifier, FirmaState>(() {
  return FirmaNotifier();
});
