import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fala_comigo/core/services/beta_gate_service.dart';
import 'package:fala_comigo/core/services/beta_telemetry_service.dart';

void main() {
  test('trava beta bloqueia a expiração informada pelo backend', () {
    final status = BetaGateService.evaluateAccess(
      current: DateTime.parse('2026-11-10T00:00:01Z'),
      serverStatus: {
        'status': 'expired',
        'serverNow': '2026-11-10T00:00:01Z',
        'expiresAt': '2026-11-09T23:59:59Z',
      },
    );

    expect(status.allowed, isFalse);
    expect(status.reason, 'expired');
  });

  test('trava beta bloqueia retrocesso do relógio local', () {
    final status = BetaGateService.evaluateAccess(
      current: DateTime.parse('2026-10-12T00:00:00Z'),
      lastWallClock: DateTime.parse('2026-10-20T00:00:00Z'),
      localExpiresAt: DateTime.parse('2026-11-09T00:00:00Z'),
    );

    expect(status.allowed, isFalse);
    expect(status.reason, 'clock_rollback');
  });

  test(
      'telemetria remove eventos não allowlistados e não inclui texto sensível',
      () async {
    final captured = <String>[];
    BetaTelemetryService.requestOverride = (uri, body) async {
      captured.add('$uri $body');
      return http.Response('{}', 202);
    };
    addTearDown(() => BetaTelemetryService.requestOverride = null);

    final accepted =
        await BetaTelemetryService.track('screen_view', screen: 'login');
    final rejected = await BetaTelemetryService.track('click', screen: 'login');

    expect(accepted, isTrue);
    expect(rejected, isFalse);
    expect(captured.single, contains('"event":"screen_view"'));
    expect(captured.single, isNot(contains('password')));
    expect(captured.single, isNot(contains('clinicalText')));
  });
}
