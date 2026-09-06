import '../models/yevmiye_kaydi.dart';
import '../services/database_service.dart';

class YevmiyeRepository {
  final DatabaseService _db = DatabaseService.instance;

  Future<List<YevmiyeKaydi>> getYevmiyeKayitlari(int firmaId) async {
    final db = await _db.getDatabase(firmaId: firmaId);
    final rows = await db.query('yevmiye_kayitlari', orderBy: 'id DESC');
    // Kuruşlar burada YevmiyeKaydi.fromMap ile otomatik olarak TL'ye dönüştü!
    return rows.map((r) => YevmiyeKaydi.fromMap(r)).toList();
  }
}
