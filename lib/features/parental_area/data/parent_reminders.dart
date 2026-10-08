import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/secure_box_service.dart';
import '../../../core/services/parental_session_service.dart';

const _boxName = 'parent_reminders';

@immutable
class ParentReminder {
  final String id;
  final String label;
  final int hour;
  final int minute;
  final List<int> weekdays;
  final int notificationId;

  const ParentReminder({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.notificationId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'notificationId': notificationId,
      };

  factory ParentReminder.fromMap(Map<dynamic, dynamic> map) => ParentReminder(
        id: '${map['id'] ?? ''}',
        label: '${map['label'] ?? 'Lembrete da rotina'}',
        hour: (map['hour'] as int?) ?? 8,
        minute: (map['minute'] as int?) ?? 0,
        weekdays: (map['weekdays'] as List?)?.whereType<int>().toList() ?? [],
        notificationId: (map['notificationId'] as int?) ?? 0,
      );
}

class ParentReminderStore {
  ParentReminderStore._();

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return SecureBoxService.openSecureBox(_boxName);
  }

  static Future<List<ParentReminder>> load() async {
    ParentalSessionService.requireAuthenticated();
    final box = await _box();
    return box.values
        .whereType<Map>()
        .map(ParentReminder.fromMap)
        .where((reminder) => reminder.id.isNotEmpty)
        .toList();
  }

  static Future<void> save(List<ParentReminder> reminders) async {
    ParentalSessionService.requireAuthenticated();
    final box = await _box();
    await box.clear();
    for (final reminder in reminders) {
      await box.put(reminder.id, reminder.toMap());
    }
  }
}
