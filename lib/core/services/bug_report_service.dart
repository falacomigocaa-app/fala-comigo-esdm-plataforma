import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_token_service.dart';

const bugReportApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);
const bugReportAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0+1',
);

class BugReportService {
  BugReportService._();

  static final http.Client _client = http.Client();
  static Future<http.Response> Function(Uri uri, String body)? requestOverride;

  static Future<void> submit({
    required String description,
    required String severity,
  }) async {
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty || normalizedDescription.length > 2000) {
      throw const FormatException('Descrição inválida.');
    }
    if (!const {'leve', 'travamento', 'sugestao'}.contains(severity)) {
      throw const FormatException('Severidade inválida.');
    }
    var token = await AuthTokenService.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthTokenRequiredException();
    }
    final uri = Uri.parse(bugReportApiBaseUrl).resolve('/v1/beta/report');
    Future<http.Response> send(String currentToken) {
      final body = jsonEncode({
        'description': normalizedDescription,
        'severity': severity,
      });
      final override = requestOverride;
      if (override != null) return override(uri, body);
      return _client.post(uri, headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'authorization': 'Bearer $currentToken',
        'x-client-platform': 'android',
        'x-client-version': bugReportAppVersion,
        'x-device-model': 'android',
      }, body: body).timeout(const Duration(seconds: 15));
    }

    var response = await send(token);
    if (response.statusCode == 401 && await AuthTokenService.refreshAccessToken()) {
      token = await AuthTokenService.readToken();
      if (token != null && token.isNotEmpty) response = await send(token);
    }
    if (response.statusCode != 201) {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map ? decoded['error'] : null;
      throw StateError(error is String ? error : 'BUG_REPORT_FAILED');
    }
  }
}
