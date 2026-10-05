// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'concessao_acesso_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConcessaoAcessoModelAdapter extends TypeAdapter<ConcessaoAcessoModel> {
  @override
  final int typeId = 10;

  @override
  ConcessaoAcessoModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ConcessaoAcessoModel(
      id: fields[0] as String,
      perfilAlvo: fields[1] as String,
      permiteLeituraMetas: fields[2] as bool,
      permiteEscritaDados: fields[3] as bool,
      dataExpiracao: fields[4] as DateTime,
      revoked: fields[5] == null ? false : fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ConcessaoAcessoModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.perfilAlvo)
      ..writeByte(2)
      ..write(obj.permiteLeituraMetas)
      ..writeByte(3)
      ..write(obj.permiteEscritaDados)
      ..writeByte(4)
      ..write(obj.dataExpiracao)
      ..writeByte(5)
      ..write(obj.revoked);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConcessaoAcessoModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
