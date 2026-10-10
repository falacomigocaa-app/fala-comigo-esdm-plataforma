import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthTokenService {
  AuthTokenService._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'fala_comigo_portal_access_token';
  static const _refreshTokenKey = 'fala_comigo_portal_refresh_token';
  static const _apiBaseUrl = String.fromEnvironment(
    'PORTAL_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
  static final http.Client _client = http.Client();
  static Future<http.Response> Function(Uri uri, String body)?
      refreshRequestOverride;
  static Future<bool>? _refreshInFlight;
  static int _sessionGeneration = 0;
  static void Function()? onAuthenticationRequired;

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

  static Future<void> saveSessionTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final normalizedRefresh = refreshToken.trim();
    if (normalizedRefresh.isEmpty) {
      throw ArgumentError.value(
        refreshToken,
        'refreshToken',
        'Refresh token não pode ser vazio.',
      );
    }
    await saveToken(accessToken);
    await _storage.write(key: _refreshTokenKey, value: normalizedRefresh);
    _sessionGeneration++;
  }

  static Future<void> clearToken() async {
    _sessionGeneration++;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  /// Renova a sessão uma única vez quando várias chamadas recebem 401.
  /// A rotação é descartada se logout ou um novo login ocorrer durante a
  /// requisição, evitando que uma resposta antiga sobrescreva a sessão atual.
  static Future<bool> refreshAccessToken() {
    final current = _refreshInFlight;
    if (current != null) return current;
    final future = _refreshAccessTokenInternal();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  static Future<bool> _refreshAccessTokenInternal() async {
    final refreshToken = await readRefreshToken();
    final normalizedRefresh = refreshToken?.trim() ?? '';
    if (normalizedRefresh.isEmpty) {
      await clearToken();
      return false;
    }
    final generation = _sessionGeneration;
    final uri = Uri.parse(_apiBaseUrl).resolve('/v1/auth/refresh');
    final body = jsonEncode({'refreshToken': normalizedRefresh});
    try {
      final override = refreshRequestOverride;
      final response = override != null
          ? await override(uri, body)
          : await _client
              .post(
                uri,
                headers: {
                  'accept': 'application/json',
                  'content-type': 'application/json',
                },
                body: body,
              )
              .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await clearToken();
        return false;
      }
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      final accessToken = decoded is Map ? decoded['accessToken'] : null;
      final rotatedRefresh = decoded is Map ? decoded['refreshToken'] : null;
      if (accessToken is! String ||
          accessToken.trim().isEmpty ||
          rotatedRefresh is! String ||
          rotatedRefresh.trim().isEmpty) {
        return false;
      }
      if (generation != _sessionGeneration ||
          await readRefreshToken() != normalizedRefresh) {
        return (await readToken())?.isNotEmpty == true;
      }
      await saveSessionTokens(
        accessToken: accessToken,
        refreshToken: rotatedRefresh,
      );
      return true;
    } catch (_) {
      // Erros de rede preservam a sessão e a fila local para retry posterior.
      return false;
    }
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
