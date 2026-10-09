import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'auth_token_service.dart';
import 'crypto_service.dart';
import 'secure_box_service.dart';

const locationSyncBoxName = 'secure_location_sync_queue';
const locationSyncApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);
const locationSyncSubjectId = String.fromEnvironment(
  'PORTAL_SUBJECT_ID',
  defaultValue: 'local-subject',
);

enum LocationSyncOutcome { synced, queued, offline, unauthorized, failed }

/// A localização permanece local e cifrada quando não há rede. O portal
/// recebe apenas o envelope E2EE e nunca latitude/longitude em claro.
class LocationSyncService {
  LocationSyncService._();

  static final Connectivity _connectivity = Connectivity();
  static final http.Client _client = http.Client();
  static final _uuid = Uuid();
  static bool _isSyncing = false;
  static Future<bool> Function()? connectivityOverride;
  static Future<http.Response> Function(
      String, Uri, Map<String, String>, String?)? requestOverride;

  static Future<Box<dynamic>> _box() =>
      SecureBoxService.openSecureBox<dynamic>(locationSyncBoxName);

  static Future<LocationSyncOutcome> enqueuePosition({
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime recordedAt,
    String subjectId = locationSyncSubjectId,
  }) async {
    final organizationId = await AuthTokenService.readOrganizationId();
    if (organizationId == null || organizationId.isEmpty) {
      AuthTokenService.requireAuthentication();
      return LocationSyncOutcome.unauthorized;
    }
    final id = 'location:${subjectId}:${_uuid.v4()}';
    final envelope = await CryptoService.encryptPayload(
      organizationId: organizationId,
      plaintext: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
      }),
    );
    final parsed = jsonDecode(envelope) as Map<String, dynamic>;
    final box = await _box();
    await box.put(id, {
      'id': id,
      'subjectId': subjectId,
      'organizationId': organizationId,
      'encryptedData': parsed['encryptedData'],
      'iv': parsed['iv'],
      'clientRecordedAt': recordedAt.toUtc().toIso8601String(),
      'queuedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return syncPending(subjectId: subjectId);
  }

  static Future<LocationSyncOutcome> syncPending({
    String subjectId = locationSyncSubjectId,
  }) async {
    if (_isSyncing) return LocationSyncOutcome.queued;
    if (!await _isOnline()) return LocationSyncOutcome.offline;
    final token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      AuthTokenService.requireAuthentication();
      return LocationSyncOutcome.unauthorized;
    }
    _isSyncing = true;
    try {
      final box = await _box();
      final entries = box.values
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where((item) => item['subjectId'] == subjectId)
          .toList()
        ..sort((a, b) => '${a['queuedAt']}'.compareTo('${b['queuedAt']}'));
      for (final item in entries) {
        final result = await _send(item, token);
        if (result != LocationSyncOutcome.synced) return result;
        await box.delete(item['id']);
      }
      return LocationSyncOutcome.synced;
    } finally {
      _isSyncing = false;
    }
  }

  static Future<LocationSyncOutcome> revoke({
    String subjectId = locationSyncSubjectId,
  }) async {
    final box = await _box();
    for (final key in box.keys.toList()) {
      final item = box.get(key);
      if (item is Map && item['subjectId'] == subjectId) await box.delete(key);
    }
    final token = await AuthTokenService.readToken();
    final organizationId = await AuthTokenService.readOrganizationId();
    if (token == null || token.isEmpty || organizationId == null) {
      AuthTokenService.requireAuthentication();
      return LocationSyncOutcome.unauthorized;
    }
    final uri = Uri.parse(locationSyncApiBaseUrl).resolve(
      '/v1/subjects/${Uri.encodeComponent(subjectId)}/location-updates/all',
    );
    try {
      final headers = {
        'accept': 'application/json',
        'authorization': 'Bearer $token'
      };
      final override = requestOverride;
      final response = override != null
          ? await override('DELETE', uri, headers, null)
          : await _client
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        AuthTokenService.requireAuthentication();
        return LocationSyncOutcome.unauthorized;
      }
      return response.statusCode == 200
          ? LocationSyncOutcome.synced
          : LocationSyncOutcome.failed;
    } catch (_) {
      return LocationSyncOutcome.failed;
    }
  }

  static Future<LocationSyncOutcome> _send(
    Map<String, dynamic> item,
    String token, {
    bool allowRefresh = true,
  }) async {
    final uri = Uri.parse(locationSyncApiBaseUrl).resolve(
      '/v1/subjects/${Uri.encodeComponent(item['subjectId'] as String)}/location-updates',
    );
    final headers = {
      'accept': 'application/json',
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
      'x-request-id': item['id'] as String,
    };
    final body = jsonEncode({
      'id': item['id'],
      'organizationId': item['organizationId'],
      'encryptedData': item['encryptedData'],
      'iv': item['iv'],
      'clientRecordedAt': item['clientRecordedAt'],
    });
    try {
      final override = requestOverride;
      final response = override != null
          ? await override('POST', uri, headers, body)
          : await _client
              .post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        if (allowRefresh && AuthTokenService.autoRefreshEnabled) {
          final refreshed = await AuthTokenService.refreshSession(
            apiBaseUrl: locationSyncApiBaseUrl,
          );
          if (refreshed) {
            final refreshedToken = await AuthTokenService.readToken();
            if (refreshedToken != null && refreshedToken.isNotEmpty) {
              return _send(item, refreshedToken, allowRefresh: false);
            }
          }
        }
        AuthTokenService.requireAuthentication();
        return LocationSyncOutcome.unauthorized;
      }
      return response.statusCode == 200 || response.statusCode == 201
          ? LocationSyncOutcome.synced
          : LocationSyncOutcome.failed;
    } catch (_) {
      return LocationSyncOutcome.failed;
    }
  }

  static Future<bool> _isOnline() async {
    final override = connectivityOverride;
    if (override != null) return override();
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
