import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'package:fala_comigo/core/services/auth_token_service.dart';
import 'package:fala_comigo/core/services/secure_box_service.dart';
import 'package:fala_comigo/features/transition_alerts/data/providers/transition_alerts_provider.dart';
import 'package:fala_comigo/features/transition_alerts/domain/models/transition_alert.dart';
import 'package:fala_comigo/features/transition_alerts/domain/services/transition_alert_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureValues = <String, String>{};
  late Directory root;
  late Box<dynamic> alertsBox;
  late Box<dynamic> queueBox;
  var authenticationRequests = 0;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('transition_alert_sync_');
    Hive.init('${root.path}/hive');
    SecureBoxService.configureHiveDirectory('${root.path}/hive');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = call.arguments is Map
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{};
      final key = args['key'] as String;
      switch (call.method) {
        case 'write':
          secureValues[key] = args['value'] as String;
          return null;
        case 'read':
          return secureValues[key];
        case 'delete':
          secureValues.remove(key);
          return null;
        case 'containsKey':
          return secureValues.containsKey(key);
        default:
          return null;
      }
    });
    alertsBox = await SecureBoxService.openSecureBox<dynamic>(
      transitionAlertsBoxName,
    );
    queueBox = await SecureBoxService.openSecureBox<dynamic>(
      transitionAlertSyncBoxName,
    );
  });

  setUp(() async {
    await alertsBox.clear();
    await queueBox.clear();
    authenticationRequests = 0;
    AuthTokenService.onAuthenticationRequired = () {
      authenticationRequests += 1;
    };
    TransitionAlertSyncService.connectivityOverride = () async => true;
    TransitionAlertSyncService.requestOverride = null;
  });

  tearDown(() {
    AuthTokenService.onAuthenticationRequired = null;
    TransitionAlertSyncService.connectivityOverride = null;
    TransitionAlertSyncService.requestOverride = null;
  });

  tearDownAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    await Hive.close();
    await root.delete(recursive: true);
  });

  TransitionAlert alert() => TransitionAlert(
        id: 'alert-sync-test',
        title: 'Transição',
        description: 'Descrição local',
        audioType: 'gravado',
        recordedAudioPath: '/private/local-audio.m4a',
        audioUrl: 'file:///private/local-audio.m4a',
        ttsText: 'Vamos mudar de atividade',
        scheduledWeekdays: [1, 2, 3],
        notificationId: 27,
      );

  test('mantém a operação enfileirada quando está offline', () async {
    TransitionAlertSyncService.connectivityOverride = () async => false;

    final outcome = await TransitionAlertSyncService.enqueueUpsert(
      alert(),
      subjectId: 'subject-synthetic',
    );

    expect(outcome, TransitionAlertSyncOutcome.offline);
    expect(queueBox.length, 1);
    expect(queueBox.values.single, isA<Map>());
  });

  test('substitui operações antigas do mesmo alerta na fila offline', () async {
    TransitionAlertSyncService.connectivityOverride = () async => false;
    final local = alert();

    await TransitionAlertSyncService.enqueueUpsert(
      local,
      subjectId: 'subject-synthetic',
    );
    await TransitionAlertSyncService.enqueueDelete(
      local.id,
      subjectId: 'subject-synthetic',
    );

    expect(queueBox.length, 1);
    expect((queueBox.values.single as Map)['operation'], 'delete');

    await TransitionAlertSyncService.enqueueUpsert(
      local,
      subjectId: 'subject-synthetic',
    );

    expect(queueBox.length, 1);
    expect((queueBox.values.single as Map)['operation'], 'upsert');
  });

  test('preserva a fila e solicita autenticação quando recebe 401', () async {
    await AuthTokenService.saveToken('synthetic-access-token');
    TransitionAlertSyncService.requestOverride =
        (method, uri, headers, body) async => http.Response('{}', 401);

    final outcome = await TransitionAlertSyncService.enqueueUpsert(
      alert(),
      subjectId: 'subject-synthetic',
    );

    expect(outcome, TransitionAlertSyncOutcome.unauthorized);
    expect(queueBox.length, 1);
    expect(authenticationRequests, 1);
  });

  test('marca conflito sem descartar silenciosamente o alerta local', () async {
    await AuthTokenService.saveToken('synthetic-access-token');
    final local = alert();
    await alertsBox.put(local.id, local.toMap());
    TransitionAlertSyncService.requestOverride =
        (method, uri, headers, body) async => http.Response('{}', 409);

    final outcome = await TransitionAlertSyncService.enqueueUpsert(
      local,
      subjectId: 'subject-synthetic',
    );

    final stored = TransitionAlert.fromMap(
      Map<String, dynamic>.from(alertsBox.get(local.id) as Map),
    );
    expect(outcome, TransitionAlertSyncOutcome.conflict);
    expect(queueBox, isEmpty);
    expect(stored.syncState, 'conflict');
    expect(stored.syncError, 'VERSION_CONFLICT');
  });

  test('remove mídia local do payload antes do POST remoto', () async {
    await AuthTokenService.saveToken('synthetic-access-token');
    final local = alert()..syncState = 'pending';
    await alertsBox.put(local.id, local.toMap());
    final requests = <Map<String, dynamic>>[];
    TransitionAlertSyncService.requestOverride =
        (method, uri, headers, body) async {
      requests.add({
        'method': method,
        'uri': uri,
        'headers': headers,
        'body': body,
      });
      return method == 'POST'
          ? http.Response('{"alert":{"id":"alert-sync-test"}}', 201)
          : http.Response('{"alerts":[]}', 200);
    };

    final outcome = await TransitionAlertSyncService.enqueueUpsert(
      alert(),
      subjectId: 'subject-synthetic',
    );

    final post =
        jsonDecode(requests.first['body'] as String) as Map<String, dynamic>;
    final remoteAlert = post['alert'] as Map<String, dynamic>;
    final stored = TransitionAlert.fromMap(
      Map<String, dynamic>.from(alertsBox.get(local.id) as Map),
    );
    expect(outcome, TransitionAlertSyncOutcome.synced);
    expect(queueBox, isEmpty);
    expect(stored.syncState, 'synced');
    expect(stored.syncError, isNull);
    expect(remoteAlert.containsKey('recordedAudioPath'), isFalse);
    expect(remoteAlert.containsKey('audioUrl'), isFalse);
    expect(remoteAlert.containsKey('syncState'), isFalse);
    expect(requests.map((item) => item['method']), ['POST', 'GET']);
  });

  test('sincroniza somente o sujeito solicitado e preserva os demais',
      () async {
    TransitionAlertSyncService.connectivityOverride = () async => false;
    await TransitionAlertSyncService.enqueueUpsert(
      alert(),
      subjectId: 'subject-a',
    );
    await TransitionAlertSyncService.enqueueUpsert(
      alert(),
      subjectId: 'subject-b',
    );

    await AuthTokenService.saveToken('synthetic-access-token');
    final requests = <Map<String, dynamic>>[];
    TransitionAlertSyncService.connectivityOverride = () async => true;
    TransitionAlertSyncService.requestOverride =
        (method, uri, headers, body) async {
      requests.add({'method': method, 'uri': uri});
      return method == 'POST'
          ? http.Response('{}', 201)
          : http.Response('{"alerts":[]}', 200);
    };

    final outcome = await TransitionAlertSyncService.syncPending(
      subjectId: 'subject-a',
    );

    expect(outcome, TransitionAlertSyncOutcome.synced);
    expect(requests, hasLength(2));
    expect(
      requests.every(
        (request) => (request['uri'] as Uri).path.contains('/subject-a/'),
      ),
      isTrue,
    );
    expect(queueBox.length, 1);
    expect((queueBox.values.single as Map)['subjectId'], 'subject-b');
  });
}
