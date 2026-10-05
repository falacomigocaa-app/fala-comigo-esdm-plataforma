import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/coleta_escola_store.dart';
import '../../domain/models/coleta_escola_model.dart';
import '../widgets/esdm_evolucao_chart.dart';

class EsdmDashboardScreen extends StatefulWidget {
  const EsdmDashboardScreen({super.key});

  @override
  State<EsdmDashboardScreen> createState() => _EsdmDashboardScreenState();
}

class _EsdmDashboardScreenState extends State<EsdmDashboardScreen> {
  bool _loading = true;
  Object? _error;
  List<EsdmEvolucaoPoint> _weeklyPoints = const [];
  String? _mostAutonomousBlock;
  double? _lastWeekAverage;
  int _lastWeekRecords = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await ColetaEscolaStore.loadAll();
      final analysis = _DashboardAnalysis.from(records);
      if (!mounted) return;
      setState(() {
        _weeklyPoints = analysis.weeklyPoints;
        _mostAutonomousBlock = analysis.mostAutonomousBlock;
        _lastWeekAverage = analysis.lastWeekAverage;
        _lastWeekRecords = analysis.lastWeekRecords;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gráficos e Relatórios de Evolução'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Não foi possível carregar os dados da evolução.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        const _IntroCard(),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Tendência semanal de autonomia',
          subtitle: 'Média de suporte empregado por semana',
          child: EsdmEvolucaoChart(points: _weeklyPoints),
        ),
        const SizedBox(height: 16),
        const Text(
          'Resumo da última semana',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _SummaryGrid(
          block: _mostAutonomousBlock,
          average: _lastWeekAverage,
          records: _lastWeekRecords,
        ),
        const SizedBox(height: 16),
        const Text(
          'Escala de autonomia',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Recusa = 0  •  Ajuda Física = 1  •  Ajuda Verbal = 2  •  Independente = 3',
          style: TextStyle(color: AppTheme.mutedText, height: 1.35),
        ),
        const SizedBox(height: 12),
        const Text(
          'A linha representa uma tendência descritiva dos registros escolares. Ela não substitui uma avaliação clínica ou uma análise funcional completa.',
          style: TextStyle(color: AppTheme.mutedText, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }
}

class _DashboardAnalysis {
  final List<EsdmEvolucaoPoint> weeklyPoints;
  final String? mostAutonomousBlock;
  final double? lastWeekAverage;
  final int lastWeekRecords;

  const _DashboardAnalysis({
    required this.weeklyPoints,
    required this.mostAutonomousBlock,
    required this.lastWeekAverage,
    required this.lastWeekRecords,
  });

  factory _DashboardAnalysis.from(List<ColetaEscolaModel> records) {
    final byWeek = <DateTime, List<ColetaEscolaModel>>{};
    for (final record in records) {
      final week = _weekStart(record.dataRegistro);
      byWeek.putIfAbsent(week, () => []).add(record);
    }

    final weeks = byWeek.keys.toList()..sort();
    final visibleWeeks = weeks.length > 8 ? weeks.sublist(weeks.length - 8) : weeks;
    final points = visibleWeeks
        .map(
          (week) => EsdmEvolucaoPoint(
            label: '${week.day.toString().padLeft(2, '0')}/${week.month.toString().padLeft(2, '0')}',
            averageSupport: _average(byWeek[week]!),
          ),
        )
        .toList();

    final now = DateTime.now();
    final lastWeekStart = now.subtract(const Duration(days: 7));
    final recent = records
        .where((record) => record.dataRegistro.isAfter(lastWeekStart))
        .toList();
    final byBlock = <String, List<ColetaEscolaModel>>{};
    for (final record in recent) {
      byBlock.putIfAbsent(record.blocoRotinaEscolar, () => []).add(record);
    }

    String? bestBlock;
    double? bestAverage;
    for (final entry in byBlock.entries) {
      final average = _average(entry.value);
      if (bestAverage == null || average > bestAverage) {
        bestAverage = average;
        bestBlock = entry.key;
      }
    }

    return _DashboardAnalysis(
      weeklyPoints: points,
      mostAutonomousBlock: bestBlock,
      lastWeekAverage: recent.isEmpty ? null : _average(recent),
      lastWeekRecords: recent.length,
    );
  }

  static DateTime _weekStart(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
  }

  static double _average(Iterable<ColetaEscolaModel> records) {
    if (records.isEmpty) return 0;
    final total = records.fold<double>(
      0,
      (sum, record) => sum + supportLevelValue(record.nivelSuporte),
    );
    return total / records.length;
  }
}

int supportLevelValue(String support) {
  switch (support) {
    case 'Independente':
      return 3;
    case 'Ajuda Verbal':
      return 2;
    case 'Ajuda Física':
      return 1;
    case 'Recusa':
    default:
      return 0;
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.professionalBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.show_chart, color: AppTheme.professionalAccent, size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Acompanhe mudanças de autonomia com base nos registros rápidos feitos na rotina escolar.',
              style: TextStyle(color: Colors.white, height: 1.35, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppTheme.mutedText)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final String? block;
  final double? average;
  final int records;

  const _SummaryGrid({
    required this.block,
    required this.average,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              width: itemWidth,
              icon: Icons.place_outlined,
              label: 'Maior autonomia detectada no',
              value: block ?? 'Ainda sem dados',
            ),
            _SummaryCard(
              width: itemWidth,
              icon: Icons.speed_outlined,
              label: 'Média de autonomia',
              value: average == null ? '—' : '${average!.toStringAsFixed(1)} / 3',
            ),
            _SummaryCard(
              width: itemWidth,
              icon: Icons.fact_check_outlined,
              label: 'Coletas na última semana',
              value: '$records',
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;

  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(height: 10),
              Text(label, style: const TextStyle(color: AppTheme.mutedText, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
