// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meta_esdm_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MetaEsdmModelAdapter extends TypeAdapter<MetaEsdmModel> {
  @override
  final int typeId = 11;

  @override
  MetaEsdmModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MetaEsdmModel(
      id: fields[0] as String,
      codigoTecnicoDenver: fields[1] as String,
      status: fields[2] as String,
      passoAtualAba: fields[3] as int,
      subjectId: fields[4] as String?,
      missaoPais: fields[5] as String?,
      dicaPratica: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MetaEsdmModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.codigoTecnicoDenver)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.passoAtualAba)
      ..writeByte(4)
      ..write(obj.subjectId)
      ..writeByte(5)
      ..write(obj.missaoPais)
      ..writeByte(6)
      ..write(obj.dicaPratica);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetaEsdmModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
