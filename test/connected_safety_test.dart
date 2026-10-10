// Fixtures adaptadas de test/data_wipe_service_test.dart. Somente dados sintéticos.
import 'dart:io';
import 'dart:async';
import 'package:fala_comigo/features/esdm_aba/data/coleta_escola_store.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/core/services/data_wipe_service.dart';
import 'package:fala_comigo/core/services/parental_session_service.dart';
import 'package:fala_comigo/core/services/secure_box_service.dart';
import 'package:fala_comigo/features/aac_grid/domain/models/pictogram_card.dart';

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fala_comigo/features/auth/presentation/controllers/login_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fala_comigo/core/services/auth_token_service.dart';
import 'package:fala_comigo/core/services/crypto_service.dart';
import 'package:fala_comigo/features/esdm_aba/data/concessao_acesso_store.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/concessao_acesso_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/coleta_escola_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/services/sync_queue_service.dart';

class _TestNotificationsPlatform extends FlutterLocalNotificationsPlatform {
  _TestNotificationsPlatform(this.onCancelAll);

  final Future<void> Function() onCancelAll;

  @override
  Future<void> cancelAll() => onCancelAll();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final secureValues = <String, String>{};
  final notificationMethods = <String>[];
  var failNotificationCancellation = false;
  late Directory root;

  var caseNumber = 0;
  setUp(() async {
    await Hive.close();
    secureValues.clear();
    final caseDirectory = Directory('${root.path}/case-${caseNumber++}');
    await caseDirectory.create(recursive: true);
    Hive.init(caseDirectory.path);
    SecureBoxService.configureHiveDirectory(caseDirectory.path);
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
    await SyncQueueService.dispose();
    await Hive.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    await root.delete(recursive: true);
  });

  test('A06: apagar dados deve remover tokens e chaves E2EE', () async {
    await AuthTokenService.saveSessionTokens(
      accessToken: 'audit-access',
      refreshToken: 'audit-refresh',
    );
    await CryptoService.encryptPayload(
      organizationId: 'audit-org',
      plaintext: '{}',
    );
    await DataWipeService.deleteAllLocalData();
    final remaining = secureValues.keys
        .where(
          (key) =>
              key.startsWith('fala_comigo_portal_') ||
              key.startsWith('fala_comigo_org_e2ee_key_'),
        )
        .toList();
    expect(
      remaining,
      isEmpty,
      reason: 'Tokens/chaves antigos continuam no cofre após apagar dados',
    );
  });

  test('A06b: apagar dados deve remover concessões ESDM e suas chaves',
      () async {
    await ConcessaoAcessoStore.save(
      ConcessaoAcessoModel(
        id: 'audit-wipe-grant',
        perfilAlvo: escolaPerfilAlvo,
        permiteEscritaDados: true,
        dataExpiracao: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    Object? wipeError;
    try {
      await DataWipeService.deleteAllLocalData();
    } catch (error) {
      wipeError = error;
    }
    expect(
      await ConcessaoAcessoStore.loadAll(),
      isEmpty,
      reason:
          'Consentimento anterior permaneceu legível; erro de wipe: $wipeError',
    );
  });

  test(
    'A07: consentimento somente de leitura deve impedir POST de coleta',
    () async {
      for (final grant in await ConcessaoAcessoStore.loadAll()) {
        await ConcessaoAcessoStore.delete(grant.id);
      }
      await ConcessaoAcessoStore.save(
        ConcessaoAcessoModel(
          id: 'audit-read-only',
          perfilAlvo: escolaPerfilAlvo,
          permiteLeituraMetas: true,
          permiteEscritaDados: false,
          dataExpiracao: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      final claims = base64UrlEncode(
        utf8.encode('{"organizationId":"audit-org"}'),
      ).replaceAll('=', '');
      await AuthTokenService.saveToken('synthetic.$claims.signature');
      var posts = 0;
      SyncQueueService.connectivityOverride = () async => true;
      SyncQueueService.postOverride = (uri, headers, body) async {
        posts += 1;
        return http.Response('{}', 201);
      };
      try {
        await SyncQueueService.saveOrSyncCollection(
          subjectId: 'audit-subject',
          coleta: ColetaEscolaModel(
            id: 'audit-collection',
            dataRegistro: DateTime.now(),
            blocoRotinaEscolar: 'Lanche',
            nivelSuporte: 'Independente',
          ),
        );
        expect(
          posts,
          0,
          reason: 'Coleta transmitida sem consentimento local de escrita',
        );
      } finally {
        SyncQueueService.connectivityOverride = null;
        SyncQueueService.postOverride = null;
      }
    },
  );
  test(
    'A08: coleta mobile deve usar a chave da organização recebida no login',
    () async {
      // Transporte sintético injetado; não conecta ao portal real.
      final provisionedKey = List<int>.filled(32, 17);
      final claims = base64UrlEncode(
        utf8.encode('{"organizationId":"audit-provisioned-org"}'),
      ).replaceAll('=', '');
      final controller = LoginController(
          client: MockClient((request) async => http.Response(
              jsonEncode({
                'accessToken': 'synthetic.$claims.signature',
                'refreshToken': 'audit-refresh',
                'organizationId': 'audit-provisioned-org',
                'organizationKey': base64Encode(provisionedKey),
              }),
              200)));
      SyncQueueService.connectivityOverride = () async => false;
      try {
        expect(
          await controller.login(
            email: 'audit@example.test',
            password: 'synthetic',
          ),
          isTrue,
        );
        final envelope = jsonDecode(
          await CryptoService.encryptPayload(
            organizationId: 'audit-provisioned-org',
            plaintext: '{"synthetic":true}',
          ),
        ) as Map<String, dynamic>;
        final encrypted = base64Decode(envelope['encryptedData'] as String);
        final clear = await AesGcm.with256bits().decrypt(
          SecretBox(
            encrypted.sublist(0, encrypted.length - 16),
            nonce: base64Decode(envelope['iv'] as String),
            mac: Mac(encrypted.sublist(encrypted.length - 16)),
          ),
          secretKey: SecretKey(provisionedKey),
        );
        expect(utf8.decode(clear), '{"synthetic":true}');
      } finally {
        controller.dispose();
        SyncQueueService.connectivityOverride = null;
      }
    },
  );
  test(
      'nova chave concorrente e importação preservam envelopes locais e retries',
      () async {
    final envelopes = await Future.wait([
      CryptoService.encryptPayload(
          organizationId: 'key-race', plaintext: '{"value":1}'),
      CryptoService.encryptPayload(
          organizationId: 'key-race', plaintext: '{"value":2}'),
    ]);
    expect(await CryptoService.decryptPayload(envelopes[0]), '{"value":1}');
    expect(await CryptoService.decryptPayload(envelopes[1]), '{"value":2}');
    await CryptoService.importOrganizationKey(
        'key-race', base64Encode(List<int>.filled(32, 71)));
    expect(await CryptoService.decryptPayload(envelopes[0]), '{"value":1}');
    final prepared = await CryptoService.prepareForUpload(envelopes[0]);
    expect(prepared, isNot(envelopes[0]));
    expect(await CryptoService.prepareForUpload(prepared), prepared);
  });
  test('refresh concorrente é único e não restaura sessão apagada', () async {
    await AuthTokenService.saveSessionTokens(
        accessToken: 'old', refreshToken: 'old-refresh');
    final arrived = Completer<void>();
    final response = Completer<http.Response>();
    var calls = 0;
    AuthTokenService.refreshOverride = (_, __, ___) {
      calls++;
      arrived.complete();
      return response.future;
    };
    try {
      final first = AuthTokenService.refreshSession();
      final second = AuthTokenService.refreshSession();
      await arrived.future;
      await AuthTokenService.clearToken();
      response.complete(http.Response(
          '{"accessToken":"new","refreshToken":"new-refresh"}', 200));
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(calls, 1);
      expect(await AuthTokenService.readToken(), isNull);
      expect(await AuthTokenService.readRefreshToken(), isNull);
    } finally {
      AuthTokenService.refreshOverride = null;
    }
  });

  test('login iniciado antes de apagar sessão não recria tokens ou chave',
      () async {
    final response = Completer<http.Response>();
    final controller =
        LoginController(client: MockClient((_) => response.future));
    try {
      final pending =
          controller.login(email: 'local@example.test', password: 'fixture');
      await AuthTokenService.clearToken();
      response.complete(http.Response(
          jsonEncode({
            'accessToken': 'new',
            'refreshToken': 'new-refresh',
            'organizationId': 'cancelled-org',
            'organizationKey': base64Encode(List<int>.filled(32, 4)),
          }),
          200));
      expect(await pending, isFalse);
      expect(await AuthTokenService.readToken(), isNull);
      expect(secureValues.keys.any((key) => key.contains('cancelled-org')),
          isFalse);
    } finally {
      controller.dispose();
    }
  });

  test('coletas locais não misturam pacientes nem registros sem vínculo',
      () async {
    for (final subject in <String?>['patient-a', 'patient-b', null]) {
      await ColetaEscolaStore.save(ColetaEscolaModel(
          id: 'collection-$subject',
          subjectId: subject,
          dataRegistro: DateTime.now(),
          blocoRotinaEscolar: 'Lanche',
          nivelSuporte: 'Independente'));
    }
    expect(
        (await ColetaEscolaStore.loadAll(subjectId: 'patient-a'))
            .map((item) => item.id),
        ['collection-patient-a']);
    expect(
        (await ColetaEscolaStore.loadAll(subjectId: 'patient-b'))
            .map((item) => item.id),
        ['collection-patient-b']);
    expect((await ColetaEscolaStore.loadAll()).map((item) => item.id),
        ['collection-null']);
  });
}
