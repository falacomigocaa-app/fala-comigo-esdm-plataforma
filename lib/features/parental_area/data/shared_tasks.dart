import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/secure_box_service.dart';
import '../../../core/services/parental_session_service.dart';

const _taskBoxName = 'shared_tasks';
const _syncBoxName = 'shared_task_sync_queue';

enum SharedTaskStatus {
  pending,
  inProgress,
  completed,
  partiallyCompleted,
  needsHelp,
  declined,
  cancelled,
}

enum TaskAcceptanceStatus { notRequired, pending, accepted, declined }

@immutable
class SharedTaskEvent {
  final String type;
  final String actor;
  final String? note;
  final DateTime occurredAt;

  const SharedTaskEvent({
    required this.type,
    required this.actor,
    required this.note,
    required this.occurredAt,
  });

  Map<String, dynamic> toMap() => {
        'type': type,
        'actor': actor,
        'note': note,
        'occurredAt': occurredAt.toIso8601String(),
      };

  factory SharedTaskEvent.fromMap(Map<dynamic, dynamic> map) => SharedTaskEvent(
        type: '${map['type'] ?? 'atualização'}',
        actor: '${map['actor'] ?? 'Família'}',
        note: map['note'] == null ? null : '${map['note']}',
        occurredAt: DateTime.tryParse('${map['occurredAt']}') ?? DateTime.now(),
      );
}

@immutable
class SharedTask {
  final String id;
  final String title;
  final String description;
  final String createdBy;
  final String assignedTo;
  final String organizationName;
  final String recipientRole;
  final String contextLabel;
  final DateTime dueAt;
  final bool reminderEnabled;
  final SharedTaskStatus status;
  final TaskAcceptanceStatus acceptance;
  final String? feedback;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SharedTaskEvent> events;

  const SharedTask({
    required this.id,
    required this.title,
    required this.description,
    required this.createdBy,
    required this.assignedTo,
    required this.organizationName,
    required this.recipientRole,
    required this.contextLabel,
    required this.dueAt,
    required this.reminderEnabled,
    required this.status,
    required this.acceptance,
    required this.feedback,
    required this.createdAt,
    required this.updatedAt,
    required this.events,
  });

  SharedTask copyWith({
    SharedTaskStatus? status,
    TaskAcceptanceStatus? acceptance,
    String? feedback,
    DateTime? updatedAt,
    List<SharedTaskEvent>? events,
  }) =>
      SharedTask(
        id: id,
        title: title,
        description: description,
        createdBy: createdBy,
        assignedTo: assignedTo,
        organizationName: organizationName,
        recipientRole: recipientRole,
        contextLabel: contextLabel,
        dueAt: dueAt,
        reminderEnabled: reminderEnabled,
        status: status ?? this.status,
        acceptance: acceptance ?? this.acceptance,
        feedback: feedback ?? this.feedback,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        events: events ?? this.events,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'createdBy': createdBy,
        'assignedTo': assignedTo,
        'organizationName': organizationName,
        'recipientRole': recipientRole,
        'contextLabel': contextLabel,
        'dueAt': dueAt.toIso8601String(),
        'reminderEnabled': reminderEnabled,
        'status': status.name,
        'acceptance': acceptance.name,
        'feedback': feedback,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'events': events.map((event) => event.toMap()).toList(),
      };

  factory SharedTask.fromMap(Map<dynamic, dynamic> map) => SharedTask(
        id: '${map['id'] ?? ''}',
        title: '${map['title'] ?? 'Tarefa compartilhada'}',
        description: '${map['description'] ?? ''}',
        createdBy: '${map['createdBy'] ?? 'Família'}',
        assignedTo: '${map['assignedTo'] ?? 'Família'}',
        organizationName: '${map['organizationName'] ?? ''}',
        recipientRole: '${map['recipientRole'] ?? 'Colaborador'}',
        contextLabel: '${map['contextLabel'] ?? 'Rotina'}',
        dueAt: DateTime.tryParse('${map['dueAt']}') ?? DateTime.now(),
        reminderEnabled: map['reminderEnabled'] == true,
        status: SharedTaskStatus.values.firstWhere(
          (value) => value.name == map['status'],
          orElse: () => SharedTaskStatus.pending,
        ),
        acceptance: TaskAcceptanceStatus.values.firstWhere(
          (value) => value.name == map['acceptance'],
          orElse: () => TaskAcceptanceStatus.notRequired,
        ),
        feedback: map['feedback'] == null ? null : '${map['feedback']}',
        createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${map['updatedAt']}') ?? DateTime.now(),
        events: (map['events'] as List?)
                ?.whereType<Map>()
                .map(SharedTaskEvent.fromMap)
                .toList() ??
            const [],
      );

  String get statusLabel => switch (status) {
        SharedTaskStatus.pending => 'Pendente',
        SharedTaskStatus.inProgress => 'Em andamento',
        SharedTaskStatus.completed => 'Concluída',
        SharedTaskStatus.partiallyCompleted => 'Parcial',
        SharedTaskStatus.needsHelp => 'Precisa de ajuda',
        SharedTaskStatus.declined => 'Não realizada',
        SharedTaskStatus.cancelled => 'Cancelada',
      };

  String get acceptanceLabel => switch (acceptance) {
        TaskAcceptanceStatus.notRequired => '',
        TaskAcceptanceStatus.pending => 'Aguardando aceite',
        TaskAcceptanceStatus.accepted => 'Aceita',
        TaskAcceptanceStatus.declined => 'Recusada pelo destinatário',
      };

  bool get isOpen =>
      status == SharedTaskStatus.pending ||
      status == SharedTaskStatus.inProgress;
}

class SharedTaskStore {
  SharedTaskStore._();

  static Future<Box> _box(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return SecureBoxService.openSecureBox(name);
  }

  static Future<List<SharedTask>> load() async {
    ParentalSessionService.requireAuthenticated();
    final box = await _box(_taskBoxName);
    return box.values
        .whereType<Map>()
        .map(SharedTask.fromMap)
        .where((task) => task.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  static Future<void> save(
    SharedTask task, {
    String operation = 'upsert',
  }) async {
    ParentalSessionService.requireAuthenticated();
    final box = await _box(_taskBoxName);
    await box.put(task.id, task.toMap());
    final queue = await _box(_syncBoxName);
    await queue.put('${task.id}-${DateTime.now().microsecondsSinceEpoch}', {
      'taskId': task.id,
      'operation': operation,
      'queuedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> pendingSyncOperations() async {
    ParentalSessionService.requireAuthenticated();
    final queue = await _box(_syncBoxName);
    return queue.values
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  static Future<void> acknowledgeSyncOperation(dynamic key) async {
    ParentalSessionService.requireAuthenticated();
    final queue = await _box(_syncBoxName);
    await queue.delete(key);
  }
}
