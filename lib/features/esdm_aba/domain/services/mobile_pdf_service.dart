import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/services/crypto_service.dart';
import '../../data/goal_store.dart';
import '../../data/meta_esdm_store.dart';
import '../../data/sync_queue_store.dart';
import '../../../../core/services/secure_box_service.dart';
import '../models/meta_esdm_model.dart';
import '../models/sync_item.dart';

/// Gera relatórios clínicos locais sem enviar dados para a rede.
class MobilePdfService {
  MobilePdfService._();

  static Future<Uint8List> generate({
    required String subjectId,
    String? patientName,
    String? organizationName,
  }) async {
    var goals = await GoalStore.loadForSubject(subjectId);
    if (goals.isEmpty) {
      // Metas criadas antes do downlink podem não ter subjectId; elas só são
      // usadas como fallback local quando não há metas vinculadas ao sujeito.
      goals = (await MetaEsdmStore.loadAll())
          .where((goal) => goal.subjectId == null)
          .toList();
    }
    final collections = await _loadQueuedCollections(subjectId);
    final profile = await _loadProfile();
    final resolvedPatientName = patientName ??
        '${profile?['nome'] ?? profile?['name'] ?? 'Paciente local'}';
    final resolvedOrganization = organizationName ??
        '${profile?['organizacao'] ?? profile?['organization'] ?? 'Organização não informada'}';
    final average = _average(collections);
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 16),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Fala Comigo',
                style: pw.TextStyle(
                  color: PdfColors.blue800,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Relatório clínico ESDM / ABA',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
          ),
        ),
        build: (context) => [
          pw.Text(
            'Relatório de evolução clínica',
            style: pw.TextStyle(
              color: PdfColors.blue900,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 14),
          _identityTable(resolvedPatientName, resolvedOrganization, subjectId),
          pw.SizedBox(height: 18),
          _sectionTitle('Resumo de autonomia'),
          _summaryTable(collections.length, average),
          pw.SizedBox(height: 18),
          _sectionTitle('Metas clínicas cached'),
          goals.isEmpty
              ? _emptyText('Nenhuma meta local disponível para este indivíduo.')
              : _goalsTable(goals),
          pw.SizedBox(height: 18),
          _sectionTitle('Histórico local de coletas'),
          collections.isEmpty
              ? _emptyText('Nenhuma coleta pendente encontrada no aparelho.')
              : _collectionsTable(collections),
          pw.SizedBox(height: 20),
          pw.Text(
            'Documento gerado localmente a partir do cache cifrado. Revise o conteúdo com o profissional responsável; este arquivo não é diagnóstico nem prontuário completo.',
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
          ),
        ],
      ),
    );

    return document.save();
  }

  static Future<List<_QueuedCollection>> _loadQueuedCollections(
    String subjectId,
  ) async {
    final items = await SyncQueueStore.pending();
    final collections = <_QueuedCollection>[];
    for (final item
        in items.where((item) => item.endpoint == '/school-collections')) {
      final collection = await _QueuedCollection.tryParse(item);
      if (collection != null && collection.subjectId == subjectId) {
        collections.add(collection);
      }
    }
    collections
        .sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return collections;
  }

  static Future<Map<String, dynamic>?> _loadProfile() async {
    final box = await SecureBoxService.openSecureBox('patient_profile');
    final value = box.get('data');
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static double? _average(List<_QueuedCollection> collections) {
    final scores = collections
        .map((collection) => _levels[collection.supportLevel])
        .whereType<int>()
        .toList();
    if (scores.isEmpty) return null;
    return scores.reduce((left, right) => left + right) / scores.length;
  }

  static pw.Widget _identityTable(
    String patientName,
    String organization,
    String subjectId,
  ) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Paciente', 'Organização', 'Subject ID', 'Emissão'],
      data: [
        [
          patientName,
          organization,
          subjectId,
          _formatDateTime(DateTime.now()),
        ]
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellPadding: const pw.EdgeInsets.all(6),
    );
  }

  static pw.Widget _summaryTable(int count, double? average) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Coletas no cache', 'Autonomia média', 'Escala'],
      data: [
        [count.toString(), average?.toStringAsFixed(1) ?? '—', '0 a 3']
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellPadding: const pw.EdgeInsets.all(6),
    );
  }

  static pw.Widget _goalsTable(List<MetaEsdmModel> goals) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Código', 'Status', 'Passo ABA', 'Missão'],
      data: goals
          .map((goal) => [
                goal.codigoTecnicoDenver,
                goal.status,
                goal.passoAtualAba.toString(),
                goal.missaoPais ?? '—',
              ])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellPadding: const pw.EdgeInsets.all(6),
    );
  }

  static pw.Widget _collectionsTable(List<_QueuedCollection> collections) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Data', 'Bloco', 'Suporte', 'Tentativas'],
      data: collections
          .map((collection) => [
                _formatDateTime(collection.createdAt),
                collection.routineBlock,
                collection.supportLevel,
                collection.attempts.toString(),
              ])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellPadding: const pw.EdgeInsets.all(6),
    );
  }

  static pw.Widget _sectionTitle(String title) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 9),
        color: PdfColors.blue50,
        child: pw.Text(
          title,
          style: pw.TextStyle(
            color: PdfColors.blue900,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.Widget _emptyText(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 9),
        child: pw.Text(
          text,
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
        ),
      );

  static String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} às $hour:$minute';
  }
}

const _levels = {
  'Recusa': 0,
  'Ajuda Física': 1,
  'Ajuda Verbal': 2,
  'Independente': 3,
};

class _QueuedCollection {
  final String subjectId;
  final DateTime createdAt;
  final String routineBlock;
  final String supportLevel;
  final int attempts;

  const _QueuedCollection({
    required this.subjectId,
    required this.createdAt,
    required this.routineBlock,
    required this.supportLevel,
    required this.attempts,
  });

  static Future<_QueuedCollection?> tryParse(SyncItem item) async {
    try {
      final decoded = jsonDecode(item.payload);
      final clearPayload =
          decoded is Map<String, dynamic> && CryptoService.isEnvelope(decoded)
              ? await CryptoService.decryptPayload(item.payload)
              : item.payload;
      final map = jsonDecode(clearPayload) as Map<String, dynamic>;
      final subjectId = map['subjectId']?.toString();
      if (subjectId == null || subjectId.isEmpty) return null;
      return _QueuedCollection(
        subjectId: subjectId,
        createdAt: item.createdAt,
        routineBlock: map['blocoRotinaEscolar']?.toString() ?? '—',
        supportLevel: map['nivelSuporte']?.toString() ?? '—',
        attempts: item.attempts,
      );
    } catch (_) {
      return null;
    }
  }
}
