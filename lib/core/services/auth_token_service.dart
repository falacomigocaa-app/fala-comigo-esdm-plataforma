import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'crypto_service.dart';

class AuthTokenService {
  AuthTokenService._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'fala_comigo_portal_access_token';
  static const _refreshTokenKey = 'fala_comigo_portal_refresh_token';
  static void Function()? onAuthenticationRequired;
  static bool autoRefreshEnabled = false;

  static Future<String?> readToken() => _storage.read(key: _tokenKey);

  static Future<String?> readOrganizationId() async {
    final token = await readToken();
    if (token == null) return null;
    try {
      final segments = token.split('.');
      if (segments.length != 3) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
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
    await saveToken(accessToken);
    final normalizedRefresh = refreshToken.trim();
    if (normalizedRefresh.isEmpty) {
      throw ArgumentError.value(
        refreshToken,
        'refreshToken',
        'Refresh token não pode ser vazio.',
      );
    }
    await _storage.write(key: _refreshTokenKey, value: normalizedRefresh);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  static Future<void> handleRefreshTokenExpired() async {
    await clearToken();
    requireAuthentication();
  }

  static void requireAuthentication() {
    onAuthenticationRequired?.call();
  }

  /// Rotaciona o refresh token e atualiza a chave E2EE da organização na
  /// mesma sessão. Versões anteriores permanecem no armazenamento seguro.
  static Future<bool> refreshSession({required String apiBaseUrl}) async {
    final refreshToken = await readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await handleRefreshTokenExpired();
      return false;
    }
    try {
      final response = await http
          .post(
            Uri.parse(apiBaseUrl).resolve('/v1/auth/refresh'),
            headers: {
              'accept': 'application/json',
              'content-type': 'application/json',
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        await handleRefreshTokenExpired();
        return false;
      }
      final payload = decoded;
      if (payload['accessToken'] is! String ||
          payload['refreshToken'] is! String) {
        await handleRefreshTokenExpired();
        return false;
      }
      await saveSessionTokens(
        accessToken: payload['accessToken'] as String,
        refreshToken: payload['refreshToken'] as String,
      );
      if (payload['organizationKey'] is String &&
          payload['keyVersion'] is int &&
          payload['organizationId'] is String) {
        await CryptoService.saveOrganizationKey(
          organizationId: payload['organizationId'] as String,
          keyVersion: payload['keyVersion'] as int,
          organizationKeyBase64: payload['organizationKey'] as String,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
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
