import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/features/aac_grid/domain/models/pictogram_card.dart';
import 'package:fala_comigo/features/parental_area/presentation/screens/settings_screen.dart';

void main() {
  late Directory hiveDirectory;
  late Box<PictogramCard> cardsBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('parental-preview-');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(PictogramCardAdapter());
    cardsBox = await Hive.openBox<PictogramCard>('pictogram_cards');
    await Hive.openBox('transition_alerts');
    await Hive.openBox('app_settings');
  });

  setUp(() async {
    await cardsBox.clear();
    await cardsBox.put(
      'card-comer',
      PictogramCard(
        id: 'card-comer',
        label: 'Comer',
        imagePath: 'assets/images/cards/comer.png',
        category: 'acoes',
      ),
    );
  });

  testWidgets('exibe preview visual dos cartões na configuração',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('parental-settings')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    final cardsSection = find.byKey(
      const ValueKey('settings-section-Cartões de comunicação'),
    );
    await Scrollable.ensureVisible(
      tester.element(cardsSection),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(cardsSection);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('cards-visual-preview'))),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cards-visual-preview')), findsOneWidget);
    expect(find.text('Preview da grade infantil'), findsOneWidget);
    expect(find.text('Comer'), findsNWidgets(2));
  });

  testWidgets('exibe miniaturas e preview em tempo real do tema',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('parental-settings')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    final themeSection = find.byKey(
      const ValueKey('settings-section-Personalização da experiência'),
    );
    await Scrollable.ensureVisible(
      tester.element(themeSection),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(themeSection);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('selected-theme-preview')), findsOneWidget);
    expect(find.text('Prévia em tempo real'), findsOneWidget);
    expect(find.text('Dinossauros'), findsOneWidget);

    await tester.tap(find.text('Dinossauros'));
    await tester.pumpAndSettle();
    expect(find.text('Tema Dinossauros'), findsOneWidget);
  });
}
