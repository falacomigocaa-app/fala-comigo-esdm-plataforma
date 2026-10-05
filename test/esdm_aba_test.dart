import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/features/esdm_aba/data/concessao_acesso_store.dart';
import 'package:fala_comigo/features/esdm_aba/data/sincronizacao_queue_store.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/concessao_acesso_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/meta_esdm_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/sincronizacao_queue_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/sync_item.dart';
import 'package:fala_comigo/core/services/auth_token_service.dart';
import 'package:fala_comigo/features/esdm_aba/data/meta_esdm_store.dart';
import 'package:fala_comigo/features/esdm_aba/data/sync_queue_store.dart';
import 'package:fala_comigo/features/esdm_aba/domain/services/esdm_translator.dart';
import 'package:fala_comigo/features/esdm_aba/domain/services/mobile_pdf_service.dart';
import 'package:fala_comigo/features/esdm_aba/domain/services/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Directory root;
  final secureValues = <String, String>{};

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('fala_esdm_aba_test_');
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
  });

  tearDownAll(() async {
    await Hive.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    await root.delete(recursive: true);
  });

  test('traduz CE_N1_I5 em missão e dica não nulas e precisas', () {
    final translation = EsdmTranslator.traduzir('CE_N1_I5');

    expect(translation, isNotNull);
    expect(
      translation!.missaoPais,
      'Estimular o uso da voz para pedir itens no dia a dia.',
    );
    expect(
      translation.dicaPratica,
      'Segure o brinquedo favorito próximo ao seu rosto. Quando ele fizer '
      'qualquer vocalização ou som voluntário, elogie e entregue o item '
      'imediatamente.',
    );
  });

  test('bloqueia concessão expirada no store cifrado', () async {
    await ConcessaoAcessoStore.save(
      ConcessaoAcessoModel(
        id: 'expired-school-grant',
        perfilAlvo: escolaPerfilAlvo,
        permiteLeituraMetas: true,
        permiteEscritaDados: true,
        dataExpiracao: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    final active = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo);

    expect(active, isNull);
  });

  test('carrega payload enfileirado como pendência offline', () async {
    final item = SincronizacaoQueueModel(
      id: 'queue-test-1',
      payloadJson: '{"id":"coleta-test-1"}',
      endpointAlvo: '/coletas',
      acao: 'INSERT',
    );

    await SincronizacaoQueueStore.enqueue(item);
    final pending = await SincronizacaoQueueStore.loadPending();

    expect(pending, hasLength(1));
    expect(pending.single.id, item.id);
    expect(pending.single.payloadJson, item.payloadJson);
    expect(pending.single.endpointAlvo, '/coletas');
    expect(pending.single.acao, 'INSERT');
    expect(pending.single.processado, isFalse);
  });

  test('gera PDF clínico com meta e coleta do subjectId local', () async {
    const subjectId = 'subject-pdf-test';
    await MetaEsdmStore.save(
      MetaEsdmModel(
        id: 'pdf-goal-1',
        codigoTecnicoDenver: 'CE_N1_I5',
        subjectId: subjectId,
      ),
    );
    final item = SyncItem(
      id: 'pdf-collection-1',
      payload:
          '{"subjectId":"$subjectId","blocoRotinaEscolar":"Lanche","nivelSuporte":"Independente"}',
      createdAt: DateTime.utc(2026, 10, 5),
      endpoint: '/school-collections',
    );
    await SyncQueueStore.enqueue(item);

    final bytes = await MobilePdfService.generate(
      subjectId: subjectId,
      patientName: 'Paciente PDF',
      organizationName: 'Clínica Teste',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    await SyncQueueStore.remove(item);
    await MetaEsdmStore.delete('pdf-goal-1');
  });

  test('bloqueia concessão revogada mesmo antes da data de expiração',
      () async {
    await ConcessaoAcessoStore.save(
      ConcessaoAcessoModel(
        id: 'revoked-school-grant',
        perfilAlvo: escolaPerfilAlvo,
        permiteLeituraMetas: true,
        permiteEscritaDados: true,
        dataExpiracao: DateTime.now().add(const Duration(days: 30)),
        revoked: true,
      ),
    );

    expect(await ConcessaoAcessoStore.findActive(escolaPerfilAlvo), isNull);
  });

  test('fila mantém item intacto quando consentimento está revogado', () async {
    const itemId = 'consent-blocked-sync-item';
    await SyncQueueStore.enqueue(
      SyncItem(
        id: itemId,
        payload: '{"subjectId":"local-subject","id":"coleta-consent"}',
        createdAt: DateTime.utc(2026, 10, 5),
        endpoint: '/school-collections',
      ),
    );
    SyncQueueService.connectivityOverride = () async => true;
    try {
      await SyncQueueService.syncPending();
    } finally {
      SyncQueueService.connectivityOverride = null;
    }

    final pending = await SyncQueueStore.pending();
    final item = pending.firstWhere((candidate) => candidate.id == itemId);
    expect(item.attempts, 0);
    expect(SyncQueueService.consentBlocked, isTrue);
    await SyncQueueStore.remove(item);
  });

  test('persiste SyncItem em box AES-256 com tentativas e endpoint', () async {
    final item = SyncItem(
      id: 'sync-item-test-1',
      payload: '{"subjectId":"local-subject","id":"coleta-1"}',
      createdAt: DateTime.utc(2026, 10, 5),
      attempts: 2,
      endpoint: '/school-collections',
    );

    await SyncQueueStore.enqueue(item);
    final pending = await SyncQueueStore.pending();

    expect(pending, hasLength(1));
    expect(pending.single.payload, contains('local-subject'));
    expect(pending.single.attempts, 2);
    expect(pending.single.endpoint, '/school-collections');
  });

  test('401 de access retém fila e 401 de refresh limpa sessão e reautentica',
      () async {
    const itemId = 'expired-session-sync-item';
    var authenticationRequests = 0;
    await ConcessaoAcessoStore.save(
      ConcessaoAcessoModel(
        id: 'active-auth-school-grant',
        perfilAlvo: escolaPerfilAlvo,
        permiteLeituraMetas: true,
        permiteEscritaDados: true,
        dataExpiracao: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    await AuthTokenService.saveSessionTokens(
      accessToken: 'access-expired',
      refreshToken: 'refresh-expired-seven-days',
    );
    await SyncQueueStore.enqueue(
      SyncItem(
        id: itemId,
        payload: '{"subjectId":"local-subject","id":"expired-collection"}',
        createdAt: DateTime.utc(2026, 10, 5),
        endpoint: '/school-collections',
      ),
    );

    AuthTokenService.onAuthenticationRequired = () {
      authenticationRequests += 1;
    };
    SyncQueueService.connectivityOverride = () async => true;
    SyncQueueService.postOverride = (uri, headers, body) async {
      expect(headers['authorization'], 'Bearer access-expired');
      return http.Response(
        '{"error":"TOKEN_EXPIRED","renewalRequired":true}',
        401,
      );
    };
    try {
      await SyncQueueService.syncPending();

      final afterAccessExpiry = (await SyncQueueStore.pending())
          .firstWhere((candidate) => candidate.id == itemId);
      expect(afterAccessExpiry.attempts, 0);
      expect(authenticationRequests, 1);

      // Simula a resposta 401 do endpoint de refresh após os sete dias.
      final refreshResponse = http.Response(
        '{"error":"REFRESH_TOKEN_EXPIRED"}',
        401,
      );
      if (refreshResponse.statusCode == 401) {
        await AuthTokenService.handleRefreshTokenExpired();
      }
      expect(await AuthTokenService.readToken(), isNull);
      expect(await AuthTokenService.readRefreshToken(), isNull);
      expect(authenticationRequests, 2);
    } finally {
      SyncQueueService.connectivityOverride = null;
      SyncQueueService.postOverride = null;
      AuthTokenService.onAuthenticationRequired = null;
      await SyncQueueStore.remove(
        (await SyncQueueStore.pending()).firstWhere(
          (candidate) => candidate.id == itemId,
        ),
      );
    }
  });
}
