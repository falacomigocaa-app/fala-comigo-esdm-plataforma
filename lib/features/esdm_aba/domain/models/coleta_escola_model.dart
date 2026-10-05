import 'package:hive/hive.dart';

part 'coleta_escola_model.g.dart';

/// Registro mínimo e rápido para uma observação da rotina escolar.
@HiveType(typeId: 12)
class ColetaEscolaModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime dataRegistro;

  @HiveField(2)
  String blocoRotinaEscolar;

  @HiveField(3)
  String nivelSuporte;

  ColetaEscolaModel({
    required this.id,
    required this.dataRegistro,
    required this.blocoRotinaEscolar,
    required this.nivelSuporte,
  });
}
