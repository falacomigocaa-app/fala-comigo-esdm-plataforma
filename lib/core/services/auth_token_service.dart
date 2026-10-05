import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokenService {
  AuthTokenService._();

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'fala_comigo_portal_access_token';
  static void Function()? onAuthenticationRequired;

  static Future<String?> readToken() => _storage.read(key: _tokenKey);

  static Future<void> saveToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token JWT não pode ser vazio.');
    }
    await _storage.write(key: _tokenKey, value: normalized);
  }

  static Future<void> clearToken() => _storage.delete(key: _tokenKey);

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
