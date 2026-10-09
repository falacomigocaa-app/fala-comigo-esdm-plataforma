import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/media_storage_service.dart';
import '../../domain/models/transition_alert.dart';

const String transitionAlertsBoxName = 'transition_alerts';

final transitionAlertsBoxProvider = Provider<Box>((ref) {
  return Hive.box(transitionAlertsBoxName);
});

final transitionAlertsListProvider =
    StateNotifierProvider<TransitionAlertsNotifier, List<TransitionAlert>>((
  ref,
) {
  final box = ref.watch(transitionAlertsBoxProvider);
  return TransitionAlertsNotifier(box);
});

class TransitionAlertsNotifier extends StateNotifier<List<TransitionAlert>> {
  final Box _box;

  TransitionAlertsNotifier(this._box) : super(_loadAll(_box));

  static List<TransitionAlert> _loadAll(Box box) {
    return box.values
        .map(
          (e) => TransitionAlert.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<TransitionAlert> addAlert(TransitionAlert alert) async {
    alert.syncState = 'pending';
    alert.syncError = null;
    await _box.put(alert.id, alert.toMap());
    state = _loadAll(_box);
    return alert;
  }

  Future<void> updateAlert(TransitionAlert alert) async {
    alert.syncState = 'pending';
    alert.syncError = null;
    alert.updatedAt = DateTime.now();
    await _box.put(alert.id, alert.toMap());
    state = _loadAll(_box);
  }

  Future<void> removeAlert(String id) async {
    final raw = _box.get(id);
    await _box.delete(id);
    if (raw is Map) {
      final alert = TransitionAlert.fromMap(Map<String, dynamic>.from(raw));
      final audioPath = alert.recordedAudioPath;
      if (audioPath != null) {
        await MediaStorageService.deleteFile(audioPath);
      }
    }
    state = _loadAll(_box);
  }

  /// Gera um ID numérico único, exigido pelo flutter_local_notifications
  /// (que usa inteiros para identificar cada notificação agendada).
  int generateNotificationId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(1000000000);
  }

  String generateId() => const Uuid().v4();
}
