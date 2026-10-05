import 'package:hive/hive.dart';

part 'sincronizacao_queue_model.g.dart';

/// Evento local pendente de sincronização com o Cuidado Conectado.
@HiveType(typeId: 13)
class SincronizacaoQueueModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String payloadJson;

  @HiveField(2)
  String endpointAlvo;

  @HiveField(3)
  String acao;

  @HiveField(4)
  bool processado;

  SincronizacaoQueueModel({
    required this.id,
    required this.payloadJson,
    required this.endpointAlvo,
    required this.acao,
    this.processado = false,
  });
}
