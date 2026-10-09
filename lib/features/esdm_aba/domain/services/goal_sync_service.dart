import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/auth_token_service.dart';
import '../../data/goal_store.dart';
import '../models/meta_esdm_model.dart';

const goalSyncApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

enum GoalSyncResult { synced, offline, unauthorized, failed }

/// Baixa metas clínicas ativas e só altera o cache após validar toda a resposta.
class GoalSyncService {
  GoalSyncService._();

  static final Connectivity _connectivity = Connectivity();
  static final http.Client _client = http.Client();

  static Future<GoalSyncResult> syncActiveGoals({
    required String subjectId,
    bool allowRefresh = true,
  }) async {
    if (!await _isOnline()) return GoalSyncResult.offline;
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      AuthTokenService.requireAuthentication();
      return GoalSyncResult.unauthorized;
    }

    try {
      final uri = Uri.parse(goalSyncApiBaseUrl).resolve(
        '/v1/subjects/${Uri.encodeComponent(subjectId)}/esdm-goals',
      );
      final response = await _client.get(
        uri,
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        if (allowRefresh && AuthTokenService.autoRefreshEnabled) {
          final refreshed = await AuthTokenService.refreshSession(
            apiBaseUrl: goalSyncApiBaseUrl,
          );
          if (refreshed) {
            return syncActiveGoals(subjectId: subjectId, allowRefresh: false);
          }
        }
        AuthTokenService.requireAuthentication();
        return GoalSyncResult.unauthorized;
      }
      if (response.statusCode != 200) return GoalSyncResult.failed;

      final decoded = jsonDecode(response.body);
      final rawGoals =
          decoded is Map<String, dynamic> ? decoded['goals'] : null;
      if (rawGoals is! List) return GoalSyncResult.failed;
      final goals = rawGoals
          .map((raw) => _fromApi(raw, subjectId))
          .toList(growable: false);
      await GoalStore.replaceForSubject(subjectId, goals);
      return GoalSyncResult.synced;
    } catch (_) {
      // Falhas de rede ou parsing preservam o cache anterior intacto.
      return GoalSyncResult.failed;
    }
  }

  static MetaEsdmModel _fromApi(dynamic raw, String subjectId) {
    if (raw is! Map) throw const FormatException('Meta inválida na resposta.');
    final id = raw['id'];
    final code = raw['codigoTecnicoDenver'];
    if (id is! String || id.isEmpty || code is! String || code.isEmpty) {
      throw const FormatException('Meta sem id ou código técnico.');
    }
    return MetaEsdmModel(
      id: id,
      subjectId: raw['subjectId'] as String? ?? subjectId,
      codigoTecnicoDenver: code,
      status: raw['status'] as String? ?? 'Em Progresso',
      passoAtualAba:
          raw['passoAtualAba'] is int ? raw['passoAtualAba'] as int : 0,
      missaoPais: raw['missaoPais'] as String?,
      dicaPratica: raw['dicaPratica'] as String?,
    );
  }

  static Future<bool> _isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
