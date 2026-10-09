import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/features/parental_area/presentation/screens/parental_gate_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final fakeStorage = <String, String>{};
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('parental-gate-');
    Hive.init(hiveDirectory.path);
    await Hive.openBox('app_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  setUp(() {
    fakeStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments is Map
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};
      switch (call.method) {
        case 'write':
          fakeStorage[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return fakeStorage[args['key'] as String];
        case 'delete':
          fakeStorage.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('primeiro acesso mostra os quatro indicadores para criar o PIN',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ParentalGateScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PRIMEIRO ACESSO'), findsOneWidget);
    expect(find.text('Criar acesso'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pin-indicators-Novo PIN')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-indicators-Confirmar PIN')),
        findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '48');
    await tester.pump();
    expect(
        find.byKey(const ValueKey('pin-indicators-Novo PIN')), findsOneWidget);
  });

  testWidgets('login apresenta estado bloqueado com aviso dedicado',
      (tester) async {
    // A derivação criptográfica é coberta por parental_pin_service_test.dart.
    // Aqui testamos apenas o estado visual do lockout, usando um verifier
    // estrutural e um prazo futuro no armazenamento simulado.
    fakeStorage['fala_comigo_parental_pin_salt_v2'] =
        'AAAAAAAAAAAAAAAAAAAAAA==';
    fakeStorage['fala_comigo_parental_pin_verifier_v2'] =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    fakeStorage['fala_comigo_parental_pin_lockout_until_v2'] =
        '${DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch}';

    await tester.pumpWidget(const MaterialApp(home: ParentalGateScreen()));
    await tester.pumpAndSettle();
    expect(find.text('ÁREA PROTEGIDA'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4826');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pin-blocked-banner')), findsOneWidget);
    expect(
        find.textContaining('Acesso bloqueado por segurança'), findsOneWidget);
  });
}
