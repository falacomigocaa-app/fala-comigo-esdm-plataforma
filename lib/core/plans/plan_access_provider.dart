import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'billing_service.dart';
import 'plan_access_controller.dart';
import 'plan_license_store.dart';
import 'plan_models.dart';

/// Estado comercial local. O aplicativo inicia no Essencial e não depende de
/// conta ou internet para funcionar.
class PlanAccessNotifier extends StateNotifier<PlanAccessController> {
  PlanAccessNotifier() : super(essentialPlanAccess);

  Future<void> hydrate() async {
    try {
      final license = await PlanLicenseStore.load();
      if (license != null) state = PlanAccessController.fromLicense(license);
    } catch (_) {
      // Falha de leitura não pode bloquear a comunicação local.
      state = essentialPlanAccess;
    }
  }

  Future<void> activateLicense(PlanLicense license) async {
    await PlanLicenseStore.save(license);
    state = PlanAccessController.fromLicense(license);
  }

  Future<void> hydrateRemote() async {
    try {
      final license = await BillingService.fetchSubscription();
      if (license != null) await activateLicense(license);
    } catch (_) {
      // A cobrança indisponível não bloqueia o plano Essencial offline.
    }
  }

  Future<void> returnToEssential() async {
    await PlanLicenseStore.clear();
    state = essentialPlanAccess;
  }
}

final planAccessProvider =
    StateNotifierProvider<PlanAccessNotifier, PlanAccessController>(
  (ref) => PlanAccessNotifier(),
);

/// Atalho para telas que precisam esconder ou explicar um recurso remoto.
final hasRemoteBackupProvider = Provider<bool>((ref) {
  return ref.watch(planAccessProvider).canUse(PlanFeature.remoteBackup);
});

final hasCareNetworkProvider = Provider<bool>((ref) {
  return ref.watch(planAccessProvider).canUse(PlanFeature.careNetwork);
});
