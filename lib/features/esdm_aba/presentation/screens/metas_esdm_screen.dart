import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/meta_esdm_model.dart';
import '../../domain/services/esdm_translator.dart';
import '../controllers/meta_esdm_controller.dart';

class MetasEsdmScreen extends ConsumerWidget {
  const MetasEsdmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(metaEsdmControllerProvider);
    final controller = ref.read(metaEsdmControllerProvider.notifier);

    ref.listen<MetaEsdmState>(
      metaEsdmControllerProvider,
      (previous, next) {
        if (next.erro != null && next.erro != previous?.erro) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Não foi possível salvar a meta.'),
            ),
          );
        }
      },
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Plano de Metas Desenvolvimento'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (state.exportando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Exportar relatório unificado em PDF',
              onPressed: state.salvando
                  ? null
                  : () => _exportPdf(context, controller),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: state.carregando
          ? const Center(child: CircularProgressIndicator())
          : state.metas.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
                  itemCount: state.metas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _MetaCard(
                    meta: state.metas[index],
                    onStatusChanged: (status) => controller.atualizarMeta(
                      _withStatus(state.metas[index], status),
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.salvando
            ? null
            : () => _showAddMetaDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova meta'),
      ),
    );
  }

  static MetaEsdmModel _withStatus(MetaEsdmModel meta, String status) {
    return MetaEsdmModel(
      id: meta.id,
      codigoTecnicoDenver: meta.codigoTecnicoDenver,
      status: status,
      passoAtualAba: meta.passoAtualAba,
    );
  }

  Future<void> _exportPdf(
    BuildContext context,
    MetaEsdmController controller,
  ) async {
    final exported = await controller.exportarRelatorioUnificado();
    if (!context.mounted) return;
    if (exported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Relatório gerado. Escolha onde compartilhar.'),
        ),
      );
    }
  }

  Future<void> _showAddMetaDialog(BuildContext context, WidgetRef ref) async {
    String selectedCode = EsdmTranslator.traducoes.keys.first;
    final controller = ref.read(metaEsdmControllerProvider.notifier);
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Cadastrar nova meta'),
              content: DropdownButtonFormField<String>(
                value: selectedCode,
                decoration: const InputDecoration(
                  labelText: 'Código técnico Denver',
                  border: OutlineInputBorder(),
                ),
                items: EsdmTranslator.traducoes.keys
                    .map(
                      (code) => DropdownMenuItem(
                        value: code,
                        child: Text(code),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedCode = value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final success = await controller.adicionarMeta(selectedCode);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(success);
                    }
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Meta adicionada ao plano.'),
        ),
      );
    }
  }
}

class _MetaCard extends StatelessWidget {
  final MetaEsdmModel meta;
  final ValueChanged<String> onStatusChanged;

  const _MetaCard({required this.meta, required this.onStatusChanged});

  @override
  Widget build(BuildContext context) {
    final translation = EsdmTranslator.translate(meta.codigoTecnicoDenver);
    if (translation == null) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.cardBorder),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE7EDFF),
          child: Icon(Icons.flag_outlined, color: AppTheme.primary),
        ),
        title: Text(
          translation.missaoPais,
          style: const TextStyle(
            color: AppTheme.textDark,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Missão para a Família',
            style: TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        children: [
          _DetailBlock(
            title: 'Dica Prática',
            text: translation.dicaPratica,
            icon: Icons.lightbulb_outline,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Detalhes Técnicos',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                meta.codigoTecnicoDenver,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: meta.status,
            decoration: const InputDecoration(
              labelText: 'Status da meta',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Em Progresso',
                child: Text('Em Progresso'),
              ),
              DropdownMenuItem(
                value: 'Adquirido',
                child: Text('Adquirido'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onStatusChanged(value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Passo atual da análise ABA: ${meta.passoAtualAba}',
            style: const TextStyle(color: AppTheme.mutedText),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String text;
  final IconData icon;

  const _DetailBlock({
    required this.title,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 56, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text(
              'Nenhuma meta cadastrada',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Adicione uma meta técnica para criar uma missão simples para a família.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedText, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
