import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

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
const syncUserId = String.fromEnvironment(
  'PORTAL_USER_ID',
  defaultValue: 'user-admin-beta',
);

enum SyncOutcome { synced, queued, localOnly }

/// Envia coletas quando há rede e mantém a fila cifrada quando não há.
class SyncQueueService {
  SyncQueueService._();

  static final Connectivity _connectivity = Connectivity();
  static final http.Client _client = http.Client();
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static Timer? _fallbackTimer;
  static bool _isSyncing = false;

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
    if (grant == null) return SyncOutcome.localOnly;

    final item = _itemFor(coleta, subjectId: subjectId);
    if (!await _isOnline()) {
      await SyncQueueStore.enqueue(item);
      return SyncOutcome.queued;
    }

    try {
      await _send(item, grant.id);
      return SyncOutcome.synced;
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
        if (grant == null) return;
        try {
          await _send(item, grant.id);
          await SyncQueueStore.remove(item);
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
      }),
      createdAt: DateTime.now(),
      endpoint: '/school-collections',
    );
  }

  static Future<void> _send(SyncItem item, String grantId) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    final subjectId = payload['subjectId'] as String?;
    if (subjectId == null || subjectId.isEmpty) {
      throw const FormatException('SyncItem sem subjectId.');
    }

    final uri = Uri.parse(syncApiBaseUrl).resolve(
      '/v1/subjects/${Uri.encodeComponent(subjectId)}${item.endpoint}',
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'accept': 'application/json',
            'content-type': 'application/json',
            'authorization': 'Bearer consent-$grantId',
            'x-consent-profile': escolaPerfilAlvo,
            'x-synthetic-user-id': syncUserId,
            'x-request-id': item.id,
          },
          body: item.payload,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('Sincronização recusada: HTTP ${response.statusCode}.');
    }
  }

  static Future<bool> _isOnline() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _hasNetwork(result);
    } catch (_) {
      return false;
    }
  }

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
