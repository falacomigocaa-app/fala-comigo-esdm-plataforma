import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../features/aac_grid/domain/models/pictogram_card.dart';

/// A paper fallback using the same order as the communication grid.
/// Images are supplied locally; this service never requests network resources.
class CommunicationBoardPdfService {
  static Future<Uint8List> generate({
    required List<PictogramCard> cards,
    required Future<Uint8List?> Function(PictogramCard) loadImage,
  }) async {
    if (cards.isEmpty) throw ArgumentError('Selecione ao menos um cartão.');
    final ordered = [...cards]..sort((a, b) => a.order.compareTo(b.order));
    final document = pw.Document();
    for (var start = 0; start < ordered.length; start += 12) {
      final pageCards = ordered.skip(start).take(12).toList();
      final images = <pw.ImageProvider?>[];
      for (final card in pageCards) {
        try {
          final bytes = await loadImage(card);
          images.add(bytes == null ? null : pw.MemoryImage(bytes));
        } catch (_) {
          images.add(null);
        }
      }
      final pageNumber = start ~/ 12 + 1;
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Column(children: [
          pw.Text('Fala Comigo - prancha de comunicação',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(
              'Aponte para comunicar. Aguarde o tempo de resposta da pessoa.',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 18),
          pw.GridView(
            crossAxisCount: 3,
            childAspectRatio: 0.85,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (var index = 0; index < pageCards.length; index++)
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey600),
                      borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Column(children: [
                    pw.Expanded(
                      child: images[index] == null
                          ? pw.Center(
                              child: pw.Text(pageCards[index].label,
                                  textAlign: pw.TextAlign.center))
                          : pw.Image(images[index]!, fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(pageCards[index].label,
                        textAlign: pw.TextAlign.center,
                        maxLines: 2,
                        style: pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ]),
                ),
            ],
          ),
          pw.Spacer(),
          pw.Text('Página $pageNumber de ${(ordered.length / 12).ceil()}',
              style: const pw.TextStyle(fontSize: 9)),
        ]),
      ));
    }
    return document.save();
  }
}
