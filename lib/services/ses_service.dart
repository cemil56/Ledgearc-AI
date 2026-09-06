// lib/services/ses_service.dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class SesService {
  SesService._();
  static final SesService instance = SesService._();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentRecordingPath;

  bool get isRecording => _isRecording;

  // Mikrofondan Ses Kaydını Başlat
  Future<bool> baslat() async {
    try {
      // Zaten kayıttaysa önce durdur
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }

      // Windows'ta izin kontrolü
      final hasPerm = await _recorder.hasPermission();
      if (!hasPerm) {
        print("Mikrofon izni verilmedi!");
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}${Platform.pathSeparator}ses_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Windows için en kararlı config
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      return true;
    } catch (e) {
      print("Ses kaydı başlatma hatası: $e");
      _isRecording = false;
      return false;
    }
  }

  // Ses Kaydını Bitir ve Ses Dosyasını Döndür
  Future<File?> durdur() async {
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      if (path != null) {
        final f = File(path);
        if (await f.exists() && await f.length() > 0) {
          return f;
        }
      }
    } catch (e) {
      print("Ses kaydı durdurma hatası: $e");
      _isRecording = false;
    }
    return null;
  }
}
