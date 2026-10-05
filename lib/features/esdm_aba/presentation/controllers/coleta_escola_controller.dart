import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/coleta_escola_store.dart';
import '../../domain/models/coleta_escola_model.dart';
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
  final bool salvando;
  final ColetaEscolaModel? ultimaColeta;
  final String? sincronizacaoStatus;
  final Object? erro;

  const ColetaEscolaState({
    this.blocoSelecionado,
    this.nivelSuporteSelecionado,
    this.salvando = false,
    this.ultimaColeta,
    this.sincronizacaoStatus,
    this.erro,
  });

  bool get podeRegistrar =>
      blocoSelecionado != null && nivelSuporteSelecionado != null && !salvando;

  ColetaEscolaState copyWith({
    String? blocoSelecionado,
    String? nivelSuporteSelecionado,
    bool? salvando,
    ColetaEscolaModel? ultimaColeta,
    String? sincronizacaoStatus,
    Object? erro,
  }) {
    return ColetaEscolaState(
      blocoSelecionado: blocoSelecionado ?? this.blocoSelecionado,
      nivelSuporteSelecionado:
          nivelSuporteSelecionado ?? this.nivelSuporteSelecionado,
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
  ColetaEscolaController() : super(const ColetaEscolaState());

  void selecionarBloco(String bloco) {
    state = state.copyWith(blocoSelecionado: bloco, erro: null);
  }

  void selecionarNivelSuporte(String nivel) {
    state = state.copyWith(nivelSuporteSelecionado: nivel, erro: null);
  }

  Future<bool> registrar() async {
    final bloco = state.blocoSelecionado;
    final nivel = state.nivelSuporteSelecionado;
    if (bloco == null || nivel == null || state.salvando) return false;

    state = state.copyWith(salvando: true, erro: null);
    try {
      final coleta = ColetaEscolaModel(
        id: const Uuid().v4(),
        dataRegistro: DateTime.now(),
        blocoRotinaEscolar: bloco,
        nivelSuporte: nivel,
      );
      await ColetaEscolaStore.save(coleta);
      final syncStatus = await SyncQueueService.saveOrSyncCollection(
        coleta: coleta,
        subjectId: syncSubjectId,
      );
      state = state.copyWith(
        salvando: false,
        ultimaColeta: coleta,
        sincronizacaoStatus: syncStatus.name,
      );
      return true;
    } catch (error) {
      state = state.copyWith(salvando: false, erro: error);
      return false;
    }
  }

}
