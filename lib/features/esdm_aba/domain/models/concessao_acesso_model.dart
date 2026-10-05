import 'package:hive/hive.dart';

part 'concessao_acesso_model.g.dart';

/// Concessão local de acesso controlada pelo responsável.
///
/// A autorização server-side continua obrigatória quando o portal conectado
/// existir; este modelo representa o estado local do switch parental.
@HiveType(typeId: 10)
class ConcessaoAcessoModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String perfilAlvo;

  @HiveField(2)
  bool permiteLeituraMetas;

  @HiveField(3)
  bool permiteEscritaDados;

  @HiveField(4)
  DateTime dataExpiracao;

  ConcessaoAcessoModel({
    required this.id,
    required this.perfilAlvo,
    this.permiteLeituraMetas = false,
    this.permiteEscritaDados = false,
    required this.dataExpiracao,
  });

  bool get estaExpirada => dataExpiracao.isBefore(DateTime.now());
}
