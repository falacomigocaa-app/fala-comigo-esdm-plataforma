import 'package:hive/hive.dart';

import '../../../core/services/secure_box_service.dart';
import '../domain/models/sincronizacao_queue_model.dart';

const sincronizacaoQueueBoxName = 'sincronizacao_queue_box';

class SincronizacaoQueueStore {
  SincronizacaoQueueStore._();

  static Future<Box<SincronizacaoQueueModel>> _box() async {
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(SincronizacaoQueueModelAdapter());
    }
    if (Hive.isBoxOpen(sincronizacaoQueueBoxName)) {
      return Hive.box<SincronizacaoQueueModel>(sincronizacaoQueueBoxName);
    }
    return SecureBoxService.openSecureBox<SincronizacaoQueueModel>(
      sincronizacaoQueueBoxName,
    );
  }

  static Future<void> enqueue(SincronizacaoQueueModel item) async {
    final box = await _box();
    await box.put(item.id, item);
  }

  static Future<List<SincronizacaoQueueModel>> loadPending() async {
    final box = await _box();
    return box.values.where((item) => !item.processado).toList();
  }

  static Future<void> markProcessed(SincronizacaoQueueModel item) async {
    final box = await _box();
    item.processado = true;
    await box.put(item.id, item);
  }
}
