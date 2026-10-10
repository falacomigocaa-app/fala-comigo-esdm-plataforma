import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'beta_telemetry_service.dart';

const betaStartAt = String.fromEnvironment(
  'BETA_START_AT',
  defaultValue: '2026-10-10T00:00:00.000Z',
);
const betaDurationDays =
    int.fromEnvironment('BETA_DURATION_DAYS', defaultValue: 30);

class BetaAccessStatus {
  const BetaAccessStatus({
    required this.allowed,
    required this.reason,
    required this.expiresAt,
  });

  final bool allowed;
  final String reason;
  final DateTime expiresAt;
}

class BetaGateService {
  BetaGateService._();

  static const _storage = FlutterSecureStorage();
  static const _lastWallClockKey = 'fala_comigo_beta_last_wall_clock';
  static const _expiresAtKey = 'fala_comigo_beta_expires_at';
  static const _maxClockSkew = Duration(minutes: 5);
  static final http.Client _client = http.Client();
  static Future<http.Response> Function(Uri uri)? statusRequestOverride;

  static BetaAccessStatus evaluateAccess({
    required DateTime current,
    DateTime? lastWallClock,
    DateTime? localExpiresAt,
    Map<String, dynamic>? serverStatus,
  }) {
    final now = current.toUtc();
    final last = lastWallClock?.toUtc();
    if (last != null && now.add(_maxClockSkew).isBefore(last)) {
      return _status(
          false, 'clock_rollback', localExpiresAt ?? _defaultExpiry());
    }
    final serverNow = _parseDate(serverStatus?['serverNow']);
    final expiresAt = _parseDate(serverStatus?['expiresAt']) ??
        localExpiresAt ??
        _defaultExpiry();
    final effectiveNow = serverNow ?? now;
    final reason = serverStatus?['status'] == 'not_started'
        ? 'not_started'
        : serverStatus?['status'] == 'expired' ||
                !effectiveNow.isBefore(expiresAt)
            ? 'expired'
            : 'active';
    return _status(reason == 'active', reason, expiresAt);
  }

  static Future<BetaAccessStatus> checkAccess({
    DateTime Function()? now,
  }) async {
    final current = (now ?? DateTime.now)().toUtc();
    final lastWallClock = await _readDate(_lastWallClockKey);
    final localExpiresAt = await _readDate(_expiresAtKey);
    if (lastWallClock != null &&
        current.add(_maxClockSkew).isBefore(lastWallClock)) {
      final status =
          _status(false, 'clock_rollback', localExpiresAt ?? _defaultExpiry());
      await _persist(current, status.expiresAt);
      await BetaTelemetryService.track('beta_expired', reason: status.reason);
      return status;
    }

    Map<String, dynamic>? serverStatus;
    try {
      final uri = Uri.parse(betaTelemetryApiBaseUrl).resolve('/v1/beta/status');
      final override = statusRequestOverride;
      final response = override != null
          ? await override(uri)
          : await _client
              .get(uri, headers: {'accept': 'application/json'}).timeout(
              const Duration(seconds: 3),
            );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) serverStatus = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Offline: use only a previously trusted expiry or the compiled beta date.
    }

    final status = evaluateAccess(
      current: current,
      lastWallClock: lastWallClock,
      localExpiresAt: localExpiresAt,
      serverStatus: serverStatus,
    );
    await _persist(current, status.expiresAt);
    if (!status.allowed) {
      await BetaTelemetryService.track('beta_expired', reason: status.reason);
    }
    return status;
  }

  static BetaAccessStatus _status(
          bool allowed, String reason, DateTime expiresAt) =>
      BetaAccessStatus(allowed: allowed, reason: reason, expiresAt: expiresAt);

  static DateTime _defaultExpiry() {
    final start = DateTime.parse(betaStartAt).toUtc();
    return start.add(const Duration(days: betaDurationDays));
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String) return null;
    try {
      return DateTime.parse(value).toUtc();
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> _readDate(String key) async =>
      _parseDate(await _storage.read(key: key));

  static Future<void> _persist(DateTime now, DateTime expiresAt) async {
    await _storage.write(key: _lastWallClockKey, value: now.toIso8601String());
    await _storage.write(
        key: _expiresAtKey, value: expiresAt.toIso8601String());
  }
}
