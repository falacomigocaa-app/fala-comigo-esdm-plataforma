import 'dart:convert';
import 'dart:developer' as developer;

import '../../data/concessao_acesso_store.dart';
import '../../data/sincronizacao_queue_store.dart';
import '../models/concessao_acesso_model.dart';
import '../models/sincronizacao_queue_model.dart';

/// Cliente local da futura API Cuidado Conectado.
///
/// Esta versão não abre conexão de rede: ela simula a chamada HTTP somente
/// depois de validar a concessão local, preservando o modo offline-first.
class CuidadoConectadoClient {
  CuidadoConectadoClient._();

  static Future<void> processarFilaSincronizacao() async {
    final pending = await SincronizacaoQueueStore.loadPending();
    for (final item in pending) {
      final profile = _profileForEndpoint(item.endpointAlvo);
      if (profile == null) continue;

      final grant = await ConcessaoAcessoStore.findActive(profile);
      // Revogação ou expiração bloqueia o evento e o mantém pendente.
      if (grant == null) continue;

      await _simulateHttpRequest(item, grant);
      await SincronizacaoQueueStore.markProcessed(item);
    }
  }

  static String? _profileForEndpoint(String endpoint) {
    switch (endpoint) {
      case '/coletas':
        return escolaPerfilAlvo;
      case '/metas':
        return especialistaPerfilAlvo;
      default:
        return null;
    }
  }

  static Future<void> _simulateHttpRequest(
    SincronizacaoQueueModel item,
    ConcessaoAcessoModel grant,
  ) async {
    final method = switch (item.acao) {
      'INSERT' => 'POST',
      'UPDATE' => 'PUT',
      'DELETE' => 'DELETE',
      _ => throw const FormatException('Ação de sincronização desconhecida.'),
    };

    final headers = <String, String>{
      // Placeholder local até a emissão de token server-side do portal.
      'Authorization': 'Bearer consent-${grant.id}',
      'X-Consent-Profile': grant.perfilAlvo,
      'Content-Type': 'application/json',
    };
    final payload = jsonDecode(item.payloadJson);

    developer.log(
      'Simulação Cuidado Conectado: $method ${item.endpointAlvo} '
      'headers=${headers.keys.toList()} payload=$payload',
      name: 'cuidado_conectado.sync',
    );
  }
}
