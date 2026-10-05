import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/transition_alert_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../transition_alerts/data/providers/transition_alerts_provider.dart';
import '../../../transition_alerts/domain/models/transition_alert.dart';
import 'transition_alert_edit_screen.dart';

/// Lista os Alertas de Transição de Atividade cadastrados, permite
/// criar novos, editar, excluir e disparar cada um imediatamente.
class TransitionAlertsListScreen extends ConsumerWidget {
  const TransitionAlertsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(transitionAlertsListProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Alertas de Transição'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TransitionAlertEditScreen()),
        ),
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Novo alerta'),
        backgroundColor: AppTheme.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Para os alertas funcionarem mesmo com a tela bloqueada, '
                      'autorize as permissões do celular (uma vez só).',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.mutedText,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await TransitionAlertService.instance
                            .requestPermissions();
                        final status = await TransitionAlertService.instance
                            .checkPermissionStatus();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(status),
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Não foi possível configurar as permissões.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Autorizar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'Nenhum alerta criado ainda.\nToque em "Novo alerta" para começar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          for (final alert in alerts) _AlertCard(alert: alert),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  final TransitionAlert alert;

  const _AlertCard({required this.alert});

  String _scheduleSummary() {
    if (!alert.isScheduled || alert.scheduledWeekdays.isEmpty) {
      return 'Somente disparo manual';
    }
    const labels = {
      1: 'Dom',
      2: 'Seg',
      3: 'Ter',
      4: 'Qua',
      5: 'Qui',
      6: 'Sex',
      7: 'Sáb',
    };
    final days = alert.scheduledWeekdays.map((d) => labels[d] ?? '').join(', ');
    final hour = (alert.scheduledHour ?? 0).toString().padLeft(2, '0');
    final minute = (alert.scheduledMinute ?? 0).toString().padLeft(2, '0');
    return '$days às $hour:$minute';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(
          Icons.notifications_active_outlined,
          color: AppTheme.primary,
        ),
        title: Text(alert.title.isEmpty ? '(sem título)' : alert.title),
        subtitle: Text(
          '${alert.audioType == 'gravado' ? 'Áudio gravado' : 'Texto falado'} • '
          '${_scheduleSummary()} • ${alert.checklistItems.length} itens no checklist',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransitionAlertEditScreen(existingAlert: alert),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.play_circle_outline,
                color: AppTheme.accentGreen,
              ),
              tooltip: 'Testar agora',
              onPressed: () async {
                try {
                  await TransitionAlertService.instance.triggerNow(alert);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Notificação disparada! Verifique a barra de notificações.',
                        ),
                      ),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Não foi possível disparar o alerta.'),
                      ),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Excluir',
              onPressed: () async {
                await TransitionAlertService.instance.cancelSchedule(alert);
                await ref
                    .read(transitionAlertsListProvider.notifier)
                    .removeAlert(alert.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}
