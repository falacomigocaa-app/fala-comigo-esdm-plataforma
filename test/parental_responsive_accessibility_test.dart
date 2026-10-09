import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/features/aac_grid/domain/models/pictogram_card.dart';
import 'package:fala_comigo/features/parental_area/presentation/screens/parental_gate_screen.dart';
import 'package:fala_comigo/features/parental_area/presentation/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final fakeStorage = <String, String>{};
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'parental-responsive-',
    );
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(PictogramCardAdapter());
    await Hive.openBox<PictogramCard>('pictogram_cards');
    await Hive.openBox('transition_alerts');
    await Hive.openBox('app_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  setUp(() {
    fakeStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
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
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('dashboard compacto não gera overflow e mantém semântica', (
    tester,
  ) async {
    setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PAINEL DE CUIDADO'), findsOneWidget);
    expect(find.text('Alertas ativos'), findsOneWidget);

    final securityAction = find.byTooltip('Segurança e localização');
    expect(securityAction, findsOneWidget);
    expect(
      tester.getSize(securityAction).shortestSide,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('seletor de orientação preserva leitura em celular estreito', (
    tester,
  ) async {
    setViewport(tester, const Size(320, 640));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();

    final settingsList = find.byType(Scrollable).first;
    final themeTitle = find.text('Personalização da experiência');
    await tester.scrollUntilVisible(themeTitle, 500, scrollable: settingsList);
    await tester.tap(themeTitle);
    await tester.pumpAndSettle();

    final orientationTitle = find.text('Orientação da tela da criança');
    await tester.scrollUntilVisible(
      orientationTitle,
      300,
      scrollable: settingsList,
    );
    expect(orientationTitle, findsOneWidget);
    expect(find.bySemanticsLabel('Orientação Paisagem'), findsOneWidget);
    expect(find.bySemanticsLabel('Orientação Vertical'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gate do PIN continua rolável quando o teclado ocupa a tela', (
    tester,
  ) async {
    setViewport(tester, const Size(320, 460));

    await tester.pumpWidget(const MaterialApp(home: ParentalGateScreen()));
    await tester.pumpAndSettle();
    expect(find.text('PRIMEIRO ACESSO'), findsOneWidget);

    final pinField = find.byType(TextField).first;
    await tester.ensureVisible(pinField);
    await tester.tap(pinField);
    await tester.enterText(pinField, '48');
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();

    expect(find.text('Criar PIN e continuar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard em tablet preserva ações e navegação', (tester) async {
    setViewport(tester, const Size(1024, 768));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('ACESSO RÁPIDO'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Acompanhamento'), findsOneWidget);
    expect(find.text('Localização'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
