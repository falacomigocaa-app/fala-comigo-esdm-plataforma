import 'package:hive/hive.dart';

part 'sync_item.g.dart';

/// Item da fila local de sincronização, armazenado em box Hive cifrada.
@HiveType(typeId: 14, adapterName: 'SyncQueueAdapter')
class SyncItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String payload;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  int attempts;

  @HiveField(4)
  final String endpoint;

  SyncItem({
    required this.id,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    required this.endpoint,
  });
}
