import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/services/auth_token_service.dart';
import '../../../esdm_aba/domain/services/sync_queue_service.dart';

const authApiBaseUrl = String.fromEnvironment(
  'PORTAL_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

class LoginState {
  final bool loading;
  final bool authenticated;
  final String? errorMessage;

  const LoginState({
    this.loading = false,
    this.authenticated = false,
    this.errorMessage,
  });

  LoginState copyWith({
    bool? loading,
    bool? authenticated,
    String? errorMessage,
  }) {
    return LoginState(
      loading: loading ?? this.loading,
      authenticated: authenticated ?? this.authenticated,
      errorMessage: errorMessage,
    );
  }
}

final loginControllerProvider =
    StateNotifierProvider.autoDispose<LoginController, LoginState>(
  (ref) => LoginController(),
);

class LoginController extends StateNotifier<LoginState> {
  LoginController() : super(const LoginState());

  static final http.Client _client = http.Client();

  Future<bool> login({required String email, required String password}) async {
    if (state.loading) return false;
    state = state.copyWith(loading: true, errorMessage: null);
    try {
      final response = await _client
          .post(
            Uri.parse(authApiBaseUrl).resolve('/v1/auth/login'),
            headers: {
              'accept': 'application/json',
              'content-type': 'application/json',
            },
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 ||
          payload['accessToken'] is! String ||
          payload['refreshToken'] is! String) {
        throw StateError(_messageFor(payload, response.statusCode));
      }

      await AuthTokenService.saveSessionTokens(
        accessToken: payload['accessToken'] as String,
        refreshToken: payload['refreshToken'] as String,
      );
      state = state.copyWith(loading: false, authenticated: true);
      unawaited(SyncQueueService.syncPending());
      return true;
    } on FormatException {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Resposta inválida do servidor.',
      );
    } on TimeoutException {
      state = state.copyWith(
        loading: false,
        errorMessage: 'A conexão demorou. Verifique a rede e tente novamente.',
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: error is StateError
            ? error.message
            : 'Não foi possível entrar. Verifique a conexão e suas credenciais.',
      );
    }
    return false;
  }

  static String _messageFor(Map<String, dynamic> payload, int statusCode) {
    switch (payload['error']) {
      case 'INVALID_CREDENTIALS':
        return 'Email ou senha inválidos.';
      default:
        return statusCode >= 500
            ? 'O servidor está indisponível no momento.'
            : 'Não foi possível autenticar. Tente novamente.';
    }
  }
}
