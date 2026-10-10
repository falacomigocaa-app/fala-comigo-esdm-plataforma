import 'package:hive_flutter/hive_flutter.dart';

import 'media_storage_service.dart';
import 'auth_token_service.dart';
import 'crypto_service.dart';
import '../../features/esdm_aba/data/esdm_secure_box_service.dart';
import '../../features/esdm_aba/domain/services/sync_queue_service.dart';
import 'parental_pin_service.dart';
import 'parental_session_service.dart';
import 'secure_box_service.dart';
import 'transition_alert_service.dart';
import '../plans/plan_license_store.dart';
import '../../features/aac_grid/data/providers/seed_cards.dart';
import '../../features/aac_grid/domain/models/pictogram_card.dart';

/// Remove os dados criados pelo Fala Comigo neste dispositivo.
class DataWipeResult {
  const DataWipeResult({required this.notificationsCancelled});

  final bool notificationsCancelled;
}

class DataWipeService {
  DataWipeService._();

  static const _boxNames = [
    'pictogram_cards',
    'app_settings',
    'transition_alerts',
    'parent_reminders',
    'patient_profile',
    'behavior_logs',
    'video_diary',
    'visual_routine',
    'parent_access_grants',
    'shared_tasks',
    'shared_task_sync_queue',
    'sync_queue_box',
    'esdm_goals_box',
    'concessoes_acesso_box',
    'metas_esdm_box',
    'coleta_escola_box',
    'coleta_escola',
    'sincronizacao_queue_box',
    'communication_profile',
    'communication_plans',
    'care_appointments',
    planLicenseBoxName,
  ];

  static Future<DataWipeResult> deleteAllLocalData() async {
    ParentalSessionService.lock();
    await AuthTokenService.clearToken();
    await SyncQueueService.suspendForWipe();
    var notificationsCancelled = true;
    try {
      await TransitionAlertService.instance.cancelAllNotifications();
    } catch (_) {
      // Uma falha do plugin não deve impedir a remoção dos dados locais.
      notificationsCancelled = false;
    }
    // Fecha todas as boxes sem tentar reabri-las como dynamic: algumas telas
    // mantêm boxes tipadas que Hive não permite obter com outro tipo genérico.
    await Hive.close();
    for (final name in _boxNames) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } on HiveError {
        // A caixa pode ainda não existir em uma instalação nova.
      }
    }
    // Sidecars são cópias brutas e podem conter dados legados sem cifra.
    // O wipe é explícito; remova-os antes de apagar a chave e recriar as boxes.
    await SecureBoxService.deletePendingHiveSnapshotsForWipe(_boxNames);
    await MediaStorageService.clearAllMedia();
    await MediaStorageService.deleteEncryptionKey();
    await SecureBoxService.deleteEncryptionKey();
    await ParentalPinService.clearCredentials();
    await CryptoService.clearAllOrganizationKeys();
    await EsdmSecureBoxService.deleteEncryptionKeys();

    // Recria caixas vazias com uma nova chave para que o app continue
    // utilizável sem exigir uma reinicialização do processo Flutter.
    final cardsBox = await SecureBoxService.openSecureBox<PictogramCard>(
      'pictogram_cards',
    );
    for (final card in SeedCards.defaultCards()) {
      await cardsBox.put(card.id, card);
    }
    await SecureBoxService.openSecureBox('app_settings');
    await SecureBoxService.openSecureBox('transition_alerts');
    await SecureBoxService.openSecureBox('parent_reminders');
    await SecureBoxService.openSecureBox('patient_profile');
    await SecureBoxService.openSecureBox('behavior_logs');
    await SecureBoxService.openSecureBox('video_diary');
    await SecureBoxService.openSecureBox('visual_routine');
    await SecureBoxService.openSecureBox('parent_access_grants');
    await SecureBoxService.openSecureBox('shared_tasks');
    await SecureBoxService.openSecureBox('shared_task_sync_queue');
    await SecureBoxService.openSecureBox('sync_queue_box');
    await SecureBoxService.openSecureBox('esdm_goals_box');
    await SecureBoxService.openSecureBox('communication_profile');
    await SecureBoxService.openSecureBox('communication_plans');
    await SecureBoxService.openSecureBox('care_appointments');
    await SecureBoxService.openSecureBox(planLicenseBoxName);

    // Tenta novamente após a exclusão. Se o plugin continuar indisponível,
    // a UI avisa que o sistema operacional pode manter lembretes pendentes.
    if (!notificationsCancelled) {
      try {
        await TransitionAlertService.instance.cancelAllNotifications();
        notificationsCancelled = true;
      } catch (_) {
        // A remoção local já foi concluída; o resultado informa a limitação.
      }
    }
    SyncQueueService.resumeAfterWipe();
    return DataWipeResult(notificationsCancelled: notificationsCancelled);
  }
}
