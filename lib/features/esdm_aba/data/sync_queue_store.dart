import 'package:hive/hive.dart';

import '../../../core/services/secure_box_service.dart';
import '../domain/models/sync_item.dart';

const syncQueueBoxName = 'sync_queue_box';

/// Persiste a fila em uma box Hive protegida por AES-256.
class SyncQueueStore {
  SyncQueueStore._();

  static Future<Box<SyncItem>> _box() async {
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(SyncQueueAdapter());
    }
    if (Hive.isBoxOpen(syncQueueBoxName)) {
      return Hive.box<SyncItem>(syncQueueBoxName);
    }
    return SecureBoxService.openSecureBox<SyncItem>(syncQueueBoxName);
  }

  static Future<void> enqueue(SyncItem item) async {
    final box = await _box();
    await box.put(item.id, item);
  }

  static Future<List<SyncItem>> pending() async {
    final box = await _box();
    final items = box.values.toList()
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return items;
  }

  static Future<void> remove(SyncItem item) async {
    final box = await _box();
    await box.delete(item.id);
  }

  static Future<void> incrementAttempts(SyncItem item) async {
    final box = await _box();
    item.attempts += 1;
    await box.put(item.id, item);
  }
}
