/// Estrutura amigável de uma meta técnica para família e escola.
class EsdmTranslation {
  final String missaoPais;
  final String dicaPratica;

  const EsdmTranslation({
    required this.missaoPais,
    required this.dicaPratica,
  });
}

/// Traduz códigos técnicos previamente cadastrados em orientações simples.
///
/// O mapa é curado e determinístico. Ele não diagnostica, altera metas ou
/// substitui a revisão de um especialista; códigos ausentes retornam null.
class EsdmTranslator {
  EsdmTranslator._();

  static const Map<String, EsdmTranslation> _translations = {
    'CE_N1_I5': EsdmTranslation(
      missaoPais: 'Estimular o uso da voz para pedir itens no dia a dia.',
      dicaPratica:
          'Segure o brinquedo favorito próximo ao seu rosto. Quando ele fizer qualquer vocalização ou som voluntário, elogie e entregue o item imediatamente.',
    ),
    'CE_N1_I6': EsdmTranslation(
      missaoPais: 'Ajudar a criança a pedir ajuda durante uma brincadeira.',
      dicaPratica:
          'Ofereça uma atividade que precise de ajuda e modele o cartão, gesto ou som de ajuda antes de continuar.',
    ),
    'SOC_N1_I3': EsdmTranslation(
      missaoPais: 'Praticar a troca de turnos em uma brincadeira curta.',
      dicaPratica:
          'Faça uma ação simples, espere a criança participar e sinalize claramente quando for a vez dela.',
    ),
  };

  /// Retorna a tradução curada para [codigoTecnico], ou null quando ainda não
  /// há uma versão revisada para esse código.
  static EsdmTranslation? traduzir(String codigoTecnico) {
    return _translations[codigoTecnico.trim().toUpperCase()];
  }

  /// Alias em inglês útil para camadas que ainda adotam nomenclatura técnica.
  static EsdmTranslation? translate(String codigoTecnico) =>
      traduzir(codigoTecnico);

  static Map<String, EsdmTranslation> get traducoes =>
      Map.unmodifiable(_translations);
}
