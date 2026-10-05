import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/coleta_escola_store.dart';
import '../../data/concessao_acesso_store.dart';
import '../../data/meta_esdm_store.dart';
import '../models/concessao_acesso_model.dart';
import '../models/coleta_escola_model.dart';
import '../models/meta_esdm_model.dart';
import 'esdm_translator.dart';

/// Gera uma cópia local e compartilhável do estado do cuidado conectado.
///
/// A leitura é feita pelos stores, que abrem as boxes cifradas antes de
/// fornecer os dados. O documento é criado em memória e não é salvo
/// automaticamente em um caminho permanente pelo aplicativo.
class EsdmPdfService {
  EsdmPdfService._();

  static Future<Uint8List> gerarRelatorioUnificado() async {
    final metas = await MetaEsdmStore.loadAll();
    final coletas = await ColetaEscolaStore.loadAll();
    final concessoes = await ConcessaoAcessoStore.loadAll();
    final document = pw.Document();
    final generatedAt = _formatDateTime(DateTime.now());

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
                'Relatório local ESDM/ABA',
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
            'Relatório Unificado de Comunicação e Cuidado',
            style: pw.TextStyle(
              color: PdfColors.blue900,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Gerado localmente em $generatedAt',
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
          ),
          pw.SizedBox(height: 20),
          _sectionTitle('1. Plano de Metas Ativas'),
          if (metas.isEmpty)
            _emptyText('Nenhuma meta cadastrada no aparelho.')
          else
            ...metas.map(_goalBlock),
          pw.SizedBox(height: 18),
          _sectionTitle('2. Histórico de Coletas da Escola'),
          if (coletas.isEmpty)
            _emptyText('Nenhuma coleta escolar registrada no aparelho.')
          else
            ...coletas.map(_schoolCollectionBlock),
          pw.SizedBox(height: 18),
          _sectionTitle('3. Status das Concessões de Acesso'),
          if (concessoes.isEmpty)
            _emptyText('Nenhuma concessão de acesso cadastrada.')
          else
            ...concessoes.map(_accessGrantBlock),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Text(
              'Documento exportado do aparelho por escolha do responsável. '
              'Ele organiza registros locais e não é diagnóstico, prontuário, '
              'avaliação clínica ou previsão de evolução. Revise o conteúdo '
              'com o profissional responsável antes de utilizá-lo em decisões '
              'de cuidado ou contexto escolar.',
              style: const pw.TextStyle(
                color: PdfColors.grey700,
                fontSize: 9,
                lineSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _goalBlock(MetaEsdmModel meta) {
    final translation = EsdmTranslator.translate(meta.codigoTecnicoDenver);
    return _recordBlock(
      title: translation?.missaoPais ?? 'Meta técnica sem tradução disponível',
      lines: [
        if (translation != null) 'Dica prática: ${translation.dicaPratica}',
        'Código técnico: ${meta.codigoTecnicoDenver}',
        'Status: ${meta.status}',
        'Passo atual da análise ABA: ${meta.passoAtualAba}',
      ],
    );
  }

  static pw.Widget _schoolCollectionBlock(ColetaEscolaModel collection) {
    return _recordBlock(
      title: '${collection.blocoRotinaEscolar} — ${_formatDateTime(collection.dataRegistro)}',
      lines: ['Nível de suporte empregado: ${collection.nivelSuporte}'],
    );
  }

  static pw.Widget _accessGrantBlock(ConcessaoAcessoModel grant) {
    final enabled = !grant.estaExpirada &&
        (grant.permiteLeituraMetas || grant.permiteEscritaDados);
    return _recordBlock(
      title: _profileLabel(grant.perfilAlvo),
      lines: [
        'Status: ${enabled ? 'Ativo' : 'Desativado ou expirado'}',
        'Leitura de metas/rotinas: ${grant.permiteLeituraMetas ? 'Permitida' : 'Bloqueada'}',
        'Escrita de dados: ${grant.permiteEscritaDados ? 'Permitida' : 'Bloqueada'}',
        'Expira em: ${_formatDateTime(grant.dataExpiracao)}',
      ],
    );
  }

  static pw.Widget _recordBlock({
    required String title,
    required List<String> lines,
  }) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          ...lines.map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Container(
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
  }

  static pw.Widget _emptyText(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 9),
        child: pw.Text(
          text,
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
        ),
      );

  static String _profileLabel(String profile) {
    switch (profile) {
      case escolaPerfilAlvo:
        return 'Escola';
      case especialistaPerfilAlvo:
        return 'Especialistas/Clínicas';
      default:
        return profile;
    }
  }

  static String _formatDateTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} às $hour:$minute';
  }
}
