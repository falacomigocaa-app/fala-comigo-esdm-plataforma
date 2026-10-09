import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../aac_grid/data/providers/cards_provider.dart';
import '../../../aac_grid/presentation/screens/visual_routine_screen.dart';
import '../../../transition_alerts/data/providers/transition_alerts_provider.dart';
import 'add_card_screen.dart';
import 'behavior_log_screen.dart';
import 'data_export_screen.dart';
import 'progress_report_screen.dart';
import 'transition_alerts_list_screen.dart';
import 'weekly_trends_screen.dart';

class ParentalDashboardScreen extends ConsumerWidget {
  final VoidCallback onOpenTracking;
  final VoidCallback onOpenLocation;

  const ParentalDashboardScreen({
    super.key,
    required this.onOpenTracking,
    required this.onOpenLocation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsListProvider);
    final alerts = ref.watch(transitionAlertsListProvider);
    final activeAlerts = alerts.where((alert) => alert.isScheduled).length;

    return ListView(
      key: const ValueKey('parental-dashboard'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _DashboardWelcome(onOpenLocation: onOpenLocation),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DashboardMetric(
                icon: Icons.grid_view_rounded,
                label: 'Cartões',
                value: '${cards.length}',
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DashboardMetric(
                icon: Icons.alarm_on_outlined,
                label: 'Alertas ativos',
                value: '$activeAlerts',
                color: const Color(0xFFB45309),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _DashboardSectionTitle(
          eyebrow: 'ACESSO RÁPIDO',
          title: 'O que você precisa fazer hoje?',
        ),
        const SizedBox(height: 10),
        _QuickActionGrid(
          onNewCard: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddCardScreen()),
          ),
          onRegister: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BehaviorLogScreen()),
          ),
          onReport: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProgressReportScreen()),
          ),
          onAlerts: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const TransitionAlertsListScreen()),
          ),
        ),
        const SizedBox(height: 18),
        _DashboardPriorityCard(
          icon: Icons.track_changes_rounded,
          color: const Color(0xFF15803D),
          title: 'Acompanhamento & rotina',
          description:
              'Veja tendências, rotina visual e registros recentes em um só lugar.',
          actionLabel: 'Abrir acompanhamento',
          onTap: onOpenTracking,
        ),
        const SizedBox(height: 10),
        _DashboardPriorityCard(
          icon: Icons.location_on_outlined,
          color: AppTheme.primary,
          title: 'Localização segura',
          description:
              'O compartilhamento está desativado até que consentimento e permissões sejam configurados.',
          actionLabel: 'Ver segurança',
          onTap: onOpenLocation,
        ),
        const SizedBox(height: 18),
        const _DashboardSectionTitle(
          eyebrow: 'VISÃO GERAL',
          title: 'Tudo organizado para o cuidado',
        ),
        const SizedBox(height: 10),
        const _DashboardOverviewCard(),
      ],
    );
  }
}

class ParentalTrackingScreen extends StatelessWidget {
  const ParentalTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('parental-tracking'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const _DashboardSectionTitle(
          eyebrow: 'ACOMPANHAMENTO',
          title: 'Progresso e rotina',
          description:
              'Acesse os registros mais usados sem percorrer toda a configuração.',
        ),
        const SizedBox(height: 16),
        _TrackingAction(
          icon: Icons.show_chart_outlined,
          color: AppTheme.primary,
          title: 'Tendências semanais',
          subtitle: 'Observar padrões nos registros ABC',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WeeklyTrendsScreen()),
          ),
        ),
        _TrackingAction(
          icon: Icons.view_timeline_outlined,
          color: const Color(0xFF15803D),
          title: 'Rotina visual diária',
          subtitle: 'Organizar os próximos passos da criança',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const VisualRoutineScreen(readOnly: false)),
          ),
        ),
        _TrackingAction(
          icon: Icons.picture_as_pdf_outlined,
          color: const Color(0xFFBE123C),
          title: 'Relatórios em PDF',
          subtitle: 'Exportar um resumo para a rede de cuidado',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DataExportScreen()),
          ),
        ),
        _TrackingAction(
          icon: Icons.alarm_on_outlined,
          color: const Color(0xFFB45309),
          title: 'Alertas de transição',
          subtitle: 'Preparar mudanças com previsibilidade',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const TransitionAlertsListScreen()),
          ),
        ),
      ],
    );
  }
}

class ParentalLocationScreen extends StatelessWidget {
  final VoidCallback onConnect;

  const ParentalLocationScreen({super.key, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('parental-location'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const _DashboardSectionTitle(
          eyebrow: 'SEGURANÇA',
          title: 'Localização da criança',
          description:
              'O compartilhamento só será ativado com consentimento e permissões explícitas.',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFC9D9F7)),
          ),
          child: Column(
            children: [
              const Icon(Icons.location_disabled_outlined,
                  size: 48, color: AppTheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Nenhuma localização compartilhada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'O mapa em tempo real ainda não está conectado. Nenhuma localização é inventada ou enviada sem configuração segura.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedText, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Ver requisitos de segurança'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardWelcome extends StatelessWidget {
  final VoidCallback onOpenLocation;

  const _DashboardWelcome({required this.onOpenLocation});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppTheme.professionalBackground,
            AppTheme.professionalSurface
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wb_sunny_outlined,
              color: AppTheme.professionalAccent, size: 30),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PAINEL DE CUIDADO',
                    style: TextStyle(
                        color: AppTheme.professionalAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1)),
                SizedBox(height: 6),
                Text('Tudo pronto para acompanhar a criança?',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.15)),
                SizedBox(height: 7),
                Text(
                    'Registre momentos importantes e mantenha a rotina previsível.',
                    style: TextStyle(color: Colors.white70, height: 1.35)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Segurança e localização',
            onPressed: onOpenLocation,
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DashboardMetric(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.mutedText, fontSize: 12))
              ])),
        ],
      ),
    );
  }
}

class _DashboardSectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? description;

  const _DashboardSectionTitle(
      {required this.eyebrow, required this.title, this.description});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eyebrow,
          style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.05)),
      const SizedBox(height: 4),
      Text(title,
          style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark)),
      if (description != null) ...[
        const SizedBox(height: 5),
        Text(description!,
            style: const TextStyle(color: AppTheme.mutedText, height: 1.35))
      ],
    ]);
  }
}

class _QuickActionGrid extends StatelessWidget {
  final VoidCallback onNewCard;
  final VoidCallback onRegister;
  final VoidCallback onReport;
  final VoidCallback onAlerts;

  const _QuickActionGrid(
      {required this.onNewCard,
      required this.onRegister,
      required this.onReport,
      required this.onAlerts});

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.add_a_photo_outlined, 'Novo cartão', onNewCard, AppTheme.primary),
      (
        Icons.fact_check_outlined,
        'Novo registro',
        onRegister,
        const Color(0xFF15803D)
      ),
      (
        Icons.picture_as_pdf_outlined,
        'Relatório',
        onReport,
        const Color(0xFFBE123C)
      ),
      (Icons.alarm_on_outlined, 'Alertas', onAlerts, const Color(0xFFB45309)),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.7,
      children: actions
          .map((action) => _QuickAction(
              icon: action.$1,
              label: action.$2,
              onTap: action.$3,
              color: action.$4))
          .toList(),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.onTap,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 20),
        label: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: BorderSide(color: color.withValues(alpha: 0.25)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15))));
  }
}

class _DashboardPriorityCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onTap;

  const _DashboardPriorityCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.description,
      required this.actionLabel,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Row(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(
                        color: AppTheme.mutedText, fontSize: 12, height: 1.3)),
                const SizedBox(height: 8),
                Align(
                    alignment: Alignment.centerLeft,
                    child:
                        TextButton(onPressed: onTap, child: Text(actionLabel)))
              ]))
        ]));
  }
}

class _DashboardOverviewCard extends StatelessWidget {
  const _DashboardOverviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder)),
        child: const Column(children: [
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.check_circle_outline, color: AppTheme.accentGreen),
              title: Text('Área parental protegida',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Sessão local autenticada neste aparelho.')),
          Divider(height: 4),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.insights_outlined, color: AppTheme.primary),
              title: Text('Acompanhamento disponível',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'Registros, rotina e relatórios ficam acessíveis pelas ações rápidas.'))
        ]));
  }
}

class _TrackingAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TrackingAction(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppTheme.cardBorder)),
        child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            leading: Icon(icon, color: color, size: 28),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onTap));
  }
}
