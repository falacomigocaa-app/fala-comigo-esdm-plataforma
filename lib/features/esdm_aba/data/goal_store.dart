import 'package:hive/hive.dart';

import '../../../core/services/secure_box_service.dart';
import '../domain/models/meta_esdm_model.dart';

const esdmGoalsBoxName = 'esdm_goals_box';

/// Cache local cifrado das metas clínicas baixadas do portal-api.
class GoalStore {
  GoalStore._();

  static Future<Box<MetaEsdmModel>> _box() async {
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(MetaEsdmModelAdapter());
    }
    return SecureBoxService.openSecureBox<MetaEsdmModel>(esdmGoalsBoxName);
  }

  static Future<List<MetaEsdmModel>> loadForSubject(String subjectId) async {
    final box = await _box();
    final goals = box.values.where((goal) => goal.subjectId == subjectId).toList();
    goals.sort((left, right) => left.codigoTecnicoDenver.compareTo(right.codigoTecnicoDenver));
    return goals;
  }

  static Future<void> replaceForSubject(
    String subjectId,
    List<MetaEsdmModel> goals,
  ) async {
    final box = await _box();
    final currentIds = box.values
        .where((goal) => goal.subjectId == subjectId)
        .map((goal) => goal.id)
        .toList();
    await box.deleteAll(currentIds);
    for (final goal in goals) {
      await box.put(goal.id, goal);
    }
  }
}
