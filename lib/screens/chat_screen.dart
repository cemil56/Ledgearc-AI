import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:test_app/providers/cari_provider.dart';
import 'package:test_app/providers/yevmiye_provider.dart';

import '../providers/firma_provider.dart';
import '../providers/ledger_provider.dart';
import '../services/database_service.dart';
import '../services/gemini_service.dart';
import '../services/ses_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<dynamic>? actionItems;
  final List<File>? files;
  ChatMessage({
    required this.text,
    required this.isUser,
    this.actionItems,
    this.files,
  });
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Set<String> _kaydedilenFaturaNolari = {};
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<ChatMessage> _messages = [];
  final List<File> _selectedFiles = [];
  bool _isProcessing = false;
  bool _isDragging = false;
  bool _recordingState = false;

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _mikrofonTetikle() async {
    if (_recordingState) {
      setState(() {
        _recordingState = false;
        _isProcessing = true;
      });
      final sesDosyasi = await SesService.instance.durdur();
      if (sesDosyasi != null) {
        final metin = await GeminiService.sesiYaziyaCevir(sesDosyasi);
        if (await sesDosyasi.exists()) {
          await sesDosyasi.delete();
        }
        if (metin.isNotEmpty) {
          setState(() {
            _controller.text = _controller.text.trim().isNotEmpty
                ? "${_controller.text.trim()} $metin"
                : metin;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          });
        }
      }
      setState(() => _isProcessing = false);
    } else {
      final basladi = await SesService.instance.baslat();
      if (basladi) {
        setState(() => _recordingState = true);
      }
    }
  }

  Future<void> _dosyaSec() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'jpeg', 'pdf'],
    );
    if (result.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(
          result
              .map((file) => file.path)
              .whereType<String>()
              .map((path) => File(path)),
        );
      });
    }
  }

  Future<void> _panodanYapistir() async {
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      final eklenenler = files
          .where(
            (path) =>
                path.toLowerCase().endsWith('.pdf') ||
                path.toLowerCase().endsWith('.png') ||
                path.toLowerCase().endsWith('.jpg') ||
                path.toLowerCase().endsWith('.jpeg'),
          )
          .map((path) => File(path))
          .toList();
      if (eklenenler.isNotEmpty) {
        setState(() {
          _selectedFiles.addAll(eklenenler);
        });
        return;
      }
    }
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null) {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}ekran_goruntusu_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(imageBytes);
      setState(() {
        _selectedFiles.add(file);
      });
    }
  }

  Future<void> _gonder() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty && _selectedFiles.isEmpty) {
      return;
    }

    final filesToSend = List<File>.from(_selectedFiles);
    final String? gonderilenDosyaYolu = _selectedFiles.isNotEmpty
        ? _selectedFiles.first.path
        : null;

    setState(() {
      _messages.add(
        ChatMessage(isUser: true, text: prompt, files: filesToSend),
      );
      _controller.clear();
      _selectedFiles.clear();
      _isProcessing = true;
    });

    final firmaId = ref.read(firmaProvider).aktifFirmaId;
    final response = await GeminiService.analizEt(
      prompt: prompt.isNotEmpty ? prompt : "Belgeyi incele",
      dosyalar: filesToSend,
    );

    // 🚨 STOK DEPO YETKİSİ FİLTREDE ONAYLANDI
    final items = (response['items'] as List<dynamic>? ?? []).where((item) {
      if (item is! Map<String, dynamic>) {
        return false;
      }
      if (item['is_action'] != true) {
        return false;
      }
      if (item['islem_kategorisi'] == 'STOK_DEPO_ISLEMI') {
        return true;
      }
      return item['cari_unvan'] != null &&
          item['cari_unvan'].toString().trim().isNotEmpty &&
          item['cari_unvan'].toString().toLowerCase() != 'null';
    }).toList();

    for (var item in items) {
      if (item is Map<String, dynamic>) {
        if (gonderilenDosyaYolu != null) {
          item['attached_file_path'] = gonderilenDosyaYolu;
        }

        String kategori = (item['islem_kategorisi'] ?? '')
            .toString()
            .toUpperCase();
        item['islem_kategorisi'] = kategori;

        // 🚨 STOK ARAYÜZÜ BİLGİ DOLDURMASI
        if (kategori == 'STOK_DEPO_ISLEMI') {
          final stoklar = await DatabaseService.instance.getStokListesi(
            firmaId: firmaId,
          );
          item['stok_adaylar'] = stoklar;
          if (stoklar.isNotEmpty) {
            item['secili_stok_id'] = stoklar.first['id'];
          }
          continue;
        }

        final promptKucuk = prompt.toLowerCase();
        final hamYontem = (item['odeme_yontemi'] ?? item['odeme_sekli'] ?? '')
            .toString()
            .toUpperCase();

        if (kategori.isEmpty) {
          if (promptKucuk.contains('işçi') ||
              promptKucuk.contains('personel') ||
              promptKucuk.contains('avans') ||
              promptKucuk.contains('maaş')) {
            kategori = 'PERSONEL';
          } else if (promptKucuk.contains('fiş') ||
              promptKucuk.contains('benzin') ||
              promptKucuk.contains('mazot') ||
              promptKucuk.contains('yemek') ||
              promptKucuk.contains('masraf')) {
            kategori = 'ISLETME_GIDERI';
          } else {
            kategori = 'TICARI_CARI';
          }
        }
        item['islem_kategorisi'] = kategori;

        final isCekSenet =
            kategori == 'CEK_SENET' ||
            item['action_type']?.toString().contains('ÇEK') == true ||
            hamYontem.contains('ÇEK') ||
            hamYontem.contains('SENET');

        if (isCekSenet) {
          item['action_type'] = 'CEK_SENET_GIRISI';
          item['selected_payment'] = 'PORTFOY';
        } else {
          item['action_type'] = (kategori == 'PERSONEL')
              ? 'PERSONEL_AVANS'
              : (kategori == 'ISLETME_GIDERI' ? 'GIDER_FISI' : 'FATURA_KAYDI');
          final summaryKucuk = (item['summary']?.toString() ?? '')
              .toLowerCase();
          if (hamYontem.contains('KREDİ') ||
              hamYontem.contains('KART') ||
              hamYontem.contains('POS') ||
              summaryKucuk.contains('kredi kartı') ||
              summaryKucuk.contains('kart')) {
            item['selected_payment'] = 'KREDİ_KARTI';
          } else if (hamYontem.contains('NAKİT') ||
              hamYontem.contains('KASA') ||
              summaryKucuk.contains('nakit') ||
              summaryKucuk.contains('elden')) {
            item['selected_payment'] = 'NAKİT';
          } else if (hamYontem.contains('HAVALE') ||
              hamYontem.contains('EFT') ||
              hamYontem.contains('BANKA') ||
              summaryKucuk.contains('havale') ||
              summaryKucuk.contains('eft')) {
            item['selected_payment'] = 'HAVALE';
          } else {
            item['selected_payment'] =
                (kategori == 'ISLETME_GIDERI' || kategori == 'PERSONEL')
                ? 'NAKİT'
                : 'AÇIK_HESAP';
          }
        }

        final faturaNo = item['fatura_no']?.toString().trim() ?? '';
        final vkn = item['vkn']?.toString() ?? '';
        final tutar = DatabaseService.parsePara(item['tutar']);

        if (faturaNo.isNotEmpty && kategori == 'TICARI_CARI') {
          final varOlan = await DatabaseService.instance.mukerrerFaturaKontrol(
            faturaNo: faturaNo,
            firmaId: firmaId,
            vkn: vkn,
            tutar: tutar,
          );
          if (varOlan != null) {
            item['is_duplicate'] = true;
            item['duplicate_info'] =
                "Bu fatura daha önce işlenmiş (Kayıt ID: #${varOlan['id']}, Evrak: ${varOlan['fatura_no']})";
          }
        }

        final okunanUnvan = item['cari_unvan']?.toString().trim() ?? '';
        if (kategori == 'PERSONEL') {
          item['cari_unvan'] = okunanUnvan
              .replaceAll(
                RegExp(r'^(işçi|isci|personel)\s+', caseSensitive: false),
                '',
              )
              .trim();
          item['cari_adaylar'] = null;
        } else if (kategori == 'ISLETME_GIDERI') {
          item['cari_unvan'] = 'İşletme Giderleri';
          item['cari_adaylar'] = null;
        } else if (okunanUnvan.isNotEmpty) {
          final adaylar = await DatabaseService.instance.benzerCarileriBul(
            gelenUnvan: okunanUnvan,
            vkn: vkn,
            firmaId: firmaId,
          );
          item['cari_adaylar'] = [
            {'id': -1, 'unvan': '➕ Yeni Cari Kartı Oluştur ($okunanUnvan)'},
            ...adaylar,
          ];
          item['cari_unvan'] = adaylar.isEmpty
              ? '➕ Yeni Cari Kartı Oluştur ($okunanUnvan)'
              : adaylar.first['unvan'];
        }
      }
    }

    setState(() {
      _messages.add(
        ChatMessage(
          isUser: false,
          text: response['reply']?.toString() ?? '',
          actionItems: items.isNotEmpty ? items : null,
        ),
      );
      _isProcessing = false;
    });
  }

  // 🚨 STOK ONAYLAMA METODU EKLENDİ
  Future<void> _stokOnaylaVeKaydet(Map<String, dynamic> item) async {
    setState(() {
      item['is_saved'] = true;
    });
    final firmaId = ref.read(firmaProvider).aktifFirmaId;

    final action = item['action_type'];
    final stokAdi = item['stok_adi']?.toString() ?? 'Yeni Ürün';
    final alis = (item['alis_fiyati'] as num?)?.toDouble();
    final satis = (item['satis_fiyati'] as num?)?.toDouble();
    final miktar = (item['miktar'] as num?)?.toDouble() ?? 0.0;

    int? stokId = item['secili_stok_id'];

    if (action == 'YENI_STOK_KARTI' || stokId == null) {
      final stokKodu =
          'STK-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      stokId = await DatabaseService.instance.stokKartiEkle(
        firmaId: firmaId,
        stokKodu: stokKodu,
        stokAdi: stokAdi,
        birim: 'Adet',
        kdvOrani: (item['kdv_orani'] as num?)?.toDouble() ?? 20.0,
        alisFiyati: alis ?? 0.0,
        satisFiyati: satis ?? 0.0,
        kritikSeviye: 10.0,
      );
      if (miktar > 0) {
        await DatabaseService.instance.stokHareketiEkle(
          firmaId: firmaId,
          stokId: stokId,
          depoId: 1,
          hareketTipi: 'GIRIS',
          miktar: miktar,
          birimFiyat: alis ?? satis ?? 0.0,
          tarih: DateTime.now().toIso8601String().substring(0, 10),
          aciklama: 'AI Asistan Stok Girişi',
        );
      }
    } else {
      if (action == 'FIYAT_GUNCELLE') {
        await DatabaseService.instance.stokKartiGuncelle(
          firmaId: firmaId,
          stokId: stokId,
          alisFiyati: alis,
          satisFiyati: satis,
        );
      } else if (action == 'STOK_GIRIS' || action == 'STOK_CIKIS') {
        if (miktar > 0) {
          final tip = action == 'STOK_CIKIS' ? 'CIKIS' : 'GIRIS';
          await DatabaseService.instance.stokHareketiEkle(
            firmaId: firmaId,
            stokId: stokId,
            depoId: 1,
            hareketTipi: tip,
            miktar: miktar,
            birimFiyat: alis ?? satis ?? 0.0,
            tarih: DateTime.now().toIso8601String().substring(0, 10),
            aciklama: 'AI Asistan İşlemi',
          );
        }
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("📦 Stok işlemi tamamlandı.")),
      );
    }
  }

  Future<void> _onaylaVeKaydet(Map<String, dynamic> item) async {
    final faturaNo = item['fatura_no']?.toString().trim() ?? '';
    if (_kaydedilenFaturaNolari.contains(faturaNo) && faturaNo.isNotEmpty) {
      return;
    }
    setState(() {
      if (faturaNo.isNotEmpty) {
        _kaydedilenFaturaNolari.add(faturaNo);
      }
      item['is_saved'] = true;
    });

    final firmaId = ref.read(firmaProvider).aktifFirmaId;
    final kategori = (item['islem_kategorisi'] ?? '').toString().toUpperCase();
    String hedefCariUnvan = item['cari_unvan']?.toString() ?? 'Genel Cari';

    if (kategori == 'ISLETME_GIDERI') {
      hedefCariUnvan = 'İşletme Giderleri';
    }
    int? olusturulanCariId;

    if (hedefCariUnvan.contains('(') && hedefCariUnvan.contains(')')) {
      final basParantez = hedefCariUnvan.indexOf('(');
      final sonParantez = hedefCariUnvan.lastIndexOf(')');
      if (basParantez != -1 && sonParantez != -1) {
        hedefCariUnvan = hedefCariUnvan
            .substring(basParantez + 1, sonParantez)
            .trim();
      }
    }

    if (kategori == 'TICARI_CARI' &&
        item['cari_unvan']?.toString().contains('➕') == true) {
      final db = await DatabaseService.instance.getDatabase(firmaId: firmaId);
      final varMi = await db.query(
        'cariler',
        where: 'unvan = ?',
        whereArgs: [hedefCariUnvan],
      );
      if (varMi.isNotEmpty) {
        olusturulanCariId = varMi.first['id'] as int;
      } else {
        olusturulanCariId = await db.insert('cariler', {
          'unvan': hedefCariUnvan,
          'vergi_no': item['vkn'] ?? '',
          'bakiye': 0.0,
          'grup_adi': DatabaseService.grupAdiCikar(hedefCariUnvan),
          'sehir': 'Genel',
          'olusturma_tarihi': DateTime.now().toIso8601String(),
        });
      }
    }

    final isCekSenet =
        item['action_type'] == 'CEK_SENET_GIRISI' ||
        item['islem_kategorisi'] == 'CEK_SENET' ||
        item['selected_payment'] == 'CEK' ||
        item['selected_payment'] == 'SENET';

    if (isCekSenet) {
      final evrakNumarasi = (item['evrak_no']?.toString().isNotEmpty == true)
          ? item['evrak_no'].toString()
          : (faturaNo.isNotEmpty
                ? faturaNo
                : 'EVR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
      final tutar = DatabaseService.parsePara(item['tutar']);
      final rawEvrakTuru = item['evrak_turu']?.toString().toUpperCase() ?? '';

      final bool isAlinan =
          rawEvrakTuru.contains('MUSTERI') || item['borc_mu'] == true;
      final bool isSenet =
          rawEvrakTuru.contains('SENET') || item['selected_payment'] == 'SENET';
      final String evrakTuru = isSenet
          ? (isAlinan ? 'MUSTERI_SENEDI' : 'BORC_SENEDI')
          : (isAlinan ? 'MUSTERI_CEKI' : 'BORC_CEKI');

      List<Map<String, dynamic>> yevmiye = [];
      final rawYevmiye = item['yevmiye_kaydi'];
      if (rawYevmiye is List) {
        yevmiye = rawYevmiye
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (rawYevmiye is Map) {
        yevmiye = [Map<String, dynamic>.from(rawYevmiye)];
      }

      if (yevmiye.isEmpty && tutar > 0) {
        if (isAlinan) {
          yevmiye = [
            {
              'kod': isSenet ? '121' : '101',
              'ad': isSenet ? 'Alacak Senetleri' : 'Alınan Çekler',
              'borc': tutar,
              'alacak': 0.0,
            },
            {
              'kod': '120',
              'ad': 'Alıcılar Hesabı ($hedefCariUnvan)',
              'borc': 0.0,
              'alacak': tutar,
            },
          ];
        } else {
          yevmiye = [
            {
              'kod': '320',
              'ad': 'Satıcılar Hesabı ($hedefCariUnvan)',
              'borc': tutar,
              'alacak': 0.0,
            },
            {
              'kod': isSenet ? '321' : '103',
              'ad': isSenet
                  ? 'Borç Senetleri'
                  : 'Verilen Çekler ve Ödeme Emirleri (-)',
              'borc': 0.0,
              'alacak': tutar,
            },
          ];
        }
      }

      await DatabaseService.instance.cekSenetKaydet(
        firmaId: firmaId,
        cariId: olusturulanCariId,
        kesideci: hedefCariUnvan,
        vkn: item['vkn']?.toString() ?? '', // 🚨 EKSİK OLAN VKN İLETİMİ EKLENDİ
        evrakTuru: evrakTuru,
        evrakNo: evrakNumarasi,
        bankaAdi: item['banka_adi']?.toString() ?? 'Banka Belirtilmedi',
        tutar: tutar,
        vadeTarihi:
            item['vade_tarihi']?.toString() ??
            DateTime.now().toIso8601String().substring(0, 10),
        belgeYolu: item['attached_file_path']?.toString(),
        yevmiyeMaddeleri: yevmiye,
      );
    } else {
      List<Map<String, dynamic>> yevmiye =
          (item['yevmiye_kaydi'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      final secilenOdeme = item['selected_payment']?.toString() ?? 'NAKİT';
      final tutar = DatabaseService.parsePara(item['tutar']);
      if (yevmiye.isEmpty && kategori == 'PERSONEL' && tutar > 0) {
        yevmiye = [
          {
            'kod': '196',
            'ad': 'Personel Avansları ($hedefCariUnvan)',
            'borc': tutar,
            'alacak': 0.0,
          },
          {
            'kod': secilenOdeme == 'NAKİT' ? '100' : '102',
            'ad': secilenOdeme == 'NAKİT' ? 'Kasa Hesabı' : 'Banka Hesabı',
            'borc': 0.0,
            'alacak': tutar,
          },
        ];
      }
      if (yevmiye.isEmpty && kategori == 'ISLETME_GIDERI' && tutar > 0) {
        String karsiKod = '100';
        String karsiAd = 'Kasa Hesabı';
        if (secilenOdeme == 'HAVALE') {
          karsiKod = '102';
          karsiAd = 'Banka Hesabı';
        } else if (secilenOdeme == 'KREDİ_KARTI') {
          karsiKod = '108';
          karsiAd = 'Kredi Kartı Hesabı';
        }
        final kdvTutari = double.parse(
          (tutar - (tutar / 1.20)).toStringAsFixed(2),
        );
        final matrah = double.parse((tutar - kdvTutari).toStringAsFixed(2));
        yevmiye = [
          {
            'kod': '770',
            'ad': 'Genel Yönetim Giderleri',
            'borc': matrah,
            'alacak': 0.0,
          },
          {
            'kod': '191',
            'ad': 'İndirilecek KDV (%20)',
            'borc': kdvTutari,
            'alacak': 0.0,
          },
          {'kod': karsiKod, 'ad': karsiAd, 'borc': 0.0, 'alacak': tutar},
        ];
      }

      await DatabaseService.instance.islemKaydet(
        unvan: hedefCariUnvan,
        islemTuru: (kategori == 'PERSONEL')
            ? 'PERSONEL_AVANS'
            : (kategori == 'ISLETME_GIDERI'
                  ? 'GİDER_FİŞİ'
                  : 'CARİ_FATURA_KAYDI'),
        tutar: tutar,
        borcMu: item['borc_mu'] == true,
        aciklama:
            item['summary']?.toString() ??
            (kategori == 'ISLETME_GIDERI'
                ? 'İşletme Gider Fişi'
                : '$hedefCariUnvan İşlem Kaydı'),
        odemeYontemi: secilenOdeme,
        faturaNo: faturaNo,
        yevmiyeMaddeleri: yevmiye,
        vkn: item['vkn']?.toString() ?? '', // 🚨 EKSİK OLAN VKN İLETİMİ EKLENDİ
        belgeYolu: item['attached_file_path']?.toString(),
        firmaId: firmaId,
      );
    }
    ref.read(ledgerProvider.notifier).yenile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ $hedefCariUnvan işlemi başarıyla kaydedildi."),
        ),
      );
      ref.read(ledgerProvider.notifier).yenile();
      ref.read(yevmiyeProvider.notifier).yenile();
      ref.read(carilerProvider.notifier).yenile();
    }
  }

  void _iptalEt(Map<String, dynamic> item) {
    setState(() {
      item['is_cancelled'] = true;
    });
  }

  Future<void> _kartaDosyaEkle(Map<String, dynamic> item) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'jpeg', 'pdf'],
    );
    if (result.isNotEmpty && result.first.path != null) {
      setState(() {
        item['attached_file_path'] = result.first.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _panodanYapistir,
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragDone: (detail) {
            setState(() {
              _isDragging = false;
              for (final xFile in detail.files) {
                final ext = xFile.path.toLowerCase();
                if (ext.endsWith('.pdf') ||
                    ext.endsWith('.png') ||
                    ext.endsWith('.jpg') ||
                    ext.endsWith('.jpeg')) {
                  _selectedFiles.add(File(xFile.path));
                }
              }
            });
          },
          onDragEntered: (detail) => setState(() => _isDragging = true),
          onDragExited: (detail) => setState(() => _isDragging = false),
          child: Scaffold(
            backgroundColor: const Color(0xFFFAFAFA),
            body: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(50),
                                    ),
                                    child: const Icon(
                                      Icons.file_upload_outlined,
                                      size: 48,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "LedgerArc AI Asistan Hazır",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Fatura, fiş veya çek dosyasını buraya sürükleyin\nveya Ctrl + V ile ekran görüntüsü / belge yapıştırın.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final gecerliAksiyonlar =
                                    (msg.actionItems ?? [])
                                        .where(
                                          (item) =>
                                              item is Map<String, dynamic> &&
                                              item['is_action'] == true &&
                                              ((item['cari_unvan'] != null &&
                                                      item['cari_unvan']
                                                          .toString()
                                                          .trim()
                                                          .isNotEmpty &&
                                                      item['cari_unvan']
                                                              .toString()
                                                              .toLowerCase() !=
                                                          'null') ||
                                                  item['islem_kategorisi'] ==
                                                      'STOK_DEPO_ISLEMI'),
                                        )
                                        .toList();

                                if (!msg.isUser &&
                                    msg.text.trim().isEmpty &&
                                    gecerliAksiyonlar.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Align(
                                  alignment: msg.isUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    constraints: const BoxConstraints(
                                      maxWidth: 650,
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: msg.isUser
                                          ? const Color(0xFF111111)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (msg.files != null &&
                                            msg.files!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: msg.files!.map((f) {
                                                final isim = f.path
                                                    .split(
                                                      Platform.pathSeparator,
                                                    )
                                                    .last;
                                                return Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.15,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.picture_as_pdf,
                                                        size: 14,
                                                        color: Colors.white70,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        isim.length > 25
                                                            ? "${isim.substring(0, 22)}..."
                                                            : isim,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        if (msg.text.trim().isNotEmpty)
                                          Text(
                                            msg.text,
                                            style: TextStyle(
                                              color: msg.isUser
                                                  ? Colors.white
                                                  : const Color(0xFF111827),
                                              fontSize: 13.5,
                                            ),
                                          ),
                                        if (gecerliAksiyonlar.isNotEmpty)
                                          ...gecerliAksiyonlar.map((item) {
                                            final isDup =
                                                item['is_duplicate'] == true;
                                            final kategori =
                                                (item['islem_kategorisi'] ?? '')
                                                    .toString()
                                                    .toUpperCase();
                                            final isCek =
                                                item['action_type'] ==
                                                'CEK_SENET_GIRISI';
                                            final isStok =
                                                kategori == 'STOK_DEPO_ISLEMI';
                                            final tutar =
                                                (item['tutar'] as num?)
                                                    ?.toDouble() ??
                                                0.0;

                                            return Container(
                                              margin: const EdgeInsets.only(
                                                top: 10,
                                              ),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: isDup
                                                    ? const Color(0xFFFEF2F2)
                                                    : const Color(0xFFF9FAFB),
                                                border: Border.all(
                                                  color: isDup
                                                      ? Colors.red
                                                      : const Color(0xFFE5E7EB),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (isDup)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFFEE2E2,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0xFFEF4444,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .warning_amber_rounded,
                                                            color: Color(
                                                              0xFFDC2626,
                                                            ),
                                                            size: 18,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              item['duplicate_info']
                                                                      ?.toString() ??
                                                                  "⚠️ Bu fatura daha önce sisteme işlenmiş!",
                                                              style: const TextStyle(
                                                                color: Color(
                                                                  0xFF991B1B,
                                                                ),
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),

                                                  Text(
                                                    item['summary']
                                                            ?.toString() ??
                                                        (isStok
                                                            ? 'Depo Stok İşlemi'
                                                            : (isCek
                                                                  ? 'Çek Giriş Bordrosu'
                                                                  : (kategori ==
                                                                            'PERSONEL'
                                                                        ? 'Personel Avans Ödemesi'
                                                                        : (kategori == 'ISLETME_GIDERI'
                                                                              ? 'İşletme Gider Fişi'
                                                                              : 'Fatura Kaydı')))),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),

                                                  if (isStok) ...[
                                                    Text(
                                                      "Ürün: ${item['stok_adi']} • İşlem Miktarı: ${item['miktar'] ?? '-'}",
                                                      style: const TextStyle(
                                                        fontSize: 12.5,
                                                        color: Color(
                                                          0xFF374151,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    if (item['action_type'] !=
                                                            'YENI_STOK_KARTI' &&
                                                        item['stok_adaylar'] !=
                                                            null)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFFFFBEB,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFFDE68A,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const Text(
                                                              "Eşleşen Stok Kartı:",
                                                              style: TextStyle(
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFFB45309,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            DropdownButtonFormField<
                                                              int
                                                            >(
                                                              initialValue:
                                                                  item['secili_stok_id'],
                                                              isExpanded: true,
                                                              decoration: const InputDecoration(
                                                                isDense: true,
                                                                contentPadding:
                                                                    EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          10,
                                                                      vertical:
                                                                          8,
                                                                    ),
                                                                border:
                                                                    OutlineInputBorder(),
                                                              ),
                                                              items: (item['stok_adaylar'] as List).map<DropdownMenuItem<int>>((
                                                                s,
                                                              ) {
                                                                return DropdownMenuItem<
                                                                  int
                                                                >(
                                                                  value:
                                                                      s['id'],
                                                                  child: Text(
                                                                    s['stok_adi']
                                                                        .toString(),
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                );
                                                              }).toList(),
                                                              onChanged:
                                                                  item['is_saved'] ==
                                                                      true
                                                                  ? null
                                                                  : (val) {
                                                                      setState(
                                                                        () => item['secili_stok_id'] =
                                                                            val,
                                                                      );
                                                                    },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ] else ...[
                                                    Text(
                                                      "${kategori == 'PERSONEL' ? 'Personel' : 'Cari'}: ${item['cari_unvan']} • Tutar: ${fmt.format(tutar)}",
                                                      style: const TextStyle(
                                                        fontSize: 12.5,
                                                        color: Color(
                                                          0xFF374151,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 10),
                                                    if (kategori ==
                                                            'PERSONEL' ||
                                                        kategori ==
                                                            'ISLETME_GIDERI')
                                                      Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 10,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFEFF6FF,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFBFDBFE,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              kategori ==
                                                                      'ISLETME_GIDERI'
                                                                  ? Icons
                                                                        .receipt_long_outlined
                                                                  : Icons
                                                                        .badge_outlined,
                                                              size: 18,
                                                              color:
                                                                  const Color(
                                                                    0xFF2563EB,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                kategori == 'ISLETME_GIDERI'
                                                                    ? "İşletme Gideri (770 Genel Yönetim Giderleri)"
                                                                    : "Personel Kaydı: ${item['cari_unvan']} (196 Personel Avansları)",
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Color(
                                                                    0xFF1E40AF,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    else if (item['cari_adaylar'] !=
                                                        null)
                                                      Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 10,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFFFFBEB,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFFDE68A,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .store_mall_directory_outlined,
                                                                  size: 16,
                                                                  color: Color(
                                                                    0xFFD97706,
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  width: 6,
                                                                ),
                                                                Text(
                                                                  "İşlem Yapılacak Cari Hesap:",
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        11.5,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Color(
                                                                      0xFFB45309,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            DropdownButtonFormField<
                                                              String
                                                            >(
                                                              initialValue:
                                                                  item['cari_unvan']
                                                                      ?.toString(),
                                                              isExpanded: true,
                                                              decoration: const InputDecoration(
                                                                isDense: true,
                                                                contentPadding:
                                                                    EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          10,
                                                                      vertical:
                                                                          8,
                                                                    ),
                                                                border:
                                                                    OutlineInputBorder(),
                                                              ),
                                                              items: (item['cari_adaylar'] as List).map<DropdownMenuItem<String>>((
                                                                c,
                                                              ) {
                                                                final unvan =
                                                                    c['unvan']
                                                                        .toString();
                                                                final isYeni = unvan
                                                                    .startsWith(
                                                                      '➕',
                                                                    );
                                                                return DropdownMenuItem<
                                                                  String
                                                                >(
                                                                  value: unvan,
                                                                  child: Text(
                                                                    unvan,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      fontWeight:
                                                                          isYeni
                                                                          ? FontWeight.bold
                                                                          : FontWeight.normal,
                                                                      color:
                                                                          isYeni
                                                                          ? const Color(
                                                                              0xFF059669,
                                                                            )
                                                                          : Colors.black87,
                                                                    ),
                                                                  ),
                                                                );
                                                              }).toList(),
                                                              onChanged:
                                                                  item['is_saved'] ==
                                                                      true
                                                                  ? null
                                                                  : (val) {
                                                                      setState(() {
                                                                        item['cari_unvan'] =
                                                                            val;
                                                                      });
                                                                    },
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    if (isCek)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 9,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFECFDF5,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFA7F3D0,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(
                                                              Icons
                                                                  .account_balance_wallet_outlined,
                                                              size: 18,
                                                              color: Color(
                                                                0xFF059669,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                "${item['banka_adi'] ?? 'Banka'} • Evrak: ${item['evrak_no'] ?? item['fatura_no'] ?? '-'} • Vade: ${item['vade_tarihi'] ?? '-'}",
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Color(
                                                                    0xFF047857,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    else
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFD1D5DB,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(
                                                              Icons.payment,
                                                              size: 16,
                                                              color: Color(
                                                                0xFF4B5563,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            const Text(
                                                              "Ödeme Şekli:",
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 10,
                                                            ),
                                                            Expanded(
                                                              child: DropdownButtonHideUnderline(
                                                                child: DropdownButton<String>(
                                                                  isDense: true,
                                                                  value:
                                                                      item['selected_payment'] ?? 'AÇIK_HESAP',
                                                                  items: const [
                                                                    DropdownMenuItem(
                                                                      value: 'NAKİT',
                                                                      child: Text(
                                                                        "💵 Nakit",
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    DropdownMenuItem(
                                                                      value: 'HAVALE',
                                                                      child: Text(
                                                                        "🏦 Havale/Banka",
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    DropdownMenuItem(
                                                                      value: 'AÇIK_HESAP',
                                                                      child: Text(
                                                                        "⏳ Vadeli/Açık Hesap",
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    DropdownMenuItem(
                                                                      value: 'KREDİ_KARTI',
                                                                      child: Text(
                                                                        "💳 Kredi Kartı",
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                  onChanged:
                                                                      item['is_saved'] ==
                                                                              true ||
                                                                          item['is_cancelled'] ==
                                                                              true
                                                                      ? null
                                                                      : (yeniDeger) {
                                                                          setState(() {
                                                                            item['selected_payment'] =
                                                                                yeniDeger;
                                                                          });
                                                                        },
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],

                                                  const SizedBox(height: 12),
                                                  if (item['attached_file_path'] !=
                                                      null)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 6,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            bottom: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFEFF6FF,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0xFFBFDBFE,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Icon(
                                                            Icons.attachment,
                                                            size: 16,
                                                            color: Color(
                                                              0xFF2563EB,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              item['attached_file_path']
                                                                  .toString()
                                                                  .split(
                                                                    Platform
                                                                        .pathSeparator,
                                                                  )
                                                                  .last,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 11.5,
                                                                color: Color(
                                                                  0xFF1E40AF,
                                                                ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                          if (item['is_saved'] !=
                                                                  true &&
                                                              item['is_cancelled'] !=
                                                                  true)
                                                            InkWell(
                                                              onTap: () => setState(
                                                                () =>
                                                                    item['attached_file_path'] =
                                                                        null,
                                                              ),
                                                              child: const Icon(
                                                                Icons.close,
                                                                size: 14,
                                                                color: Color(
                                                                  0xFFDC2626,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    )
                                                  else if (item['is_saved'] !=
                                                          true &&
                                                      item['is_cancelled'] !=
                                                          true)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 10,
                                                          ),
                                                      child: OutlinedButton.icon(
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor:
                                                              const Color(
                                                                0xFF374151,
                                                              ),
                                                          side:
                                                              const BorderSide(
                                                                color: Color(
                                                                  0xFFD1D5DB,
                                                                ),
                                                              ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 6,
                                                              ),
                                                          minimumSize:
                                                              Size.zero,
                                                        ),
                                                        icon: const Icon(
                                                          Icons.attach_file,
                                                          size: 14,
                                                        ),
                                                        label: const Text(
                                                          "Dekont / Çek Görseli Ekle",
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                        onPressed: () =>
                                                            _kartaDosyaEkle(
                                                              item
                                                                  as Map<
                                                                    String,
                                                                    dynamic
                                                                  >,
                                                            ),
                                                      ),
                                                    ),

                                                  Row(
                                                    children: [
                                                      if (item['is_cancelled'] ==
                                                          true)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 14,
                                                                vertical: 8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFFFEE2E2,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                          child: const Text(
                                                            "❌ İşlem İptal Edildi",
                                                            style: TextStyle(
                                                              color: Color(
                                                                0xFFDC2626,
                                                              ),
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        )
                                                      else ...[
                                                        FilledButton(
                                                          style: FilledButton.styleFrom(
                                                            backgroundColor:
                                                                item['is_saved'] ==
                                                                    true
                                                                ? Colors.green
                                                                : const Color(
                                                                    0xFF111111,
                                                                  ),
                                                          ),
                                                          onPressed:
                                                              item['is_saved'] ==
                                                                  true
                                                              ? null
                                                              : () {
                                                                  if (isStok) {
                                                                    _stokOnaylaVeKaydet(
                                                                      item
                                                                          as Map<
                                                                            String,
                                                                            dynamic
                                                                          >,
                                                                    );
                                                                  } else {
                                                                    _onaylaVeKaydet(
                                                                      item
                                                                          as Map<
                                                                            String,
                                                                            dynamic
                                                                          >,
                                                                    );
                                                                  }
                                                                },
                                                          child: Text(
                                                            item['is_saved'] ==
                                                                    true
                                                                ? "✅ Kaydedildi"
                                                                : (isStok
                                                                      ? "Stok İşlemini Onayla"
                                                                      : (isDup
                                                                            ? "Yine de Onayla"
                                                                            : "Onayla ve Kaydet")),
                                                          ),
                                                        ),
                                                        if (item['is_saved'] !=
                                                            true) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          OutlinedButton(
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor:
                                                                  const Color(
                                                                    0xFFDC2626,
                                                                  ),
                                                              side: const BorderSide(
                                                                color: Color(
                                                                  0xFFFCA5A5,
                                                                ),
                                                              ),
                                                            ),
                                                            onPressed: () =>
                                                                _iptalEt(
                                                                  item
                                                                      as Map<
                                                                        String,
                                                                        dynamic
                                                                      >,
                                                                ),
                                                            child: const Text(
                                                              "İptal Et",
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (_isProcessing)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Gemini belgeyi analiz ediyor...",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedFiles.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF3F4F6),
                          border: Border(
                            top: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedFiles.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final file = _selectedFiles[index];
                              final isim = file.path
                                  .split(Platform.pathSeparator)
                                  .last;
                              return Container(
                                padding: const EdgeInsets.only(
                                  left: 10,
                                  right: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.description,
                                      size: 16,
                                      color: Color(0xFF4B5563),
                                    ),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 180,
                                      ),
                                      child: Text(
                                        isim,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedFiles.removeAt(index);
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.white,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.attach_file),
                            tooltip: "Dosya Seç",
                            onPressed: _dosyaSec,
                          ),
                          IconButton(
                            icon: Icon(
                              _recordingState ? Icons.stop : Icons.mic,
                              color: _recordingState
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF4B5563),
                            ),
                            tooltip: _recordingState
                                ? "Kaydı Durdur ve Gönder"
                                : "Sesli Mesaj Kaydet",
                            onPressed: _isProcessing ? null : _mikrofonTetikle,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) {
                                if (!_isProcessing) {
                                  _gonder();
                                }
                              },
                              decoration: const InputDecoration(
                                hintText: "Mesaj yazın, belge sürükleyin veya Ctrl + V ile yapıştırın...",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: Color(0xFF111111),
                            ),
                            onPressed: _isProcessing ? null : _gonder,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_isDragging)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF2563EB),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.file_download_outlined,
                                color: Color(0xFF2563EB),
                                size: 30,
                              ),
                              SizedBox(width: 12),
                              Text(
                                "Belgeyi yüklemek için buraya bırakın",
                                style: TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
