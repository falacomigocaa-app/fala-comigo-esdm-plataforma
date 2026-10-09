import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/plans/plan_access_controller.dart';
import '../../../../core/plans/billing_service.dart';
import '../../../../core/plans/plan_access_provider.dart';
import '../../../../core/plans/plan_catalog.dart';
import '../../../../core/plans/plan_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/parental_ui.dart';

/// Exibe o estado comercial sem exigir conta, cobrança ou conexão.
class PlanStatusScreen extends ConsumerStatefulWidget {
  const PlanStatusScreen({super.key});

  @override
  ConsumerState<PlanStatusScreen> createState() => _PlanStatusScreenState();
}

class _PlanStatusScreenState extends ConsumerState<PlanStatusScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(planAccessProvider.notifier).hydrate();
    unawaited(ref.read(planAccessProvider.notifier).hydrateRemote());
  }

  Future<void> _startSandboxCheckout(Plan plan) async {
    try {
      final result = await BillingService.createSandboxCheckout(plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Checkout de teste criado (${result.checkoutId}). Nenhuma cobrança foi realizada.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout indisponível: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(planAccessProvider);
    final license = access.license;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Plano e recursos'),
        backgroundColor: AppTheme.professionalBackground,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          const ParentalSectionHeading(
            eyebrow: 'ACESSO E RECURSOS',
            title: 'Plano e recursos',
            description:
                'Consulte o que está disponível neste aparelho sem bloquear a comunicação básica.',
          ),
          const SizedBox(height: 18),
          _CurrentPlanCard(access: access),
          const SizedBox(height: 18),
          const _PlanSectionTitle(
            icon: Icons.verified_outlined,
            title: 'Recursos da comunicação',
          ),
          const SizedBox(height: 8),
          _FeatureTile(
            icon: Icons.wifi_off_outlined,
            title: 'Comunicação offline',
            description:
                'Cartões, frases e voz continuam disponíveis sem internet.',
            enabled: access.canUse(PlanFeature.offlineCommunication),
          ),
          _FeatureTile(
            icon: Icons.lock_outline,
            title: 'Controle familiar',
            description:
                'PIN, configurações parentais e dados locais protegidos.',
            enabled: access.canUse(PlanFeature.parentalControls),
          ),
          _FeatureTile(
            icon: Icons.accessibility_new_outlined,
            title: 'Acessibilidade',
            description:
                'Modos de toque e semântica acessível fazem parte do núcleo.',
            enabled: access.canUse(PlanFeature.accessibility),
          ),
          const SizedBox(height: 20),
          const _PlanSectionTitle(
            icon: Icons.layers_outlined,
            title: 'Planos disponíveis',
          ),
          const SizedBox(height: 8),
          ...PlanCatalog.publicPlans.map(
            (plan) => _PlanCard(
              plan: plan,
              selected: plan.id == access.plan.id,
              onCheckout:
                  plan.pricePending ? () => _startSandboxCheckout(plan) : null,
            ),
          ),
          if (license == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Nenhuma assinatura ou licença remota está conectada. O plano Essencial continua funcionando neste aparelho.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final PlanAccessController access;

  const _CurrentPlanCard({required this.access});

  @override
  Widget build(BuildContext context) {
    final license = access.license;
    final status = license == null ? 'Uso local' : _statusLabel(license.status);

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
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PLANO ATUAL',
              style: TextStyle(
                color: AppTheme.professionalAccent,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.05,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              access.plan.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status,
              style: TextStyle(
                color: access.communicationRemainsAvailable
                    ? Colors.lightGreenAccent
                    : Colors.orangeAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A comunicação básica não depende de assinatura e não será bloqueada por falta de conexão.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(LicenseStatus status) => switch (status) {
        LicenseStatus.invited => 'Convite pendente',
        LicenseStatus.active => 'Ativo',
        LicenseStatus.grace => 'Período de transição',
        LicenseStatus.suspended => 'Suspenso — uso local preservado',
        LicenseStatus.expired => 'Expirado — uso local preservado',
        LicenseStatus.revoked => 'Revogado — uso local preservado',
      };
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool enabled;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title: ${enabled ? 'disponível' : 'indisponível'}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            icon,
            color: enabled ? AppTheme.primary : AppTheme.mutedText,
          ),
          title: Text(title),
          subtitle: Text(description),
          trailing: Icon(
            enabled ? Icons.check_circle_outline : Icons.lock_outline,
            color: enabled ? AppTheme.accentGreen : AppTheme.mutedText,
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool selected;
  final VoidCallback? onCheckout;

  const _PlanCard({
    required this.plan,
    required this.selected,
    this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final price = plan.isFree
        ? 'Gratuito'
        : plan.pricePending
            ? 'Preço a definir'
            : 'R\$ ${(plan.monthlyPriceCents! / 100).toStringAsFixed(2)} / mês';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF3FF) : AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.primary : AppTheme.cardBorder,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                plan.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              price,
              style: TextStyle(
                color: selected ? AppTheme.primary : AppTheme.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(plan.description),
            ),
            if (onCheckout != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: onCheckout,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Testar checkout sandbox'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlanSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ],
    );
  }
}
