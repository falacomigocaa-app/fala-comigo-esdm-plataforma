import 'dart:async';

import 'package:flutter/foundation.dart';

class ParentalSessionRequiredException implements Exception {
  const ParentalSessionRequiredException();

  @override
  String toString() =>
      'ParentalSessionRequiredException: sessão parental exigida';
}

/// Controla a sessão temporária da Área do Responsável.
///
/// A autenticação não é persistida: ao expirar o tempo ou ao aplicativo ir
/// para segundo plano, a sessão é invalidada e o PIN volta a ser exigido.
class ParentalSessionService {
  ParentalSessionService._();

  static const sessionDuration = Duration(minutes: 10);
  static Timer? _expirationTimer;
  static bool _authenticated = false;
  static bool _externalActivityInProgress = false;
  static VoidCallback? onExpired;

  static bool get isAuthenticated => _authenticated;

  /// Mantém a sessão parental durante uma atividade externa iniciada pelo
  /// responsável, como a câmera do sistema ou o seletor de mídia.
  static bool get isExternalActivityInProgress => _externalActivityInProgress;

  static void beginExternalActivity() {
    _externalActivityInProgress = true;
  }

  static void completeExternalActivity() {
    _externalActivityInProgress = false;
  }

  static void authenticate({Duration? duration}) {
    _authenticated = true;
    _expirationTimer?.cancel();
    _expirationTimer = Timer(duration ?? sessionDuration, _expire);
  }

  static void lock() {
    _expirationTimer?.cancel();
    _expirationTimer = null;
    _authenticated = false;
    _externalActivityInProgress = false;
  }

  static bool requireSession() {
    if (!_authenticated) return false;
    return true;
  }

  /// Barreira de defesa em profundidade para stores e casos de uso.
  static void requireAuthenticated() {
    if (!requireSession()) {
      throw const ParentalSessionRequiredException();
    }
  }

  static void _expire() {
    _expirationTimer = null;
    if (!_authenticated) return;
    _authenticated = false;
    onExpired?.call();
  }
}
