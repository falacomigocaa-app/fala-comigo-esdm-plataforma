import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/core/services/parental_session_service.dart';
import 'package:fala_comigo/features/parental_area/data/care_coordination.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final secureValues = <String, String>{};
  late Directory root;

  setUp(() {
    ParentalSessionService.authenticate();
  });

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('fala_care_plan_store_test_');
    Hive.init('${root.path}/hive');

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = call.arguments is Map
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};
      switch (call.method) {
        case 'write':
          secureValues[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureValues[args['key'] as String];
        case 'delete':
          secureValues.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          secureValues.clear();
          return null;
        case 'readAll':
          return secureValues;
        case 'containsKey':
          return secureValues.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
          return '${root.path}/documents';
        case 'getTemporaryDirectory':
          return '${root.path}/temporary';
        default:
          throw MissingPluginException('Método não simulado: ${call.method}');
      }
    });
  });

  tearDownAll(() async {
    await Hive.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    await root.delete(recursive: true);
  });

  test('persiste, recupera e atualiza plano local pelo mesmo identificador',
      () async {
    final plan = CommunicationPlan(
      id: 'saved-plan-1',
      title: 'Plano de pedido de pausa',
      context: 'Casa',
      functionalGoal: 'Pedir uma pausa antes de sair da atividade',
      strategy: 'Modelar o cartão sem exigir repetição',
      familyAction: 'Praticar durante uma rotina natural',
      schoolAction: 'Deixar o cartão disponível na chegada',
      reviewAt: DateTime(2026, 10, 20),
      status: CarePlanStatus.active,
      createdAt: DateTime(2026, 9, 20),
      updatedAt: DateTime(2026, 9, 21),
    );

    await CareCoordinationStore.savePlan(plan);
    final loadedPlans = await CareCoordinationStore.loadPlans();
    expect(loadedPlans.single.title, plan.title);
    expect(loadedPlans.single.status, CarePlanStatus.active);

    final updatedPlan = CommunicationPlan(
      id: plan.id,
      title: 'Plano atualizado',
      context: plan.context,
      functionalGoal: plan.functionalGoal,
      strategy: plan.strategy,
      familyAction: plan.familyAction,
      schoolAction: plan.schoolAction,
      reviewAt: plan.reviewAt,
      status: CarePlanStatus.needsReview,
      createdAt: plan.createdAt,
      updatedAt: DateTime(2026, 9, 22),
    );
    await CareCoordinationStore.savePlan(updatedPlan);

    final reloadedPlans = await CareCoordinationStore.loadPlans();
    expect(reloadedPlans, hasLength(1));
    expect(reloadedPlans.single.id, plan.id);
    expect(reloadedPlans.single.title, 'Plano atualizado');
    expect(reloadedPlans.single.status, CarePlanStatus.needsReview);
  });

  test('store nega leitura direta após a sessão ser bloqueada', () async {
    ParentalSessionService.lock();

    expect(
      () => CareCoordinationStore.loadPlans(),
      throwsA(isA<ParentalSessionRequiredException>()),
    );
  });
}
