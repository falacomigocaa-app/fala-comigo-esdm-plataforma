import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/coleta_escola_controller.dart';
import '../../domain/models/meta_esdm_model.dart';

class ColetaEscolaScreen extends ConsumerWidget {
  const ColetaEscolaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coletaEscolaControllerProvider);
    final controller = ref.read(coletaEscolaControllerProvider.notifier);

    ref.listen<ColetaEscolaState>(
      coletaEscolaControllerProvider,
      (previous, next) {
        if (next.ultimaColeta != previous?.ultimaColeta &&
            next.ultimaColeta != null) {
          final message = switch (next.sincronizacaoStatus) {
            'synced' => 'Registro salvo e sincronizado com segurança.',
            'queued' => 'Sem conexão: registro guardado neste aparelho e será enviado quando a rede voltar.',
            _ => 'Registro salvo neste aparelho. O acesso remoto não está ativo.',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
          );
        } else if (next.erro != null && next.erro != previous?.erro) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Não foi possível salvar o registro.'),
            ),
          );
        }
      },
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Coleta rápida da escola'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 720 ? 40.0 : 20.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                32,
              ),
              children: [
                const _IntroCard(),
                const SizedBox(height: 24),
                _GoalSelectionSection(
                  metas: state.metas,
                  selected: state.metaSelecionadaId,
                  loading: state.carregandoMetas,
                  onSelected: controller.selecionarMeta,
                ),
                const SizedBox(height: 24),
                _SelectionSection(
                  title: 'Em qual bloco da rotina?',
                  subtitle: 'Toque em uma opção.',
                  options: blocosRotinaEscolar,
                  selected: state.blocoSelecionado,
                  icon: Icons.schedule_outlined,
                  onSelected: controller.selecionarBloco,
                ),
                const SizedBox(height: 24),
                _SelectionSection(
                  title: 'Qual foi o nível de suporte?',
                  subtitle: 'Escolha o apoio observado nesta oportunidade.',
                  options: niveisSuporte,
                  selected: state.nivelSuporteSelecionado,
                  icon: Icons.support_outlined,
                  onSelected: controller.selecionarNivelSuporte,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: state.podeRegistrar
                        ? () => controller.registrar()
                        : null,
                    icon: state.salvando
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(state.salvando ? 'Salvando…' : 'Registrar'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'O registro fica salvo neste aparelho. Quando houver autorização e conexão, será enviado com segurança; ele não é uma avaliação clínica.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.mutedText, height: 1.35),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GoalSelectionSection extends StatelessWidget {
  final List<MetaEsdmModel> metas;
  final String? selected;
  final bool loading;
  final ValueChanged<String?> onSelected;

  const _GoalSelectionSection({
    required this.metas,
    required this.selected,
    required this.loading,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flag_outlined, color: AppTheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Qual meta está sendo observada?',
                style: TextStyle(
                  color: AppTheme.textDark,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Metas sincronizadas ficam disponíveis mesmo sem conexão.',
          style: TextStyle(color: AppTheme.mutedText),
        ),
        const SizedBox(height: 12),
        if (metas.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Text(
              loading
                  ? 'Consultando metas clínicas…'
                  : 'Nenhuma meta sincronizada para este indivíduo.',
              style: const TextStyle(color: AppTheme.mutedText),
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Meta clínica',
              border: OutlineInputBorder(),
            ),
            items: metas
                .map(
                  (meta) => DropdownMenuItem(
                    value: meta.id,
                    child: Text(
                      '${meta.codigoTecnicoDenver} · ${meta.missaoPais ?? meta.status}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onSelected,
          ),
      ],
    );
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
          Icon(Icons.school_outlined, color: AppTheme.professionalAccent, size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Registre em poucos toques como foi uma oportunidade na rotina escolar.',
              style: TextStyle(color: Colors.white, height: 1.35, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> options;
  final String? selected;
  final IconData icon;
  final ValueChanged<String> onSelected;

  const _SelectionSection({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.icon,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textDark,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppTheme.mutedText)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 640 ? 4 : 2;
            final width =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: options
                  .map(
                    (option) => SizedBox(
                      width: width,
                      child: _ChoiceTile(
                        label: option,
                        selected: option == selected,
                        onTap: () => onSelected(option),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.surface;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? Colors.white : AppTheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.textDark,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
