import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../data/concessao_acesso_store.dart';
import '../../data/meta_esdm_store.dart';
import '../../data/sincronizacao_queue_store.dart';
import '../../domain/models/meta_esdm_model.dart';
import '../../domain/models/sincronizacao_queue_model.dart';
import '../../domain/services/mobile_pdf_service.dart';
import '../../domain/services/esdm_translator.dart';

class MetaEsdmState {
  final List<MetaEsdmModel> metas;
  final bool carregando;
  final bool salvando;
  final bool exportando;
  final Object? erro;

  const MetaEsdmState({
    this.metas = const [],
    this.carregando = true,
    this.salvando = false,
    this.exportando = false,
    this.erro,
  });

  MetaEsdmState copyWith({
    List<MetaEsdmModel>? metas,
    bool? carregando,
    bool? salvando,
    bool? exportando,
    Object? erro,
  }) {
    return MetaEsdmState(
      metas: metas ?? this.metas,
      carregando: carregando ?? this.carregando,
      salvando: salvando ?? this.salvando,
      exportando: exportando ?? this.exportando,
      erro: erro,
    );
  }
}

final metaEsdmControllerProvider = StateNotifierProvider<MetaEsdmController,
    MetaEsdmState>((ref) => MetaEsdmController());

class MetaEsdmController extends StateNotifier<MetaEsdmState> {
  MetaEsdmController() : super(const MetaEsdmState()) {
    carregarMetas();
  }

  Future<void> carregarMetas() async {
    try {
      final metas = await MetaEsdmStore.loadAll();
      state = state.copyWith(metas: metas, carregando: false);
    } catch (error) {
      state = state.copyWith(carregando: false, erro: error);
    }
  }

  Future<bool> adicionarMeta(String codigoTecnico) async {
    final code = codigoTecnico.trim().toUpperCase();
    if (EsdmTranslator.translate(code) == null || state.salvando) {
      return false;
    }

    state = state.copyWith(salvando: true, erro: null);
    try {
      final meta = MetaEsdmModel(
        id: const Uuid().v4(),
        codigoTecnicoDenver: code,
      );
      await MetaEsdmStore.save(meta);
      await _enqueueIfAllowed(meta, 'INSERT');
      state = state.copyWith(
        metas: [...state.metas, meta],
        salvando: false,
      );
      return true;
    } catch (error) {
      state = state.copyWith(salvando: false, erro: error);
      return false;
    }
  }

  Future<bool> atualizarMeta(MetaEsdmModel meta) async {
    if (state.salvando) return false;

    state = state.copyWith(salvando: true, erro: null);
    try {
      await MetaEsdmStore.save(meta);
      await _enqueueIfAllowed(meta, 'UPDATE');
      final updated = state.metas
          .map((item) => item.id == meta.id ? meta : item)
          .toList();
      state = state.copyWith(metas: updated, salvando: false);
      return true;
    } catch (error) {
      state = state.copyWith(salvando: false, erro: error);
      return false;
    }
  }

  Future<void> _enqueueIfAllowed(MetaEsdmModel meta, String action) async {
    final grant = await ConcessaoAcessoStore.findActive(
      especialistaPerfilAlvo,
    );
    if (grant == null) return;

    await SincronizacaoQueueStore.enqueue(
      SincronizacaoQueueModel(
        id: 'meta:${meta.id}:$action:${DateTime.now().microsecondsSinceEpoch}',
        payloadJson: jsonEncode({
          'id': meta.id,
          'codigoTecnicoDenver': meta.codigoTecnicoDenver,
          'status': meta.status,
          'passoAtualAba': meta.passoAtualAba,
        }),
        endpointAlvo: '/metas',
        acao: action,
      ),
    );
  }

  Future<bool> exportarRelatorioUnificado({String? subjectId}) async {
    if (state.exportando) return false;

    state = state.copyWith(exportando: true, erro: null);
    try {
      final bytes = await MobilePdfService.generate(
        subjectId: subjectId ??
            const String.fromEnvironment(
              'PORTAL_SUBJECT_ID',
              defaultValue: 'local-subject',
            ),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'relatorio_unificado_fala_comigo.pdf',
      );
      state = state.copyWith(exportando: false);
      return true;
    } catch (error) {
      state = state.copyWith(exportando: false, erro: error);
      return false;
    }
  }
}
