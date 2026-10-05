import 'package:hive/hive.dart';

part 'meta_esdm_model.g.dart';

/// Objetivo clínico estruturado para posterior tradução em missões práticas.
@HiveType(typeId: 11)
class MetaEsdmModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String codigoTecnicoDenver;

  /// Estados esperados nesta primeira versão: "Adquirido" e "Em Progresso".
  @HiveField(2)
  String status;

  @HiveField(3)
  int passoAtualAba;

  MetaEsdmModel({
    required this.id,
    required this.codigoTecnicoDenver,
    this.status = 'Em Progresso',
    this.passoAtualAba = 0,
  });
}
