import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/auth_token_service.dart';
import '../../data/concessao_acesso_store.dart';
import '../../data/sync_queue_store.dart';
import '../../domain/models/coleta_escola_model.dart';
import '../../domain/models/sync_item.dart';

const syncSubjectId = String.fromEnvironment(
  'PORTAL_SUBJECT_ID',
  defaultValue: 'local-subject',
);
const syncApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

enum SyncOutcome { synced, queued, localOnly, blockedByConsent }

class ConsentBlockedException implements Exception {
  const ConsentBlockedException();
}

/// Envia coletas quando há rede e mantém a fila cifrada quando não há.
class SyncQueueService {
  SyncQueueService._();

  static final Connectivity _connectivity = Connectivity();
  static final http.Client _client = http.Client();
  static Future<bool> Function()? connectivityOverride;
  static Future<http.Response> Function(
    Uri uri,
    Map<String, String> headers,
    String body,
  )? postOverride;
  static StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription;
  static Timer? _fallbackTimer;
  static bool _isSyncing = false;
  static final ValueNotifier<bool> consentBlockedNotifier =
      ValueNotifier(false);

  static bool get consentBlocked => consentBlockedNotifier.value;

  static void start() {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen(
      (results) {
        if (_hasNetwork(results)) unawaited(syncPending());
      },
    );
    _fallbackTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(syncPending()),
    );
  }

  static Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  static Future<SyncOutcome> saveOrSyncCollection({
    required ColetaEscolaModel coleta,
    required String subjectId,
  }) async {
    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo);
    if (grant == null) {
      _notifyConsentBlocked();
      return SyncOutcome.blockedByConsent;
    }
    _notifyConsentValid();

    final item = _itemFor(coleta, subjectId: subjectId);
    if (!await _isOnline()) {
      await SyncQueueStore.enqueue(item);
      return SyncOutcome.queued;
    }

    try {
      await _send(item);
      return SyncOutcome.synced;
    } on ConsentBlockedException {
      await SyncQueueStore.enqueue(item);
      return SyncOutcome.blockedByConsent;
    } on AuthTokenExpiredException {
      await SyncQueueStore.enqueue(item);
      AuthTokenService.requireAuthentication();
      return SyncOutcome.queued;
    } on AuthTokenRequiredException {
      await SyncQueueStore.enqueue(item);
      AuthTokenService.requireAuthentication();
      return SyncOutcome.queued;
    } catch (_) {
      item.attempts = 1;
      await SyncQueueStore.enqueue(item);
      return SyncOutcome.queued;
    }
  }

  static Future<void> syncPending() async {
    if (_isSyncing || !await _isOnline()) return;
    _isSyncing = true;
    try {
      for (final item in await SyncQueueStore.pending()) {
        final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo);
        if (grant == null) {
          _notifyConsentBlocked();
          return;
        }
        _notifyConsentValid();
        try {
          await _send(item);
          await SyncQueueStore.remove(item);
        } on ConsentBlockedException {
          // A concessão pode expirar entre a checagem do item e o POST.
          // Não remover nem incrementar: todos os itens continuam intactos.
          _notifyConsentBlocked();
          return;
        } on AuthTokenExpiredException {
          // O item permanece na box sem incrementar tentativas: a coleta clínica
          // só poderá sair após uma nova autenticação válida.
          AuthTokenService.requireAuthentication();
          return;
        } on AuthTokenRequiredException {
          AuthTokenService.requireAuthentication();
          return;
        } catch (_) {
          await SyncQueueStore.incrementAttempts(item);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  static SyncItem _itemFor(
    ColetaEscolaModel coleta, {
    required String subjectId,
  }) {
    return SyncItem(
      id: 'school-collection:${coleta.id}',
      payload: jsonEncode({
        'subjectId': subjectId,
        'id': coleta.id,
        'dataRegistro': coleta.dataRegistro.toIso8601String(),
        'blocoRotinaEscolar': coleta.blocoRotinaEscolar,
        'nivelSuporte': coleta.nivelSuporte,
        'metaId': coleta.metaId,
      }),
      createdAt: DateTime.now(),
      endpoint: '/school-collections',
    );
  }

  static Future<void> _send(SyncItem item) async {
    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo);
    if (grant == null) {
      _notifyConsentBlocked();
      throw const ConsentBlockedException();
    }
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthTokenRequiredException();
    }
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final subjectId = payload['subjectId'] as String?;
    if (subjectId == null || subjectId.isEmpty) {
      throw const FormatException('SyncItem sem subjectId.');
    }

    final uri = Uri.parse(syncApiBaseUrl).resolve(
      '/v1/subjects/${Uri.encodeComponent(subjectId)}${item.endpoint}',
    );
    final headers = {
      'accept': 'application/json',
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
      'x-consent-profile': escolaPerfilAlvo,
      'x-request-id': item.id,
    };
    final override = postOverride;
    final response = override != null
        ? await override(uri, headers, item.payload)
        : await _client
            .post(uri, headers: headers, body: item.payload)
            .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw AuthTokenExpiredException(response.statusCode, response.body);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('Sincronização recusada: HTTP ${response.statusCode}.');
    }
  }

  static Future<bool> _isOnline() async {
    final override = connectivityOverride;
    if (override != null) return override();
    try {
      final result = await _connectivity.checkConnectivity();
      return _hasNetwork(result);
    } catch (_) {
      return false;
    }
  }

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  static void _notifyConsentBlocked() {
    consentBlockedNotifier.value = true;
  }

  static void _notifyConsentValid() {
    if (consentBlockedNotifier.value) consentBlockedNotifier.value = false;
  }
}
