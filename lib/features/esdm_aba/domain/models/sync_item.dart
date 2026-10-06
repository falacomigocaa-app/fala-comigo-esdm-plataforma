import 'package:hive/hive.dart';

part 'sync_item.g.dart';

/// Item da fila local de sincronização, armazenado em box Hive cifrada.
@HiveType(typeId: 14, adapterName: 'SyncQueueAdapter')
class SyncItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String payload;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  int attempts;

  @HiveField(4)
  final String endpoint;

  /// Mantido fora do payload para permitir roteamento sem expor plaintext.
  @HiveField(5)
  final String? subjectId;

  SyncItem({
    required this.id,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    required this.endpoint,
    this.subjectId,
  });
}
