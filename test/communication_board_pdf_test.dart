import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fala_comigo/core/services/communication_board_pdf_service.dart';
import 'package:fala_comigo/features/aac_grid/domain/models/pictogram_card.dart';

void main() {
  test('prancha pagina 13 cartões e preserva ordem com imagem indisponível',
      () async {
    final requested = <String>[];
    final cards = List.generate(
        13,
        (i) => PictogramCard(
            id: '$i', label: 'Cartão $i', imagePath: 'missing', order: 12 - i));
    final pdf = await CommunicationBoardPdfService.generate(
        cards: cards,
        loadImage: (card) async {
          requested.add(card.id);
          throw StateError('Imagem local ausente');
        });
    expect(utf8.decode(pdf.take(5).toList()), '%PDF-');
    final content = latin1.decode(pdf);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(content).length, 2);
    expect(requested, List.generate(13, (i) => '${12 - i}'));
    expect(cards.first.id, '0');
  });
  test('prancha vazia não gera documento enganoso', () async {
    await expectLater(
        CommunicationBoardPdfService.generate(
            cards: [], loadImage: (_) async => null),
        throwsArgumentError);
  });
}
