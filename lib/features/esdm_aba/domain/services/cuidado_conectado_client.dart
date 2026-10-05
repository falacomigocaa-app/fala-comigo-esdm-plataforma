import 'dart:convert';
import 'dart:developer' as developer;

import '../../../../core/services/auth_token_service.dart';
import '../../data/concessao_acesso_store.dart';
import '../../data/sincronizacao_queue_store.dart';
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

      await _simulateHttpRequest(item);
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
  ) async {
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthTokenRequiredException();
    }
    final method = switch (item.acao) {
      'INSERT' => 'POST',
      'UPDATE' => 'PUT',
      'DELETE' => 'DELETE',
      _ => throw const FormatException('Ação de sincronização desconhecida.'),
    };

    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Consent-Profile': escolaPerfilAlvo,
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
