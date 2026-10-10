import 'package:flutter/services.dart';
import '../../../../core/services/communication_board_pdf_service.dart';
import '../../../../core/services/parental_session_service.dart';
import '../../../aac_grid/domain/models/pictogram_card.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/services/secure_box_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../aac_grid/data/providers/visual_routine_provider.dart';

class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

enum ExportPeriod { sevenDays, thirtyDays, all }

class _DataExportScreenState extends State<DataExportScreen> {
  Box? _behaviorBox;
  Box? _videoBox;
  Map<String, dynamic>? _profile;
  List<VisualRoutineItem> _routine = [];
  ExportPeriod _period = ExportPeriod.sevenDays;
  bool _includeProfile = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final behavior = await SecureBoxService.openSecureBox('behavior_logs');
    final video = await SecureBoxService.openSecureBox('video_diary');
    final profileBox = await SecureBoxService.openSecureBox('patient_profile');
    final profile = profileBox.get('data');
    final routine = await VisualRoutineStore.load();
    if (!mounted) return;
    setState(() {
      _behaviorBox = behavior;
      _videoBox = video;
      _profile = profile is Map ? Map<String, dynamic>.from(profile) : null;
      _routine = routine;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _entries {
    final values = _behaviorBox?.values ?? const [];
    final all = values
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => _inPeriod(entry['timestamp']))
        .toList();
    all.sort((a, b) => '${b['timestamp']}'.compareTo('${a['timestamp']}'));
    return all;
  }

  bool _inPeriod(dynamic value) {
    if (_period == ExportPeriod.all) return true;
    final date = DateTime.tryParse('$value');
    if (date == null) return false;
    final days = _period == ExportPeriod.sevenDays ? 7 : 30;
    return date.isAfter(DateTime.now().subtract(Duration(days: days)));
  }

  String _periodLabel() => switch (_period) {
        ExportPeriod.sevenDays => 'últimos 7 dias',
        ExportPeriod.thirtyDays => 'últimos 30 dias',
        ExportPeriod.all => 'todo o período disponível',
      };

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse('$value');
    if (date == null) return 'Data não informada';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month às $hour:$minute';
  }

  List<pw.Widget> _profileSection() {
    if (!_includeProfile || _profile == null) return [];
    final fields = <String>[
      if ('${_profile?['name'] ?? ''}'.isNotEmpty) 'Nome: ${_profile?['name']}',
      if ('${_profile?['guardian'] ?? ''}'.isNotEmpty)
        'Responsável: ${_profile?['guardian']}',
      if ('${_profile?['school'] ?? ''}'.isNotEmpty)
        'Escola/clínica: ${_profile?['school']}',
    ];
    if (fields.isEmpty) return [];
    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Perfil informado',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            ...fields.map(pw.Text.new),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
    ];
  }

  pw.Widget _footerNote() => pw.Text(
        'Dados exportados do aparelho por escolha do responsável. Este documento não é diagnóstico, avaliação clínica ou previsão de evolução.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      );

  Future<void> _share(pw.Document document, String filename) async {
    await Printing.sharePdf(bytes: await document.save(), filename: filename);
  }

  Future<void> _exportSummary() async {
    final doc = pw.Document();
    final completed = _routine.where((item) => item.completed).length;
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Fala Comigo — Resumo local')),
          pw.Text('Gerado em ${_formatDate(DateTime.now().toIso8601String())}'),
          pw.SizedBox(height: 12),
          ..._profileSection(),
          pw.Text('Período: ${_periodLabel()}'),
          pw.SizedBox(height: 8),
          pw.Bullet(text: 'Registros ABC: ${_entries.length}'),
          pw.Bullet(
            text: 'Vídeos armazenados localmente: ${_videoBox?.length ?? 0}',
          ),
          pw.Bullet(text: 'Passos da rotina visual: ${_routine.length}'),
          pw.Bullet(text: 'Passos marcados na rotina: $completed'),
          pw.SizedBox(height: 16),
          pw.Text(
            'Registros recentes',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (_entries.isEmpty) pw.Text('Nenhum registro ABC no período.'),
          ..._entries.take(10).map(
                (entry) => pw.Container(
                  margin: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(
                    '${_formatDate(entry['timestamp'])} — ${entry['behavior'] ?? 'Sem descrição'}',
                  ),
                ),
              ),
          pw.SizedBox(height: 16),
          _footerNote(),
        ],
      ),
    );
    await _share(doc, 'resumo_fala_comigo.pdf');
  }

  Future<void> _exportAbc() async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Fala Comigo — Registros ABC')),
          pw.Text('Período: ${_periodLabel()}'),
          pw.SizedBox(height: 10),
          ..._profileSection(),
          if (_entries.isEmpty) pw.Text('Nenhum registro ABC no período.'),
          ..._entries.map(
            (entry) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _formatDate(entry['timestamp']),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Antecedente: ${entry['antecedent'] ?? ''}'),
                  pw.Text('Comportamento: ${entry['behavior'] ?? ''}'),
                  pw.Text('Apoio/consequência: ${entry['consequence'] ?? ''}'),
                  if ('${entry['notes'] ?? ''}'.isNotEmpty)
                    pw.Text('Notas: ${entry['notes']}'),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          _footerNote(),
        ],
      ),
    );
    await _share(doc, 'registros_abc_fala_comigo.pdf');
  }

  Future<void> _exportRoutine() async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text('Fala Comigo — Rotina visual')),
          pw.Text('Estado salvo no aparelho no momento da exportação.'),
          pw.SizedBox(height: 12),
          ..._profileSection(),
          if (_routine.isEmpty) pw.Text('Nenhum passo configurado.'),
          ..._routine.asMap().entries.map(
                (entry) => pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Text(
                    '${entry.key + 1}. ${entry.value.emoji} ${entry.value.title} — ${entry.value.completed ? 'concluído por agora' : 'não marcado'}',
                  ),
                ),
              ),
          pw.SizedBox(height: 8),
          _footerNote(),
        ],
      ),
    );
    await _share(doc, 'rotina_visual_fala_comigo.pdf');
  }

  bool _exportingBoard = false;

  Future<void> _exportBoard() async {
    if (_exportingBoard) return;
    _exportingBoard = true;
    try {
      ParentalSessionService.requireAuthenticated();
      final box = await SecureBoxService.openSecureBox<PictogramCard>(
          'pictogram_cards');
      // Personal photos need a separate explicit choice before entering a PDF.
      final cards = box.values.where((card) => !card.isCustomImage).toList();
      final bytes = await CommunicationBoardPdfService.generate(
        cards: cards,
        loadImage: (card) async =>
            (await rootBundle.load(card.imagePath)).buffer.asUint8List(),
      );
      ParentalSessionService.requireAuthenticated();
      await Printing.sharePdf(
          bytes: bytes, filename: 'prancha_fala_comigo.pdf');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Não foi possível gerar a prancha. Confira a sessão e os cartões disponíveis.')),
        );
      }
    } finally {
      _exportingBoard = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Exportar relatórios'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.professionalBackground,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.picture_as_pdf_outlined,
                        color: AppTheme.professionalAccent,
                        size: 28,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Escolha exatamente o relatório que deseja compartilhar. Nada é enviado automaticamente.',
                          style: TextStyle(
                            color: Colors.white,
                            height: 1.35,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Período dos registros ABC',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                DropdownButtonFormField<ExportPeriod>(
                  initialValue: _period,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    helperText: 'A rotina visual sempre mostra o estado atual.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ExportPeriod.sevenDays,
                      child: Text('Últimos 7 dias'),
                    ),
                    DropdownMenuItem(
                      value: ExportPeriod.thirtyDays,
                      child: Text('Últimos 30 dias'),
                    ),
                    DropdownMenuItem(
                      value: ExportPeriod.all,
                      child: Text('Todo o período disponível'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _period = value);
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeProfile,
                  onChanged: (value) =>
                      setState(() => _includeProfile = value ?? false),
                  title: const Text('Incluir dados identificadores'),
                  subtitle: const Text(
                    'Desmarcado por padrão: nome, responsável e escola/clínica.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                _ExportCard(
                  icon: Icons.grid_view,
                  title: 'Prancha de comunicação para imprimir',
                  description:
                      'Cartões sem fotos pessoais, na ordem da grade. Uma alternativa em papel para quando o aparelho não estiver disponível.',
                  onExport: _exportBoard,
                ),
                _ExportCard(
                  icon: Icons.insights_outlined,
                  title: 'Resumo de progresso',
                  description:
                      'Contagens locais, registros recentes, vídeos e rotina.',
                  onExport: _exportSummary,
                ),
                _ExportCard(
                  icon: Icons.fact_check_outlined,
                  title: 'Registros ABC',
                  description:
                      'Antecedente, comportamento, apoio e notas do período.',
                  onExport: _exportAbc,
                ),
                _ExportCard(
                  icon: Icons.view_timeline_outlined,
                  title: 'Rotina visual',
                  description:
                      'Passos configurados e estado atual de cada item.',
                  onExport: _exportRoutine,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Antes de compartilhar, confirme o destinatário. Depois de sair do aplicativo, cópias do PDF podem permanecer em outros serviços.',
                  style: TextStyle(color: AppTheme.mutedText, height: 1.35),
                ),
              ],
            ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onExport;

  const _ExportCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: AppTheme.primary, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(description),
        trailing: IconButton(
          onPressed: onExport,
          icon: const Icon(Icons.ios_share_outlined),
          tooltip: 'Compartilhar PDF',
        ),
        onTap: onExport,
      ),
    );
  }
}
