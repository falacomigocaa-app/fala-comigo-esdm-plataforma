import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/hyperfocus_theme.dart';
import '../../../../core/services/app_orientation_service.dart';
import '../../../../core/services/data_wipe_service.dart';
import '../../../aac_grid/data/providers/cards_provider.dart';
import '../../../aac_grid/domain/models/pictogram_card.dart';
import 'add_card_screen.dart';
import 'behavior_log_screen.dart';

import 'video_diary_screen.dart';
import 'patient_profile_screen.dart';
import 'parent_reminders_screen.dart';
import 'shared_tasks_screen.dart';
import 'care_coordination_screen.dart';
import 'change_pin_screen.dart';
import 'data_export_screen.dart';
import 'access_management_screen.dart';
import 'parental_gate_screen.dart';
import 'plan_status_screen.dart';
import 'privacy_settings_screen.dart';
import 'progress_report_screen.dart';
import 'transition_alerts_list_screen.dart';
import 'weekly_trends_screen.dart';
import 'parental_dashboard_screen.dart';
import '../../../transition_alerts/data/providers/transition_alerts_provider.dart';
import '../../../aac_grid/presentation/screens/visual_routine_screen.dart';
import '../../../../core/widgets/secure_media_image.dart';

/// Painel dos Pais & Educadores.
///
/// Permite:
/// - Adicionar, editar e reordenar cartões (arraste para reordenar);
/// - Ajustar o tamanho dos botões da grade;
/// - Escolher o tema visual de hiperfoco da criança;
/// - Remover cartões existentes.
///
/// Ao sair desta tela (voltando para a comunicação da criança), a
/// orientação volta a ser travada em paisagem.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedTab = 0;

  Future<void> _deleteAllLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar todos os dados?'),
        content: const Text(
          'Esta ação remove cartões personalizados, perfil, registros, vídeos, áudios, configurações e o PIN deste aparelho. Não pode ser desfeita pelo aplicativo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await DataWipeService.deleteAllLocalData();
      if (!result.notificationsCancelled && mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Dados locais apagados'),
            content: const Text(
              'O Fala Comigo não conseguiu cancelar todas as notificações do sistema. Um lembrete genérico pode continuar agendado. Para removê-lo, confira as notificações do Fala Comigo nas configurações do aparelho.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A exclusão não foi concluída por completo. Alguns dados podem ter permanecido; tente novamente para finalizar.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    ref.invalidate(cardsBoxProvider);
    ref.invalidate(cardsListProvider);
    ref.invalidate(transitionAlertsListProvider);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ParentalGateScreen()),
      (route) => route.isFirst,
    );
  }

  @override
  void dispose() {
    AppOrientationService.applyChildOrientation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(cardsListProvider);
    final scale = ref.watch(buttonScaleProvider);
    final tapBehavior = ref.watch(cardTapBehaviorProvider);
    final currentTheme = ref.watch(hyperfocusThemeProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Área Parental'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton.filledTonal(
            tooltip: 'Novo cartão',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AddCardScreen())),
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (_selectedTab) {
        0 => ParentalDashboardScreen(
            onOpenTracking: () => setState(() => _selectedTab = 1),
            onOpenLocation: () => setState(() => _selectedTab = 2),
          ),
        1 => const ParentalTrackingScreen(),
        2 => ParentalLocationScreen(onConnect: _showLocationRoadmap),
        _ => _buildSettingsBody(cards, scale, tapBehavior, currentTheme),
      },
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.mutedText,
        onTap: (index) => setState(() => _selectedTab = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Início',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.track_changes_outlined),
            label: 'Acompanhamento',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on_outlined),
            label: 'Localização',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Configurações',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsBody(
    List<PictogramCard> cards,
    double scale,
    CardTapBehavior tapBehavior,
    HyperfocusTheme currentTheme,
  ) =>
      ListView(
        key: const ValueKey('parental-settings'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const _SettingsHero(),
          const SizedBox(height: 16),
          _LocationHeroCard(onConnect: _showLocationRoadmap),
          const SizedBox(height: 16),
          _OptionASectionBox(
            icon: Icons.track_changes_rounded,
            title: 'Acompanhamento & Rotina',
            description: 'Rotina, vídeos, alertas, tendências e relatórios.',
            initiallyExpanded: true,
            child: _OptionARoutineGrid(),
          ),
          const SizedBox(height: 12),
          _OptionASectionBox(
            icon: Icons.accessibility_new_outlined,
            title: 'Acessibilidade da Comunicação',
            description: 'Tamanho dos botões, voz e montagem de frases.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tamanho dos botões',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Slider(
                  value: scale,
                  min: 0.8,
                  max: 1.6,
                  divisions: 8,
                  label: '${(scale * 100).round()}%',
                  activeColor: AppTheme.primary,
                  onChanged: (v) =>
                      ref.read(buttonScaleProvider.notifier).setScale(v),
                  onChangeEnd: (_) async {
                    try {
                      await ref.read(buttonScaleProvider.notifier).persist();
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Não foi possível salvar o tamanho dos botões.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ao tocar em um cartão',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Escolha se o toque fala, monta uma mensagem ou faz as duas coisas.',
                  style: TextStyle(fontSize: 13, color: AppTheme.mutedText),
                ),
                RadioGroup<CardTapBehavior>(
                  groupValue: tapBehavior,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(cardTapBehaviorProvider.notifier)
                          .setBehavior(value);
                    }
                  },
                  child: const Column(
                    children: [
                      RadioListTile<CardTapBehavior>(
                        contentPadding: EdgeInsets.zero,
                        value: CardTapBehavior.speakAndAdd,
                        title: Text('Falar e adicionar à frase'),
                      ),
                      RadioListTile<CardTapBehavior>(
                        contentPadding: EdgeInsets.zero,
                        value: CardTapBehavior.addOnly,
                        title: Text('Adicionar sem falar'),
                      ),
                      RadioListTile<CardTapBehavior>(
                        contentPadding: EdgeInsets.zero,
                        value: CardTapBehavior.speakOnly,
                        title: Text('Falar sem adicionar à frase'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OptionASectionBox(
            icon: Icons.tune_rounded,
            title: 'Personalização da experiência',
            description: 'Tema visual e orientação da tela da criança.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tema e estímulos visuais',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 122,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: HyperfocusTheme.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final theme = HyperfocusTheme.values[index];
                      return _ThemePreviewTile(
                        theme: theme,
                        selected: theme == currentTheme,
                        onTap: () => ref
                            .read(hyperfocusThemeProvider.notifier)
                            .setTheme(theme),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _SelectedThemePreview(theme: currentTheme),
                const SizedBox(height: 18),
                const Text(
                  'Orientação da tela da criança',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'A paisagem é recomendada para mostrar cartões maiores. Escolha vertical se o aparelho for usado normalmente em pé.',
                  style: TextStyle(fontSize: 13, color: AppTheme.mutedText),
                ),
                const SizedBox(height: 8),
                _ChildOrientationSelector(
                  selected: ref.watch(childOrientationProvider),
                  onChanged: (orientation) => ref
                      .read(childOrientationProvider.notifier)
                      .setOrientation(orientation),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OptionASectionBox(
            icon: Icons.insights_outlined,
            title: 'Registros, alertas e relatórios',
            description: 'ABC, progresso, vídeos, lembretes e exportações.',
            child: Column(
              children: [
                _OptionAListAction(
                  icon: Icons.fact_check_outlined,
                  title: 'Registro de Comportamento',
                  subtitle: 'Registrar gatilhos no modelo ABC',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BehaviorLogScreen(),
                    ),
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.insights_outlined,
                  title: 'Relatórios de progresso',
                  subtitle: 'Ver resumo local e exportar dados',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProgressReportScreen(),
                    ),
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.alarm_on_outlined,
                  title: 'Alertas de Transição',
                  subtitle: 'Avisar antes de mudar de atividade',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TransitionAlertsListScreen(),
                    ),
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.notifications_none_outlined,
                  title: 'Lembretes do responsável',
                  subtitle: 'Agendar avisos locais',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ParentRemindersScreen(),
                    ),
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.add_task_outlined,
                  title: 'Tarefas compartilhadas',
                  subtitle: 'Combinar próximos passos com a rede de cuidado',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SharedTasksScreen(),
                    ),
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.hub_outlined,
                  title: 'Continuidade do cuidado',
                  subtitle: 'Perfil funcional, plano de comunicação e agenda',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CareCoordinationScreen(),
                    ),
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.school_outlined,
                  title: 'Coleta rápida da escola',
                  subtitle: 'Registrar uma observação em poucos toques',
                  onTap: () => Navigator.of(context).pushNamed(
                    '/coleta-escola',
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Gerenciar Acessos e Permissões',
                  subtitle: 'Controlar o acesso da escola e de especialistas',
                  onTap: () => Navigator.of(context).pushNamed(
                    '/painel-consentimento',
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.track_changes_outlined,
                  title: 'Plano de Metas Desenvolvimento (ESDM)',
                  subtitle: 'Traduzir metas clínicas em missões para a família',
                  onTap: () => Navigator.of(context).pushNamed(
                    '/metas-esdm',
                  ),
                ),
                _OptionAListAction(
                  icon: Icons.show_chart_outlined,
                  title: 'Gráficos e Relatórios de Evolução',
                  subtitle: 'Acompanhar tendências de autonomia por semana',
                  onTap: () => Navigator.of(context).pushNamed(
                    '/esdm-dashboard',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OptionASectionBox(
            icon: Icons.grid_view_rounded,
            title: 'Cartões de comunicação',
            description: 'Adicione, edite ou reordene os cartões da criança.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cartões cadastrados (${cards.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Segure e arraste um cartão para reordenar.',
                  style: TextStyle(fontSize: 12, color: AppTheme.mutedText),
                ),
                const SizedBox(height: 8),
                if (cards.isNotEmpty) ...[
                  _CardsPreviewStrip(cards: cards),
                  const SizedBox(height: 14),
                ],
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  // Flutter 3.38 (a versão mínima do app) ainda usa este callback.
                  // ignore: deprecated_member_use
                  onReorder: (oldIndex, newIndex) => ref
                      .read(cardsListProvider.notifier)
                      .reorderCards(oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final card = cards[index];
                    return Card(
                      key: ValueKey(card.id),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(
                          Icons.drag_indicator,
                          color: AppTheme.mutedText,
                        ),
                        title: Text(card.label),
                        subtitle: Text(card.category),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: AppTheme.primary,
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AddCardScreen(existingCard: card),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => ref
                                  .read(cardsListProvider.notifier)
                                  .removeCard(card.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Conta, plano e privacidade',
            description: 'Proteções, perfil, PIN e dados locais.',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Plano e recursos'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlanStatusScreen()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Perfil do Paciente'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PatientProfileScreen(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacidade e dados'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacySettingsScreen(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('Pessoas e organizações'),
                  subtitle: const Text('Quem pode acessar?'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AccessManagementScreen(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_reset_outlined),
                  title: const Text('Trocar PIN'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChangePinScreen()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text('Apagar todos os dados'),
                  onTap: _deleteAllLocalData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      );

  void _showLocationRoadmap() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Localização segura'),
        content: const Text(
          'O mapa em tempo real será conectado ao painel web autenticado somente depois de configurar consentimento, permissão de localização no aparelho da criança e sincronização segura. Até lá, nenhum local é inventado ou enviado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}

class _ChildOrientationSelector extends StatelessWidget {
  final ChildOrientation selected;
  final ValueChanged<ChildOrientation> onChanged;

  const _ChildOrientationSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        const options = ChildOrientation.values;
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < options.length; index++) ...[
                _buildCompactOption(options[index]),
                if (index < options.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }

        return SegmentedButton<ChildOrientation>(
          segments: options
              .map(
                (orientation) => ButtonSegment<ChildOrientation>(
                  value: orientation,
                  icon: Text(childOrientationIcon(orientation)),
                  label: Text(childOrientationLabel(orientation)),
                ),
              )
              .toList(),
          selected: {selected},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onChanged(selection.first);
          },
        );
      },
    );
  }

  Widget _buildCompactOption(ChildOrientation orientation) {
    final isSelected = orientation == selected;
    final label = childOrientationLabel(orientation);
    final icon = Text(childOrientationIcon(orientation));
    final button = isSelected
        ? FilledButton.icon(
            onPressed: () => onChanged(orientation),
            icon: icon,
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: () => onChanged(orientation),
            icon: icon,
            label: Text(label),
          );

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Orientação $label',
      child: SizedBox(
        width: double.infinity,
        child: button,
      ),
    );
  }
}

class _CardsPreviewStrip extends StatelessWidget {
  final List<PictogramCard> cards;

  const _CardsPreviewStrip({required this.cards});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('cards-visual-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preview da grade infantil',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 126,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) => _CardPreviewTile(card: cards[index]),
          ),
        ),
      ],
    );
  }
}

class _CardPreviewTile extends StatelessWidget {
  final PictogramCard card;

  const _CardPreviewTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final image = card.isCustomImage
        ? SecureMediaImage(path: card.imagePath)
        : Image.asset(
            card.imagePath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.image_not_supported_outlined,
              color: AppTheme.mutedText,
            ),
          );
    return Semantics(
      label: 'Preview do cartão ${card.label}',
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: double.infinity, child: image),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreviewTile extends StatelessWidget {
  final HyperfocusTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePreviewTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema ${theme.displayName}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 104,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? theme.primaryColor : AppTheme.cardBorder,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(theme.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 5),
              Text(
                theme.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (selected) ...[
                const SizedBox(height: 3),
                Icon(Icons.check_circle, size: 15, color: theme.primaryColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedThemePreview extends StatelessWidget {
  final HyperfocusTheme theme;

  const _SelectedThemePreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('selected-theme-preview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(theme.emoji, style: const TextStyle(fontSize: 29)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prévia em tempo real',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Tema ${theme.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                const Text(
                  'A criança verá esta combinação suave de cor e estímulo.',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionASectionBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;
  final bool initiallyExpanded;

  const _OptionASectionBox({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppTheme.cardBorder),
      ),
      child: ExpansionTile(
        key: ValueKey('settings-section-$title'),
        initiallyExpanded: initiallyExpanded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: _IconBubble(icon: icon, color: AppTheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(description, style: const TextStyle(fontSize: 12)),
        children: [child],
      ),
    );
  }
}

class _OptionARoutineGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      _OptionAFeature(
        icon: Icons.view_timeline_outlined,
        title: 'Rotina visual diária',
        subtitle: 'Organizar passos',
        color: const Color(0xFF15803D),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const VisualRoutineScreen(readOnly: false),
          ),
        ),
      ),
      _OptionAFeature(
        icon: Icons.videocam_outlined,
        title: 'Diário de vídeo',
        subtitle: 'Registrar momentos',
        color: const Color(0xFF7A5FC7),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const VideoDiaryScreen())),
      ),
      _OptionAFeature(
        icon: Icons.alarm_on_outlined,
        title: 'Alertas de transição',
        subtitle: 'Preparar mudanças',
        color: const Color(0xFFB45309),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TransitionAlertsListScreen()),
        ),
      ),
      _OptionAFeature(
        icon: Icons.insights_outlined,
        title: 'Tendências semanais',
        subtitle: 'Registros ABC',
        color: AppTheme.primary,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WeeklyTrendsScreen())),
      ),
      _OptionAFeature(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Relatórios em PDF',
        subtitle: 'Resumo, ABC ou rotina',
        color: const Color(0xFFBE123C),
        wide: true,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DataExportScreen())),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => SizedBox(
                  width: item.wide ? constraints.maxWidth : width,
                  child: item,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _OptionAFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool wide;

  const _OptionAFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: _IconBubble(icon: icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: AppTheme.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionAListAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionAListAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
      onTap: onTap,
    );
  }
}

class _LocationHeroCard extends StatelessWidget {
  final VoidCallback onConnect;

  const _LocationHeroCard({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFC9D9F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBubble(
                icon: Icons.location_on_rounded,
                color: Color(0xFF315BFF),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Localização & Segurança',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Módulo web autenticado em preparação',
                      style: TextStyle(color: AppTheme.mutedText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.mutedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 148,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE8F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                CustomPaint(painter: _MapPreviewPainter()),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x3314253D), blurRadius: 12),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: AppTheme.mutedText,
                      size: 28,
                    ),
                  ),
                ),
                const Positioned(
                  left: 14,
                  bottom: 12,
                  child: Text(
                    'Nenhuma localização compartilhada',
                    style: TextStyle(
                      color: AppTheme.mutedText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Para proteger a criança, este painel só mostrará local, atualização e bateria depois que a família ativar o consentimento e a conexão segura do aparelho.',
            style: TextStyle(color: AppTheme.mutedText, height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Ver como a conexão será feita'),
          ),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBubble({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _MapPreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x5580A4C7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var x = 0.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x + 70, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 12), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppTheme.professionalBackground,
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [
            AppTheme.professionalBackground,
            AppTheme.professionalSurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F14213D),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.professionalAccent,
            child: Icon(
              Icons.shield_outlined,
              color: AppTheme.professionalBackground,
            ),
          ),
          SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAINEL DO RESPONSÁVEL',
                  style: TextStyle(
                    color: AppTheme.professionalAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Ajustes protegidos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Personalize a comunicação e mantenha o controle dos dados locais.',
                  style: TextStyle(
                    color: Color(0xFFD8E7F0),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F14213D),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.primary, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Material(color: Colors.transparent, child: child),
        ],
      ),
    );
  }
}
