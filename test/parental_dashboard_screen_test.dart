import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/features/aac_grid/domain/models/pictogram_card.dart';
import 'package:fala_comigo/features/parental_area/presentation/screens/settings_screen.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory =
        await Directory.systemTemp.createTemp('parental-dashboard-');
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

  testWidgets('exibe dashboard inicial com resumo e ações rápidas',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    expect(find.text('PAINEL DE CUIDADO'), findsOneWidget);
    expect(find.text('ACESSO RÁPIDO'), findsOneWidget);
    expect(find.text('Novo cartão'), findsOneWidget);
    expect(find.text('Cartões'), findsOneWidget);
    expect(find.text('Alertas ativos'), findsOneWidget);
  });

  testWidgets(
      'navega entre Início, Acompanhamento, Localização e Configurações',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    await tester.tap(find.text('Acompanhamento'));
    await tester.pumpAndSettle();
    expect(find.text('Progresso e rotina'), findsOneWidget);

    await tester.tap(find.text('Localização'));
    await tester.pumpAndSettle();
    expect(find.text('Localização da criança'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parental-settings')), findsOneWidget);

    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    expect(find.text('PAINEL DE CUIDADO'), findsOneWidget);
  });
}
