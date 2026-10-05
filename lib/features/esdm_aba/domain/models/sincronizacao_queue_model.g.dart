// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sincronizacao_queue_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SincronizacaoQueueModelAdapter
    extends TypeAdapter<SincronizacaoQueueModel> {
  @override
  final int typeId = 13;

  @override
  SincronizacaoQueueModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SincronizacaoQueueModel(
      id: fields[0] as String,
      payloadJson: fields[1] as String,
      endpointAlvo: fields[2] as String,
      acao: fields[3] as String,
      processado: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SincronizacaoQueueModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.payloadJson)
      ..writeByte(2)
      ..write(obj.endpointAlvo)
      ..writeByte(3)
      ..write(obj.acao)
      ..writeByte(4)
      ..write(obj.processado);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SincronizacaoQueueModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
