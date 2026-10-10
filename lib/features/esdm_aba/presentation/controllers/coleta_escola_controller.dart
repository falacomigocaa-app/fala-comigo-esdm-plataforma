import '../../../../core/services/auth_token_service.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/coleta_escola_store.dart';
import '../../data/concessao_acesso_store.dart';
import '../../data/goal_store.dart';
import '../../domain/models/coleta_escola_model.dart';
import '../../domain/models/meta_esdm_model.dart';
import '../../domain/services/goal_sync_service.dart';
import '../../domain/services/sync_queue_service.dart';

const blocosRotinaEscolar = [
  'Lanche',
  'Recreio',
  'Roda de Conversa',
  'Atividade Sentada',
];

const niveisSuporte = [
  'Independente',
  'Ajuda Verbal',
  'Ajuda Física',
  'Recusa',
];

class ColetaEscolaState {
  final String? blocoSelecionado;
  final String? nivelSuporteSelecionado;
  final String? metaSelecionadaId;
  final List<MetaEsdmModel> metas;
  final bool carregandoMetas;
  final bool consentimentoBloqueado;
  final bool salvando;
  final ColetaEscolaModel? ultimaColeta;
  final String? sincronizacaoStatus;
  final Object? erro;

  const ColetaEscolaState({
    this.blocoSelecionado,
    this.nivelSuporteSelecionado,
    this.metaSelecionadaId,
    this.metas = const [],
    this.carregandoMetas = false,
    this.consentimentoBloqueado = false,
    this.salvando = false,
    this.ultimaColeta,
    this.sincronizacaoStatus,
    this.erro,
  });

  bool get podeRegistrar =>
      blocoSelecionado != null &&
      nivelSuporteSelecionado != null &&
      !salvando &&
      !consentimentoBloqueado;

  ColetaEscolaState copyWith({
    String? blocoSelecionado,
    String? nivelSuporteSelecionado,
    String? metaSelecionadaId,
    List<MetaEsdmModel>? metas,
    bool? carregandoMetas,
    bool? consentimentoBloqueado,
    bool? salvando,
    ColetaEscolaModel? ultimaColeta,
    String? sincronizacaoStatus,
    Object? erro,
  }) {
    return ColetaEscolaState(
      blocoSelecionado: blocoSelecionado ?? this.blocoSelecionado,
      nivelSuporteSelecionado:
          nivelSuporteSelecionado ?? this.nivelSuporteSelecionado,
      metaSelecionadaId: metaSelecionadaId ?? this.metaSelecionadaId,
      metas: metas ?? this.metas,
      carregandoMetas: carregandoMetas ?? this.carregandoMetas,
      consentimentoBloqueado:
          consentimentoBloqueado ?? this.consentimentoBloqueado,
      salvando: salvando ?? this.salvando,
      ultimaColeta: ultimaColeta ?? this.ultimaColeta,
      sincronizacaoStatus: sincronizacaoStatus ?? this.sincronizacaoStatus,
      erro: erro,
    );
  }
}

final coletaEscolaControllerProvider = StateNotifierProvider.autoDispose<
    ColetaEscolaController, ColetaEscolaState>(
  (ref) => ColetaEscolaController(),
);

class ColetaEscolaController extends StateNotifier<ColetaEscolaState> {
  ColetaEscolaController() : super(const ColetaEscolaState()) {
    SyncQueueService.consentBlockedNotifier.addListener(_onConsentChanged);
    unawaited(_initializeConsent());
    unawaited(_initializeGoals());
  }

  Future<void> _initializeConsent() async {
    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo,
        requireWrite: true);
    state = state.copyWith(consentimentoBloqueado: grant == null);
  }

  void _onConsentChanged() {
    state = state.copyWith(
      consentimentoBloqueado: SyncQueueService.consentBlocked,
    );
  }

  Future<void> _initializeGoals() async {
    state = state.copyWith(carregandoMetas: true);
    try {
      final subjectId = await AuthTokenService.readSubjectId();
      final cached =
          await GoalStore.loadForSubject(subjectId ?? 'local-subject');
      state = state.copyWith(
        metas: cached,
        metaSelecionadaId: cached.isEmpty ? null : cached.first.id,
      );
      if (subjectId != null) {
        await GoalSyncService.syncActiveGoals(subjectId: subjectId);
      }
      final refreshed =
          await GoalStore.loadForSubject(subjectId ?? 'local-subject');
      state = state.copyWith(
        metas: refreshed,
        carregandoMetas: false,
        metaSelecionadaId: refreshed.isEmpty ? null : refreshed.first.id,
      );
    } catch (error) {
      state = state.copyWith(carregandoMetas: false, erro: error);
    }
  }

  void selecionarBloco(String bloco) {
    state = state.copyWith(blocoSelecionado: bloco, erro: null);
  }

  void selecionarNivelSuporte(String nivel) {
    state = state.copyWith(nivelSuporteSelecionado: nivel, erro: null);
  }

  void selecionarMeta(String? metaId) {
    if (metaId == null || metaId.isEmpty) return;
    state = state.copyWith(metaSelecionadaId: metaId, erro: null);
  }

  Future<bool> registrar() async {
    final bloco = state.blocoSelecionado;
    final nivel = state.nivelSuporteSelecionado;
    if (bloco == null ||
        nivel == null ||
        state.salvando ||
        state.consentimentoBloqueado) {
      return false;
    }

    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo,
        requireWrite: true);
    if (grant == null) {
      SyncQueueService.consentBlockedNotifier.value = true;
      return false;
    }

    state = state.copyWith(salvando: true, erro: null);
    try {
      final subjectId = await AuthTokenService.readSubjectId();
      final coleta = ColetaEscolaModel(
        id: const Uuid().v4(),
        dataRegistro: DateTime.now(),
        blocoRotinaEscolar: bloco,
        nivelSuporte: nivel,
        metaId: state.metaSelecionadaId,
        subjectId: subjectId,
      );
      await ColetaEscolaStore.save(coleta);
      final syncStatus = subjectId == null
          ? SyncOutcome.localOnly
          : await SyncQueueService.saveOrSyncCollection(
              coleta: coleta,
              subjectId: subjectId,
            );
      state = state.copyWith(
        salvando: false,
        ultimaColeta: coleta,
        sincronizacaoStatus: syncStatus.name,
        consentimentoBloqueado: syncStatus == SyncOutcome.blockedByConsent,
      );
      return true;
    } catch (error) {
      state = state.copyWith(salvando: false, erro: error);
      return false;
    }
  }

  @override
  void dispose() {
    SyncQueueService.consentBlockedNotifier.removeListener(_onConsentChanged);
    super.dispose();
  }
}
