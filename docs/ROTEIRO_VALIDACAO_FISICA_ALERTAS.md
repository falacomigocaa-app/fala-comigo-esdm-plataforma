# Roteiro de validação física — alertas e acessibilidade

**Estado:** pronto para execução em aparelhos; não executado nesta sandbox.

Este roteiro cobre o próximo gate de maior prioridade. Os testes devem usar somente alertas, títulos e áudio sintéticos. Não registrar nomes, imagens, vozes ou identificadores de crianças.

## Pré-condições

- Um celular Android e um tablet Android, em versões suportadas pelo projeto.
- Um iPhone e, se possível, um iPad.
- Uma instalação limpa do app e uma instalação atualizada com um alerta previamente criado.
- Um alerta sintético: `Transição para guardar`, mensagem `Daqui a pouco vamos mudar`, antecedência de 1 minuto.
- Um segundo alerta sintético com áudio gravado sem conteúdo identificável.
- Registrar versão do sistema, modelo, orientação, permissões e resultado; não registrar conteúdo clínico.

## Matriz funcional

| ID | Cenário | Procedimento | Resultado esperado | Evidência |
|---|---|---|---|---|
| A-01 | Notificação permitida | Criar alerta agendado e aguardar a ocorrência | Notificação privada, sem título clínico sensível, com som/vibração configurados | ☐ |
| A-02 | Notificação negada | Negar permissão e criar alerta | App informa bloqueio; dados e alerta permanecem salvos; nenhum crash | ☐ |
| A-03 | Alarme exato negado | Negar alarme exato no Android e consultar a tela de permissões | Estado aparece como bloqueado; app continua utilizável localmente | ☐ |
| A-04 | App em segundo plano | Agendar, colocar app em background e bloquear tela | Alerta ocorre ou a limitação é informada claramente, sem perder configuração | ☐ |
| A-05 | App encerrado | Agendar, encerrar o app pelo sistema e aguardar | Alerta ocorre conforme capacidade do sistema; abrir a notificação leva à transição | ☐ |
| A-06 | Reinicialização | Agendar, reiniciar o aparelho e aguardar | Receiver restaura agenda quando suportado; sem duplicidade | ☐ |
| A-07 | DND/silencioso | Repetir com Não Perturbe e silencioso | Comportamento respeita política do sistema; status não promete som quando bloqueado | ☐ |
| A-08 | Bateria baixa | Repetir com economia de bateria | App não perde o alerta local; registrar eventual limitação do fabricante | ☐ |
| A-09 | Pausar/reativar | Alternar o Switch na lista parental | Pausar cancela; reativar agenda uma ocorrência; não duplica notificações | ☐ |
| A-10 | Adiar | Abrir alerta e selecionar `Não me perturbe por 5 minutos` | Instância atual é silenciada/cancelada e lembrete é criado uma única vez | ☐ |
| A-11 | Áudio gravado | Criar alerta com áudio sintético, reproduzir e agendar | Áudio toca quando disponível; ausência/corrupção tem fallback sem crash | ☐ |
| A-12 | Exclusão/wipe | Excluir alerta e executar exclusão local completa | Agenda é cancelada; fila local é removida; nenhum dado local reaparece | ☐ |

## Matriz de acessibilidade e layout

| ID | Cenário | Procedimento | Resultado esperado | Evidência |
|---|---|---|---|---|
| U-01 | Tela compacta | Usar celular estreito em retrato | Sem overflow; controles de alerta e segurança têm alvo mínimo de 48 dp | ☐ |
| U-02 | Tablet | Usar tablet em retrato e paisagem | Cabeçalho, métricas e lista permanecem legíveis | ☐ |
| U-03 | Texto ampliado | Usar escala de texto do sistema em 200% | Sem corte de rótulos essenciais; rolagem previsível | ☐ |
| U-04 | TalkBack/VoiceOver | Navegar pela lista, Switch, editar, excluir e adiar | Ordem de foco compreensível; estado ativo/pausado e ação são anunciados | ☐ |
| U-05 | Contraste percebido | Usar tema claro/escuro e brilho reduzido | Texto, estado e ações continuam distinguíveis; registrar qualquer falha | ☐ |
| U-06 | Rotação | Girar em telas de lista, edição e alerta em tela cheia | Sem perda de dados, overflow ou duplicação de ação | ☐ |
| U-07 | Teclado/insets | Abrir edição com teclado visível | Campos e botão salvar permanecem alcançáveis; sem conteúdo inacessível | ☐ |

## Dados de execução

- Aparelho/sistema: ______________________________
- Build/commit: _________________________________
- Data e hora: __________________________________
- Orientação: ☐ retrato ☐ paisagem
- Escala de texto: ______________________________
- Leitor de tela: ☐ desligado ☐ TalkBack ☐ VoiceOver
- Resultado geral: ☐ aprovado ☐ bloqueado ☐ inconclusivo
- Incidentes/reprodução: ________________________

## Critério de saída

O gate só pode ser marcado como concluído quando todos os cenários críticos `A-01` a `A-06`, `A-09`, `A-12`, `U-01`, `U-03` e `U-04` tiverem evidência em pelo menos um Android e os cenários equivalentes de notificação tiverem sido repetidos em iOS. Falhas de fabricante, permissão ou sistema devem ser registradas como limitações específicas, nunca ocultadas como sucesso.

A ausência de aparelho real não autoriza declarar esta fase concluída. O código permanece local-first e nenhum login, plano ou conexão pode bloquear a comunicação básica.
