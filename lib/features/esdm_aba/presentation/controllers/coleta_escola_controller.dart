import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/concessao_acesso_store.dart';
import '../../data/coleta_escola_store.dart';
import '../../data/sincronizacao_queue_store.dart';
import '../../domain/models/coleta_escola_model.dart';
import '../../domain/models/sincronizacao_queue_model.dart';

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
  final Object? erro;

  const ColetaEscolaState({
    this.blocoSelecionado,
    this.nivelSuporteSelecionado,
    this.salvando = false,
    this.ultimaColeta,
    this.erro,
  });

  bool get podeRegistrar =>
      blocoSelecionado != null && nivelSuporteSelecionado != null && !salvando;

  ColetaEscolaState copyWith({
    String? blocoSelecionado,
    String? nivelSuporteSelecionado,
    bool? salvando,
    ColetaEscolaModel? ultimaColeta,
    Object? erro,
  }) {
    return ColetaEscolaState(
      blocoSelecionado: blocoSelecionado ?? this.blocoSelecionado,
      nivelSuporteSelecionado:
          nivelSuporteSelecionado ?? this.nivelSuporteSelecionado,
      salvando: salvando ?? this.salvando,
      ultimaColeta: ultimaColeta ?? this.ultimaColeta,
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
      await _enqueueIfAllowed(coleta);
      state = state.copyWith(salvando: false, ultimaColeta: coleta);
      return true;
    } catch (error) {
      state = state.copyWith(salvando: false, erro: error);
      return false;
    }
  }

  Future<void> _enqueueIfAllowed(ColetaEscolaModel coleta) async {
    final grant = await ConcessaoAcessoStore.findActive(escolaPerfilAlvo);
    if (grant == null) return;

    await SincronizacaoQueueStore.enqueue(
      SincronizacaoQueueModel(
        id: 'coleta:${coleta.id}:INSERT',
        payloadJson: jsonEncode({
          'id': coleta.id,
          'dataRegistro': coleta.dataRegistro.toIso8601String(),
          'blocoRotinaEscolar': coleta.blocoRotinaEscolar,
          'nivelSuporte': coleta.nivelSuporte,
        }),
        endpointAlvo: '/coletas',
        acao: 'INSERT',
      ),
    );
  }
}
