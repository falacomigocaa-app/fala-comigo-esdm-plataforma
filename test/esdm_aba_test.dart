import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:fala_comigo/features/esdm_aba/data/concessao_acesso_store.dart';
import 'package:fala_comigo/features/esdm_aba/data/sincronizacao_queue_store.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/concessao_acesso_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/models/sincronizacao_queue_model.dart';
import 'package:fala_comigo/features/esdm_aba/domain/services/esdm_translator.dart';

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
}
