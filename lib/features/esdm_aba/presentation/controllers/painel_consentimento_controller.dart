import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/concessao_acesso_store.dart';
import '../../domain/models/concessao_acesso_model.dart';

class PainelConsentimentoState {
  final bool permitindoEscola;
  final bool permitindoEspecialistas;
  final DateTime dataExpiracao;
  final bool carregando;
  final bool salvando;
  final Object? erro;

  const PainelConsentimentoState({
    required this.dataExpiracao,
    this.permitindoEscola = false,
    this.permitindoEspecialistas = false,
    this.carregando = true,
    this.salvando = false,
    this.erro,
  });

  bool get acessoExpirado => !dataExpiracao.isAfter(DateTime.now());

  PainelConsentimentoState copyWith({
    bool? permitindoEscola,
    bool? permitindoEspecialistas,
    DateTime? dataExpiracao,
    bool? carregando,
    bool? salvando,
    Object? erro,
  }) {
    return PainelConsentimentoState(
      permitindoEscola: permitindoEscola ?? this.permitindoEscola,
      permitindoEspecialistas:
          permitindoEspecialistas ?? this.permitindoEspecialistas,
      dataExpiracao: dataExpiracao ?? this.dataExpiracao,
      carregando: carregando ?? this.carregando,
      salvando: salvando ?? this.salvando,
      erro: erro,
    );
  }
}

final painelConsentimentoControllerProvider = StateNotifierProvider<
    PainelConsentimentoController, PainelConsentimentoState>(
  (ref) => PainelConsentimentoController(),
);

class PainelConsentimentoController
    extends StateNotifier<PainelConsentimentoState> {
  Timer? _expirationTimer;

  PainelConsentimentoController()
      : super(
          PainelConsentimentoState(
            dataExpiracao: DateTime.now().add(const Duration(days: 90)),
          ),
        ) {
    carregar();
  }

  Future<void> carregar() async {
    try {
      final concessoes = await ConcessaoAcessoStore.loadAll();
      final escola = _find(concessoes, escolaPerfilAlvo);
      final especialistas = _find(concessoes, especialistaPerfilAlvo);
      final expiration = escola?.dataExpiracao ??
          especialistas?.dataExpiracao ??
          state.dataExpiracao;
      final expired = !expiration.isAfter(DateTime.now());

      state = state.copyWith(
        permitindoEscola: !expired && _isEnabled(escola),
        permitindoEspecialistas: !expired && _isEnabled(especialistas),
        dataExpiracao: expiration,
        carregando: false,
      );
      _scheduleExpiration(expiration);
    } catch (error) {
      state = state.copyWith(carregando: false, erro: error);
    }
  }

  Future<void> definirAcessoEscola(bool permitido) async {
    state = state.copyWith(permitindoEscola: permitido, erro: null);
    await _persistir();
  }

  Future<void> definirAcessoEspecialistas(bool permitido) async {
    state = state.copyWith(permitindoEspecialistas: permitido, erro: null);
    await _persistir();
  }

  Future<void> definirDataExpiracao(DateTime data) async {
    final normalized = DateTime(data.year, data.month, data.day, 23, 59, 59);
    state = state.copyWith(dataExpiracao: normalized, erro: null);
    _scheduleExpiration(normalized);
    await _persistir();
  }

  void _scheduleExpiration(DateTime expiration) {
    _expirationTimer?.cancel();
    final remaining = expiration.difference(DateTime.now());
    _expirationTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () async {
        state = state.copyWith(
          permitindoEscola: false,
          permitindoEspecialistas: false,
        );
        await _persistir();
      },
    );
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    super.dispose();
  }

  Future<void> _persistir() async {
    if (state.carregando || state.salvando) return;
    state = state.copyWith(salvando: true, erro: null);
    try {
      final expiration = state.dataExpiracao;
      await ConcessaoAcessoStore.save(
        ConcessaoAcessoModel(
          id: escolaPerfilAlvo,
          perfilAlvo: escolaPerfilAlvo,
          permiteLeituraMetas: state.permitindoEscola,
          permiteEscritaDados: state.permitindoEscola,
          dataExpiracao: expiration,
        ),
      );
      await ConcessaoAcessoStore.save(
        ConcessaoAcessoModel(
          id: especialistaPerfilAlvo,
          perfilAlvo: especialistaPerfilAlvo,
          permiteLeituraMetas: state.permitindoEspecialistas,
          permiteEscritaDados: state.permitindoEspecialistas,
          dataExpiracao: expiration,
        ),
      );
      state = state.copyWith(salvando: false);
    } catch (error) {
      state = state.copyWith(salvando: false, erro: error);
    }
  }

  static ConcessaoAcessoModel? _find(
    Iterable<ConcessaoAcessoModel> concessoes,
    String perfil,
  ) {
    for (final concessao in concessoes) {
      if (concessao.perfilAlvo == perfil) return concessao;
    }
    return null;
  }

  static bool _isEnabled(ConcessaoAcessoModel? concessao) {
    if (concessao == null || !concessao.estaAtiva) return false;
    return concessao.permiteLeituraMetas || concessao.permiteEscritaDados;
  }
}
