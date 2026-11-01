import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_token_service.dart';

class InvitationService {
  InvitationService._();

  static const _apiBaseUrl = String.fromEnvironment(
    'PORTAL_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );
  static final http.Client _client = http.Client();

  static Future<Map<String, dynamic>> create({
    required String email,
    String? phone,
    required String role,
    required List<String> scopes,
  }) async {
    final token = await AuthTokenService.readToken();
    final organizationId = await AuthTokenService.readOrganizationId();
    if (token == null || organizationId == null) {
      throw const InvitationException('AUTH_REQUIRED');
    }
    final response = await _client
        .post(
          Uri.parse(_apiBaseUrl).resolve(
            '/v1/organizations/$organizationId/invitations',
          ),
          headers: {
            'accept': 'application/json',
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'inviteeEmail': email.trim().isEmpty ? null : email.trim(),
            'inviteePhone': phone?.trim().isEmpty == true ? null : phone?.trim(),
            'role': role,
            'scopes': scopes,
            'purpose': 'Acesso autorizado pela família',
          }),
        )
        .timeout(const Duration(seconds: 15));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 401) {
      await AuthTokenService.refreshAccessToken();
      throw const InvitationException('SESSION_EXPIRED');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InvitationException(payload['error']?.toString() ?? 'INVITATION_FAILED');
    }
    return payload['invitation'] is Map<String, dynamic>
        ? payload['invitation'] as Map<String, dynamic>
        : payload;
  }
}

class InvitationException implements Exception {
  const InvitationException(this.code);
  final String code;
  @override
  String toString() => code;
}
