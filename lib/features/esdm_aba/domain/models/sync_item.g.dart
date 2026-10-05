// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_item.dart';

class SyncQueueAdapter extends TypeAdapter<SyncItem> {
  @override
  final int typeId = 14;

  @override
  SyncItem read(BinaryReader reader) {
    final fields = <int, dynamic>{
      for (var i = 0; i < reader.readByte(); i++)
        reader.readByte(): reader.read(),
    };
    return SyncItem(
      id: fields[0] as String,
      payload: fields[1] as String,
      createdAt: fields[2] as DateTime,
      attempts: (fields[3] as int?) ?? 0,
      endpoint: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, SyncItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.payload)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.attempts)
      ..writeByte(4)
      ..write(obj.endpoint);
  }
}
