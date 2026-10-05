import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/painel_consentimento_controller.dart';

class PainelConsentimentoScreen extends ConsumerWidget {
  const PainelConsentimentoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(painelConsentimentoControllerProvider);
    final controller = ref.read(painelConsentimentoControllerProvider.notifier);

    ref.listen<PainelConsentimentoState>(
      painelConsentimentoControllerProvider,
      (previous, next) {
        if (next.erro != null && next.erro != previous?.erro) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Não foi possível salvar esta permissão.'),
            ),
          );
        }
      },
    );

    if (state.carregando) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final expirationText = _formatDate(state.dataExpiracao);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gerenciar acessos'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            const _HeaderCard(),
            const SizedBox(height: 16),
            _AccessCard(
              icon: Icons.school_outlined,
              title: 'Permitir Acesso da Escola',
              description:
                  'Permite leitura de rotinas visuais e escrita da coleta rápida.',
              value: state.permitindoEscola && !state.acessoExpirado,
              onChanged: state.acessoExpirado
                  ? null
                  : controller.definirAcessoEscola,
            ),
            const SizedBox(height: 12),
            _AccessCard(
              icon: Icons.medical_services_outlined,
              title: 'Permitir Acesso de Especialistas/Clínicas',
              description:
                  'Permite leitura de relatórios ABC e escrita de metas clínicas.',
              value: state.permitindoEspecialistas && !state.acessoExpirado,
              onChanged: state.acessoExpirado
                  ? null
                  : controller.definirAcessoEspecialistas,
            ),
            const SizedBox(height: 20),
            _ExpirationCard(
              date: state.dataExpiracao,
              label: expirationText,
              disabled: state.salvando,
              onPick: () => _pickExpiration(context, ref),
            ),
            if (state.acessoExpirado) ...[
              const SizedBox(height: 12),
              const _ExpiredNotice(),
            ],
            const SizedBox(height: 20),
            if (state.salvando)
              const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
            const Text(
              'As permissões ficam salvas localmente e expiram automaticamente na data definida. A autorização server-side será necessária para qualquer portal conectado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedText, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExpiration(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(painelConsentimentoControllerProvider.notifier);
    final current = ref.read(painelConsentimentoControllerProvider).dataExpiracao;
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current.isBefore(today) ? today : current,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 5, 12, 31),
      helpText: 'Data de Expiração do Acesso',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (selected != null) {
      await controller.definirDataExpiracao(selected);
    }
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

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
          Icon(Icons.shield_outlined, color: AppTheme.professionalAccent, size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Você decide quem pode participar do cuidado conectado. Desligar um acesso não apaga os seus dados locais.',
              style: TextStyle(color: Colors.white, height: 1.35, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _AccessCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
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
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: AppTheme.primary, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(description, style: const TextStyle(height: 1.3)),
        ),
      ),
    );
  }
}

class _ExpirationCard extends StatelessWidget {
  final DateTime date;
  final String label;
  final bool disabled;
  final VoidCallback onPick;

  const _ExpirationCard({
    required this.date,
    required this.label,
    required this.disabled,
    required this.onPick,
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: const Icon(Icons.event_outlined, color: AppTheme.primary, size: 30),
        title: const Text(
          'Data de Expiração do Acesso',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('Acesso válido até $label.'),
        trailing: IconButton(
          tooltip: 'Escolher data',
          onPressed: disabled ? null : onPick,
          icon: const Icon(Icons.edit_calendar_outlined),
        ),
      ),
    );
  }
}

class _ExpiredNotice extends StatelessWidget {
  const _ExpiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Text(
        'O prazo terminou. Os acessos estão desativados até que você escolha uma nova data.',
        style: TextStyle(height: 1.3),
      ),
    );
  }
}
