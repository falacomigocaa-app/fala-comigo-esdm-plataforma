import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';

import '../../../../core/services/auth_token_service.dart';
import '../../../../core/services/secure_box_service.dart';
import '../../data/providers/transition_alerts_provider.dart';
import '../models/transition_alert.dart';

const transitionAlertSyncBoxName = 'transition_alerts_sync_queue';
const transitionAlertSyncSubjectId = String.fromEnvironment(
  'PORTAL_SUBJECT_ID',
  defaultValue: 'local-subject',
);
const transitionAlertSyncApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

enum TransitionAlertSyncOutcome {
  synced,
  queued,
  offline,
  unauthorized,
  conflict,
  failed,
}

/// Sincroniza somente a sombra remota autorizada; o alerta local continua
/// funcionando mesmo sem conta, rede ou concessão válida.
class TransitionAlertSyncService {
  TransitionAlertSyncService._();

  static final Connectivity _connectivity = Connectivity();
  static final http.Client _client = http.Client();
  static Future<bool> Function()? connectivityOverride;
  static Future<http.Response> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  )? requestOverride;
  static StreamSubscription<List<ConnectivityResult>>?
      _connectivitySubscription;
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

  static Future<Box<dynamic>> _box() =>
      SecureBoxService.openSecureBox<dynamic>(transitionAlertSyncBoxName);

  static Future<void> _removePendingOperations(
    Box<dynamic> box,
    String subjectId,
    String alertId,
  ) async {
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw is Map &&
          raw['subjectId'] == subjectId &&
          raw['alertId'] == alertId) {
        await box.delete(key);
      }
    }
  }

  static Future<TransitionAlertSyncOutcome> enqueueUpsert(
    TransitionAlert alert, {
    String subjectId = transitionAlertSyncSubjectId,
  }) async {
    final box = await _box();
    await _removePendingOperations(box, subjectId, alert.id);
    final operationId = 'upsert:$subjectId:${alert.id}';
    await box.put(operationId, {
      'operationId': operationId,
      'operation': 'upsert',
      'subjectId': subjectId,
      'alertId': alert.id,
      'payload': alert.toMap(),
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    return syncPending(subjectId: subjectId);
  }

  static Future<TransitionAlertSyncOutcome> enqueueDelete(
    String alertId, {
    String subjectId = transitionAlertSyncSubjectId,
  }) async {
    final box = await _box();
    await _removePendingOperations(box, subjectId, alertId);
    final operationId = 'delete:$subjectId:$alertId';
    await box.put(operationId, {
      'operationId': operationId,
      'operation': 'delete',
      'subjectId': subjectId,
      'alertId': alertId,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    return syncPending(subjectId: subjectId);
  }

  static Future<TransitionAlertSyncOutcome> syncPending({
    String subjectId = transitionAlertSyncSubjectId,
  }) async {
    if (_isSyncing) return TransitionAlertSyncOutcome.queued;
    if (!await _isOnline()) return TransitionAlertSyncOutcome.offline;
    var token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      AuthTokenService.requireAuthentication();
      return TransitionAlertSyncOutcome.unauthorized;
    }

    _isSyncing = true;
    var outcome = TransitionAlertSyncOutcome.synced;
    try {
      final box = await _box();
      final entries = box.values
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .where((item) => item['subjectId'] == subjectId)
          .toList()
        ..sort((a, b) => '${a['queuedAt']}'.compareTo('${b['queuedAt']}'));
      for (final item in entries) {
        final result = await _send(item, token);
        if (result == TransitionAlertSyncOutcome.synced) {
          await _markSynced(item);
          await box.delete(item['operationId']);
          continue;
        }
        if (result == TransitionAlertSyncOutcome.conflict) {
          await _markConflict(item);
          await box.delete(item['operationId']);
        }
        outcome = result;
        if (result != TransitionAlertSyncOutcome.conflict) break;
      }
      if (outcome == TransitionAlertSyncOutcome.synced) {
        token = await AuthTokenService.readToken() ?? token;
        final pulled = await _pull(subjectId, token);
        if (pulled != TransitionAlertSyncOutcome.synced) outcome = pulled;
      }
      return outcome;
    } finally {
      _isSyncing = false;
    }
  }

  static Future<TransitionAlertSyncOutcome> _send(
    Map<String, dynamic> item,
    String token,
  {bool allowRefresh = true}) async {
    final subjectId = item['subjectId'] as String?;
    final alertId = item['alertId'] as String?;
    if (subjectId == null || alertId == null) {
      return TransitionAlertSyncOutcome.failed;
    }
    final uri = Uri.parse(transitionAlertSyncApiBaseUrl).resolve(
      '/v1/subjects/${Uri.encodeComponent(subjectId)}/transition-alerts'
      '${item['operation'] == 'delete' ? '/${Uri.encodeComponent(alertId)}' : ''}',
    );
    final headers = {
      'accept': 'application/json',
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
      'x-request-id': item['operationId'] as String,
    };
    final rawPayload = item['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    payload
      ..remove('recordedAudioPath')
      ..remove('audioUrl')
      ..remove('syncState')
      ..remove('syncError')
      ..remove('remoteVersion');
    final body = item['operation'] == 'upsert'
        ? jsonEncode({
            'alert': payload,
            'updatedAt': payload['updatedAt'] is int
                ? DateTime.fromMillisecondsSinceEpoch(
                    payload['updatedAt'] as int,
                  ).toUtc().toIso8601String()
                : payload['updatedAt'],
          })
        : null;
    try {
      final override = requestOverride;
      final response = override != null
          ? await override(item['operation'] == 'delete' ? 'DELETE' : 'POST',
              uri, headers, body)
          : item['operation'] == 'delete'
              ? await _client
                  .delete(uri, headers: headers)
                  .timeout(const Duration(seconds: 15))
              : await _client
                  .post(uri, headers: headers, body: body)
                  .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        if (allowRefresh && AuthTokenService.autoRefreshEnabled) {
          final refreshed = await AuthTokenService.refreshSession(
            apiBaseUrl: transitionAlertSyncApiBaseUrl,
          );
          if (refreshed) {
            final refreshedToken = await AuthTokenService.readToken();
            if (refreshedToken != null && refreshedToken.isNotEmpty) {
              return _send(item, refreshedToken, allowRefresh: false);
            }
          }
        }
        AuthTokenService.requireAuthentication();
        return TransitionAlertSyncOutcome.unauthorized;
      }
      if (response.statusCode == 409) {
        return TransitionAlertSyncOutcome.conflict;
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        return TransitionAlertSyncOutcome.failed;
      }
      return TransitionAlertSyncOutcome.synced;
    } catch (_) {
      return TransitionAlertSyncOutcome.failed;
    }
  }

  static Future<TransitionAlertSyncOutcome> _pull(
    String subjectId,
    String token,
  ) async {
    final uri = Uri.parse(transitionAlertSyncApiBaseUrl).resolve(
      '/v1/subjects/${Uri.encodeComponent(subjectId)}/transition-alerts',
    );
    try {
      final override = requestOverride;
      final response = override != null
          ? await override(
              'GET',
              uri,
              {
                'accept': 'application/json',
                'authorization': 'Bearer $token',
              },
              null)
          : await _client.get(uri, headers: {
              'accept': 'application/json',
              'authorization': 'Bearer $token',
            }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        AuthTokenService.requireAuthentication();
        return TransitionAlertSyncOutcome.unauthorized;
      }
      if (response.statusCode != 200) return TransitionAlertSyncOutcome.failed;
      final decoded = jsonDecode(response.body);
      final rawAlerts = decoded is Map ? decoded['alerts'] : null;
      if (rawAlerts is! List) return TransitionAlertSyncOutcome.failed;
      await _mergeRemote(rawAlerts, subjectId);
      return TransitionAlertSyncOutcome.synced;
    } catch (_) {
      return TransitionAlertSyncOutcome.failed;
    }
  }

  static Future<void> _mergeRemote(
      List<dynamic> rawAlerts, String subjectId) async {
    final box =
        await SecureBoxService.openSecureBox<dynamic>(transitionAlertsBoxName);
    final pendingIds = (await _box())
        .values
        .whereType<Map>()
        .where((item) => item['subjectId'] == subjectId)
        .map((item) => item['alertId'])
        .whereType<String>()
        .toSet();
    for (final raw in rawAlerts) {
      if (raw is! Map) continue;
      final remote = TransitionAlert.fromMap(Map<String, dynamic>.from(raw));
      if (pendingIds.contains(remote.id)) continue;
      final localRaw = box.get(remote.id);
      if (localRaw is Map) {
        final local =
            TransitionAlert.fromMap(Map<String, dynamic>.from(localRaw));
        if (local.syncState == 'pending' || local.syncState == 'conflict') {
          continue;
        }
        if (!remote.updatedAt.isAfter(local.updatedAt)) continue;
        remote.recordedAudioPath = local.recordedAudioPath;
      }
      remote.syncState = 'synced';
      remote.syncError = null;
      await box.put(remote.id, remote.toMap());
    }
  }

  static Future<void> _markConflict(Map<String, dynamic> item) async {
    if (item['operation'] != 'upsert') return;
    final payload = item['payload'];
    if (payload is! Map) return;
    final box =
        await SecureBoxService.openSecureBox<dynamic>(transitionAlertsBoxName);
    final raw = box.get(item['alertId']);
    if (raw is! Map) return;
    final alert = TransitionAlert.fromMap(Map<String, dynamic>.from(raw));
    alert.syncState = 'conflict';
    alert.syncError = 'VERSION_CONFLICT';
    await box.put(alert.id, alert.toMap());
  }

  static Future<void> _markSynced(Map<String, dynamic> item) async {
    if (item['operation'] != 'upsert') return;
    final alertId = item['alertId'];
    if (alertId is! String) return;
    final box =
        await SecureBoxService.openSecureBox<dynamic>(transitionAlertsBoxName);
    final raw = box.get(alertId);
    if (raw is! Map) return;
    final alert = TransitionAlert.fromMap(Map<String, dynamic>.from(raw));
    alert.syncState = 'synced';
    alert.syncError = null;
    await box.put(alert.id, alert.toMap());
  }

  static Future<bool> _isOnline() async {
    final override = connectivityOverride;
    if (override != null) return override();
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasNetwork(results);
    } catch (_) {
      return false;
    }
  }

  static bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
