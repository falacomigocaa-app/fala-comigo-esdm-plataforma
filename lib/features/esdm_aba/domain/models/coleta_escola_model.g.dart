// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coleta_escola_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ColetaEscolaModelAdapter extends TypeAdapter<ColetaEscolaModel> {
  @override
  final int typeId = 12;

  @override
  ColetaEscolaModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ColetaEscolaModel(
      id: fields[0] as String,
      dataRegistro: fields[1] as DateTime,
      blocoRotinaEscolar: fields[2] as String,
      nivelSuporte: fields[3] as String,
      metaId: fields[4] as String?,
      subjectId: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ColetaEscolaModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.dataRegistro)
      ..writeByte(2)
      ..write(obj.blocoRotinaEscolar)
      ..writeByte(3)
      ..write(obj.nivelSuporte)
      ..writeByte(4)
      ..write(obj.metaId)
      ..writeByte(5)
      ..write(obj.subjectId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColetaEscolaModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
