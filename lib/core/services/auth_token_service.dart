import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokenService {
  AuthTokenService._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'fala_comigo_portal_access_token';
  static const _refreshTokenKey = 'fala_comigo_portal_refresh_token';
  static void Function()? onAuthenticationRequired;

  static Future<String?> readToken() => _storage.read(key: _tokenKey);

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
