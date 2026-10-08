import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/core/services/data_wipe_service.dart';
import 'package:fala_comigo/core/services/parental_session_service.dart';
import 'package:fala_comigo/core/services/secure_box_service.dart';
import 'package:fala_comigo/features/aac_grid/domain/models/pictogram_card.dart';
import 'package:fala_comigo/features/parental_area/data/parent_reminders.dart';

class _TestNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  _TestNotificationsPlatform(this.onCancelAll);

  final Future<void> Function() onCancelAll;

  @override
  Future<void> cancelAll() => onCancelAll();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final secureValues = <String, String>{};
  final notificationMethods = <String>[];
  var failNotificationCancellation = false;
  late Directory root;

  setUp(() {
    notificationMethods.clear();
    failNotificationCancellation = false;
    ParentalSessionService.authenticate();
  });

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('fala_comigo_data_wipe_test_');
    final hiveDirectory = '${root.path}/hive';
    Hive.init(hiveDirectory);
    SecureBoxService.configureHiveDirectory(hiveDirectory);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(PictogramCardAdapter());
    }
    FlutterLocalNotificationsPlatform.instance = _TestNotificationsPlatform(
      () async {
        notificationMethods.add('cancelAll');
        if (failNotificationCancellation) {
          throw StateError('Falha simulada ao cancelar notificações.');
        }
      },
    );

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

  test('apagar dados limpa lembretes e cancela notificações agendadas',
      () async {
    const reminder = ParentReminder(
      id: 'routine-test',
      label: 'Lembrete sintético',
      hour: 8,
      minute: 30,
      weekdays: [1, 2, 3, 4, 5],
      notificationId: 321,
    );
    await ParentReminderStore.save([reminder]);
    expect((await ParentReminderStore.load()).single.id, reminder.id);

    await DataWipeService.deleteAllLocalData();
    ParentalSessionService.authenticate();

    expect(await ParentReminderStore.load(), isEmpty);
    expect(notificationMethods, contains('cancelAll'));
  });

  test('fecha outras boxes Hive tipadas sem tentar obtê-las como dynamic',
      () async {
    await Hive.close();
    await Hive.openBox<PictogramCard>('behavior_logs');

    await DataWipeService.deleteAllLocalData();

    expect(Hive.isBoxOpen('behavior_logs'), isTrue);
    expect(Hive.box<dynamic>('behavior_logs').isEmpty, isTrue);
  });

  test('wipe explícito remove sidecars Hive antes de recriar caixas', () async {
    final hiveDirectory = Directory('${root.path}/hive');
    final backup = File(
      '${hiveDirectory.path}/pictogram_cards.hive.fcm-backup',
    );
    final temporary = File(
      '${hiveDirectory.path}/app_settings.hive.fcm-backup.tmp',
    );
    await backup.writeAsString('fixture sintética de backup');
    await temporary.writeAsString('fixture sintética temporária');

    await DataWipeService.deleteAllLocalData();

    expect(await backup.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
    expect(Hive.isBoxOpen('pictogram_cards'), isTrue);
    expect(Hive.box<PictogramCard>('pictogram_cards').values, isNotEmpty);
  });

  test('falha de notificação não impede o wipe e retorna aviso de pendência',
      () async {
    const reminder = ParentReminder(
      id: 'wipe-fail-test',
      label: 'Lembrete que deve permanecer',
      hour: 9,
      minute: 0,
      weekdays: [1],
      notificationId: 654,
    );
    await ParentReminderStore.save([reminder]);
    failNotificationCancellation = true;

    final result = await DataWipeService.deleteAllLocalData();
    ParentalSessionService.authenticate();

    expect(result.notificationsCancelled, isFalse);
    expect(await ParentReminderStore.load(), isEmpty);
    expect(
        notificationMethods.where((method) => method == 'cancelAll').length, 2);
  });
}
