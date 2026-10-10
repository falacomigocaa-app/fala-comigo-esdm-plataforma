import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokenService {
  AuthTokenService._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'fala_comigo_portal_access_token';
  static const _refreshTokenKey = 'fala_comigo_portal_refresh_token';
  static const _subjectKey = 'fala_comigo_portal_subject_id';
  static Future<String?> readSubjectId() => _storage.read(key: _subjectKey);
  static Future<void> selectSubject(String id) =>
      _storage.write(key: _subjectKey, value: id);
  static Future<void> clearSelectedSubject() =>
      _storage.delete(key: _subjectKey);
  static void Function()? onAuthenticationRequired;

  static Future<bool>? _refreshing;
  static int _sessionGeneration = 0;
  static int get sessionGeneration => _sessionGeneration;
  static Future<void> _writes = Future<void>.value();

  static Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<http.Response> Function(Uri, Map<String, String>, String)?
      refreshOverride;

  static Future<bool> refreshSession() =>
      _refreshing ??= _refreshSession().whenComplete(() {
        _refreshing = null;
      });

  static Future<bool> _refreshSession() async {
    final generation = _sessionGeneration;
    final refresh = await readRefreshToken();
    if (refresh == null) return false;
    try {
      final uri = Uri.parse(const String.fromEnvironment('PORTAL_API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8787'))
          .resolve('/v1/auth/refresh');
      final headers = {'content-type': 'application/json'};
      final body = jsonEncode({'refreshToken': refresh});
      final response = await (refreshOverride != null
              ? refreshOverride!(uri, headers, body)
              : http.post(uri, headers: headers, body: body))
          .timeout(const Duration(seconds: 15));
      if (generation != _sessionGeneration) return false;
      if (response.statusCode == 401 || response.statusCode == 403) {
        await clearToken();
        return false;
      }
      if (response.statusCode != 200) return false;
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['accessToken'] is! String ||
          payload['refreshToken'] is! String) {
        return false;
      }
      return await saveSessionTokens(
          expectedGeneration: generation,
          accessToken: payload['accessToken'] as String,
          refreshToken: payload['refreshToken'] as String);
    } catch (_) {
      return false;
    }
  }

  static Future<String?> readToken() => _storage.read(key: _tokenKey);

  static Future<String?> readOrganizationId() async {
    final token = await readToken();
    if (token == null) return null;
    try {
      final segments = token.split('.');
      if (segments.length != 3) return null;
      final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))));
      return claims is Map<String, dynamic> &&
              claims['organizationId'] is String
          ? claims['organizationId'] as String
          : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
          token, 'token', 'Token JWT não pode ser vazio.');
    }
    await _storage.write(key: _tokenKey, value: normalized);
  }

  static Future<String?> readRefreshToken() =>
      _storage.read(key: _refreshTokenKey);

  static Future<bool> saveSessionTokens({
    required String accessToken,
    required String refreshToken,
    int? expectedGeneration,
    Future<void> Function()? beforeSave,
  }) {
    final generation = expectedGeneration ?? _sessionGeneration;
    return _serialize(() async {
      if (generation != _sessionGeneration) return false;
      final normalizedRefresh = refreshToken.trim();
      if (normalizedRefresh.isEmpty) {
        throw ArgumentError.value(
          refreshToken,
          'refreshToken',
          'Refresh token não pode ser vazio.',
        );
      }
      if (accessToken.trim().isEmpty) throw ArgumentError('Token JWT vazio.');
      await beforeSave?.call();
      await saveToken(accessToken);
      await _storage.write(key: _refreshTokenKey, value: normalizedRefresh);
      return generation == _sessionGeneration;
    });
  }

  static Future<void> clearToken() {
    _sessionGeneration += 1;
    return _serialize(() async {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
      await clearSelectedSubject();
    });
  }

  /// Deve ser chamado quando o endpoint de refresh também responde 401.
  /// Nesse ponto a sessão de sete dias terminou e nenhum token pode ser
  /// reutilizado silenciosamente.
  static Future<void> handleRefreshTokenExpired() async {
    await clearToken();
    requireAuthentication();
  }

  static void requireAuthentication() {
    onAuthenticationRequired?.call();
  }
}

class AuthTokenRequiredException implements Exception {
  const AuthTokenRequiredException();

  @override
  String toString() => 'Token JWT ausente; reautenticação necessária.';
}

class AuthTokenExpiredException implements Exception {
  const AuthTokenExpiredException(this.statusCode, this.responseBody);

  final int statusCode;
  final String responseBody;

  @override
  String toString() =>
      'Token JWT expirado ou inválido (HTTP $statusCode): $responseBody';
}
