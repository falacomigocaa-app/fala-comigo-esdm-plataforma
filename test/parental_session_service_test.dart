import 'package:flutter_test/flutter_test.dart';

import 'package:fala_comigo/core/services/parental_session_service.dart';

void main() {
  tearDown(() {
    ParentalSessionService.lock();
    ParentalSessionService.onExpired = null;
  });

  test('sessão começa bloqueada', () {
    expect(ParentalSessionService.isAuthenticated, isFalse);
    expect(ParentalSessionService.requireSession(), isFalse);
  });

  test('autenticação abre uma sessão temporária', () {
    ParentalSessionService.authenticate();

    expect(ParentalSessionService.isAuthenticated, isTrue);
    expect(ParentalSessionService.requireSession(), isTrue);
  });

  test('bloqueio invalida a sessão e cancela a expiração', () {
    ParentalSessionService.authenticate();
    ParentalSessionService.lock();

    expect(ParentalSessionService.isAuthenticated, isFalse);
    expect(ParentalSessionService.requireSession(), isFalse);
  });

  test('atividade externa temporária preserva a sessão parental', () {
    ParentalSessionService.authenticate();
    ParentalSessionService.beginExternalActivity();

    expect(ParentalSessionService.isExternalActivityInProgress, isTrue);
    expect(ParentalSessionService.isAuthenticated, isTrue);

    ParentalSessionService.completeExternalActivity();
    expect(ParentalSessionService.isExternalActivityInProgress, isFalse);
    expect(ParentalSessionService.isAuthenticated, isTrue);
  });

  test('expira automaticamente e notifica a camada de navegação', () async {
    var expired = false;
    ParentalSessionService.onExpired = () => expired = true;

    ParentalSessionService.authenticate(
      duration: const Duration(milliseconds: 20),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(ParentalSessionService.isAuthenticated, isFalse);
    expect(ParentalSessionService.requireSession(), isFalse);
    expect(expired, isTrue);
  });
}
