import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/auth_token_service.dart';
import '../../../../core/services/crypto_service.dart';
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
const syncOrganizationId = String.fromEnvironment(
  'PORTAL_ORGANIZATION_ID',
  defaultValue: 'org-demo-alpha',
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
  static bool _wiping = false;
  static final Set<Future<Object?>> _operations = {};

  static Future<void> suspendForWipe() async {
    _wiping = true;
    await dispose();
    while (_operations.isNotEmpty) {
      await Future.wait(_operations.toList().map(
          (operation) => operation.then<void>((_) {}, onError: (Object _) {})));
    }
  }

  static void resumeAfterWipe() {
    _wiping = false;
  }

  static final ValueNotifier<bool> consentBlockedNotifier =
      ValueNotifier(false);

  static bool get consentBlocked => consentBlockedNotifier.value;

  static void start() {
    _connectivitySubscription ??= _connectivity.onConnectivityChanged.listen(
      (results) {
        if (_hasNetwork(results)) unawaited(syncPending());
      },
      onError: (Object _) {},
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
  }) {
    if (_wiping) return Future.value(SyncOutcome.localOnly);
    final operation =
        _saveOrSyncCollection(coleta: coleta, subjectId: subjectId);
    _operations.add(operation);
    return operation.whenComplete(() => _operations.remove(operation));
  }

  static Future<SyncOutcome> _saveOrSyncCollection({
    required ColetaEscolaModel coleta,
    required String subjectId,
  }) async {
    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo,
        requireWrite: true);
    if (grant == null) {
      _notifyConsentBlocked();
      return SyncOutcome.blockedByConsent;
    }
    _notifyConsentValid();

    final item = await _itemFor(coleta, subjectId: subjectId);
    await SyncQueueStore.enqueue(item);
    if (!await _isOnline()) {
      await SyncQueueStore.enqueue(item);
      return SyncOutcome.queued;
    }

    try {
      await _send(item);
      await SyncQueueStore.remove(item);
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

  static Future<void> syncPending() {
    if (_wiping || _isSyncing) return Future.value();
    _isSyncing = true;
    final operation = _syncPending();
    _operations.add(operation);
    return operation.whenComplete(() => _operations.remove(operation));
  }

  static Future<void> _syncPending() async {
    try {
      if (!await _isOnline()) return;
      for (final item in await SyncQueueStore.pending()) {
        if (_wiping) return;
        final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo,
            requireWrite: true);
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

  static Future<SyncItem> _itemFor(
    ColetaEscolaModel coleta, {
    required String subjectId,
  }) async {
    final organizationId =
        await AuthTokenService.readOrganizationId() ?? syncOrganizationId;
    final clearPayload = jsonEncode({
      'subjectId': subjectId,
      'id': coleta.id,
      'dataRegistro': coleta.dataRegistro.toIso8601String(),
      'blocoRotinaEscolar': coleta.blocoRotinaEscolar,
      'nivelSuporte': coleta.nivelSuporte,
      'metaId': coleta.metaId,
    });
    return SyncItem(
      id: 'school-collection:${coleta.id}',
      payload: await CryptoService.encryptPayload(
        organizationId: organizationId,
        plaintext: clearPayload,
      ),
      createdAt: DateTime.now(),
      endpoint: '/school-collections',
      subjectId: subjectId,
    );
  }

  static Future<void> _send(SyncItem item, {bool canRefresh = true}) async {
    if (_wiping) throw const ConsentBlockedException();
    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo,
        requireWrite: true);
    if (grant == null) {
      _notifyConsentBlocked();
      throw const ConsentBlockedException();
    }
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthTokenRequiredException();
    }
    final subjectId = item.subjectId ?? _legacySubjectId(item.payload);
    if (subjectId == null || subjectId.isEmpty) {
      throw const FormatException('SyncItem sem subjectId.');
    }

    final organizationId =
        await AuthTokenService.readOrganizationId() ?? syncOrganizationId;
    final envelope = _decodeEnvelopeOrEmpty(item.payload);
    if (!CryptoService.isEnvelope(envelope)) {
      item.payload = await CryptoService.encryptPayload(
        organizationId: organizationId,
        plaintext: item.payload,
      );
      await SyncQueueStore.enqueue(item);
    } else if (envelope['organizationId'] != organizationId) {
      throw StateError('Envelope E2EE pertence a outra organização.');
    }

    // Envelopes locais anteriores ao login são recifrados com a chave provisionada.
    // A chave antiga permanece disponível apenas para leitura local.
    if (!await CryptoService.hasProvisionedKey(organizationId)) {
      throw const AuthTokenRequiredException();
    }
    final prepared = await CryptoService.prepareForUpload(item.payload);
    if (prepared != item.payload) {
      item.payload = prepared;
      await SyncQueueStore.enqueue(item);
    }
    final finalGrant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo,
        requireWrite: true);
    if (_wiping || finalGrant == null) throw const ConsentBlockedException();
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
      if (canRefresh && await AuthTokenService.refreshSession()) {
        return _send(item, canRefresh: false);
      }
      throw AuthTokenExpiredException(response.statusCode, response.body);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError('Sincronização recusada: HTTP ${response.statusCode}.');
    }
  }

  static String? _legacySubjectId(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic>
          ? decoded['subjectId'] as String?
          : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decodeEnvelopeOrEmpty(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
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
