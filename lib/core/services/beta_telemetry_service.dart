import 'dart:convert';

import 'package:http/http.dart' as http;

const betaTelemetryApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

class BetaTelemetryService {
  BetaTelemetryService._();

  static final http.Client _client = http.Client();
  static final String _sessionId =
      'mobile-${DateTime.now().microsecondsSinceEpoch}';
  static Future<http.Response> Function(Uri uri, String body)? requestOverride;

  static const _allowedEvents = {
    'screen_view',
    'beta_expired',
    'sync_success',
    'sync_failed',
  };
  static const _allowedScreens = {
    'splash',
    'home',
    'login',
    'parental_gate',
    'esdm_dashboard',
    'coleta_escola',
    'painel_consentimento',
    'metas_esdm',
  };

  static Future<bool> track(
    String event, {
    String? screen,
    String? reason,
  }) async {
    if (!_allowedEvents.contains(event)) return false;
    final payload = <String, dynamic>{
      'event': event,
      'sessionId': _sessionId,
      'platform': 'android',
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (event == 'screen_view' && _allowedScreens.contains(screen)) {
      payload['screen'] = screen;
    }
    if (event == 'beta_expired' &&
        const {'expired', 'clock_rollback', 'not_started'}.contains(reason)) {
      payload['reason'] = reason;
    }
    final uri = Uri.parse(betaTelemetryApiBaseUrl).resolve('/v1/telemetry');
    try {
      final body = jsonEncode(payload);
      final override = requestOverride;
      if (override != null) {
        await override(uri, body);
      } else {
        await _client
            .post(
              uri,
              headers: {
                'accept': 'application/json',
                'content-type': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 5));
      }
      return true;
    } catch (_) {
      // Telemetry nunca pode bloquear a comunicação ou o modo offline.
      return false;
    }
  }
}
