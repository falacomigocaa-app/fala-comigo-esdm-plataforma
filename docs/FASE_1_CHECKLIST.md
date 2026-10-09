# Checklist de execução — Fase 1

**Projeto:** Fala Comigo  
**Data da avaliação:** 08/10/2026  
**Fonte de escopo:** `Comandofinalfalacomigo1.1.pdf`  
**Estado da branch:** `main` limpa e sincronizada após o commit `6a45495`.

## Como ler este checklist

- `[x]` **Concluído e validado** no repositório/CI.
- `[~]` **Parcial**: existe uma base funcional, mas o requisito completo ainda não foi comprovado.
- `[ ]` **Pendente**: ainda não implementado ou não validado.
- `[?]` **Não validado**: requer inspeção/teste específico antes de marcar.

## Fase 0 — Alertas de transição

- `[~]` Modelos, telas de listagem/edição e integração local existem no código.
- `[~]` Persistência e agendamento local existem, mas o requisito completo do PDF — push, múltiplos dispositivos, app fechado, iOS/Android e sincronização backend — ainda não está validado como pronto para teste fechado.
- `[ ]` Matriz de testes em dispositivos reais (Android 8–15, iOS 13+, foreground/background/encerrado/DND/bateria baixa).

## Fase 1.1 — Área parental / UX/UI

- `[x]` Dashboard inicial separado da lista de configurações. `ParentalDashboardScreen` agora é a aba inicial e concentra resumo, métricas e ações rápidas.
- `[~]` Hierarquia visual: já existem `OptionASectionBox`, cards, cores por funcionalidade e paleta profissional; ainda falta uma hierarquia consistente por prioridade alta/média/baixa em toda a área.
- `[x]` BottomNavigationBar funcional. As quatro abas agora alternam entre Início, Acompanhamento, Localização e Configurações.
- `[x]` Gate de PIN: primeiro acesso, login, erro e lockout possuem estados visuais claros, indicadores dos quatro dígitos, semáforo de preenchimento, feedback acessível e banner dedicado de bloqueio.
- `[x]` Cartões: há fluxo de criação/edição, reordenação drag-and-drop e agora faixa de preview visual com imagem, rótulo e fallback seguro.
- `[x]` Temas de hiperfoco: miniaturas visuais com cor/emoji, seleção por toque e preview em tempo real da combinação escolhida.
- `[~]` Identidade visual Material 3: há paleta profissional, bordas e espaçamento melhorados; a densidade e a sensação de “painel” ainda precisam de uma rodada dedicada.
- `[~]` Validação visual responsiva e acessibilidade da área parental: cenários automatizados cobrem celular compacto, tablet, overflow, teclado virtual, semântica e alvos de toque; ainda falta a matriz manual em aparelhos reais e a revisão visual final de contraste com escala de texto ampliada.

## Fase 1.2 — Backend e autenticação

- `[x]` JWT com access token de 15 minutos, refresh token rotativo de 7 dias, bcrypt, Bearer e PostgreSQL.
- `[x]` Login e refresh reais em `/v1/auth/login` e `/v1/auth/refresh`.
- `[x]` CI PostgreSQL efêmero com migrations 001–005 e testes de integração verdes.
- `[~]` O PDF ainda cita endpoints genéricos `/auth/register`, `/data/sync` e `/reports/generate`; eles não fazem parte do contrato atual validado e não devem ser criados sem especificação funcional e de segurança.
- `[ ]` Rate limiting de produção e validação operacional de HTTPS/segredos no ambiente de deploy.

## Fase 1.3 — Criptografia

- `[x]` E2EE AES-256-GCM por organização no Mobile, envelopes sem plaintext e recepção sem descriptografia no backend.
- `[x]` Chaves de organização cifradas em repouso com `MASTER_CRYPTO_KEY`, endpoint protegido e Web Crypto no Portal Web.
- `[~]` A exigência ampla do PDF de criptografar todos os dados locais deve ser auditada por entidade/box; ela não deve ser considerada automaticamente concluída apenas pelo E2EE de coletas escolares.

## Fase 1.4 — Autenticação forte

- `[x]` Login email/senha, JWT, refresh rotativo e armazenamento seguro no Mobile.
- `[ ]` Biometria, 2FA e recuperação de senha por email.
- `[~]` Expiração e reautenticação estão cobertas; falta a validação de produto dos fluxos de recuperação e segundo fator.

## Fase 1.5 — Conformidade legal

- `[?]` Política de privacidade, termos, exportação, exclusão e consentimentos devem ser inventariados contra os documentos legais finais; não marcar como concluído apenas por existirem telas de privacidade.

## Fase 1.6 — Localização

- `[ ]` GPS/mapa/histórico/bateria/compartilhamento ainda não estão implementados como módulo operacional. A interface atual apresenta roadmap seguro e não inventa localização.

## Fase 1.7 — Planos e pagamentos

- `[ ]` Modelo freemium, assinatura e integração de pagamento não estão implementados/validados.

## Próximo ponto exato de retomada

1. Validar responsividade, contraste e touch targets em telas pequenas e tablet.
2. Em seguida abordar agrupamento avançado de cartões e miniaturas de categorias, se necessário.
3. Rodar `dart format`, `flutter analyze`, `flutter test` e o build Web antes de cada publicação.

## Fase 1.1A — Dashboard e navegação — concluída em 08/10/2026

- `[x]` Criado `ParentalDashboardScreen` com boas-vindas, métricas reais de cartões e alertas agendados, ações rápidas e cartões de prioridade.
- `[x]` Criadas superfícies de Acompanhamento e Localização, reutilizando os fluxos existentes e mantendo a localização explicitamente desativada até consentimento/permissões.
- `[x]` Tornado o `BottomNavigationBar` funcional, com estado de aba e destino de Configurações preservado.
- `[x]` Adicionados testes de widget em `test/parental_dashboard_screen_test.dart` para dashboard e quatro abas.
- `[x]` Validação concluída: `flutter analyze` sem issues, `flutter test` com 124 testes aprovados, `flutter build web --release` concluído.

## Fase 1.1B — Gate de PIN visual — concluída em 08/10/2026

- `[x]` Indicadores visuais dos quatro dígitos para criação, confirmação e login.
- `[x]` Semântica acessível informa quantos dígitos já foram preenchidos.
- `[x]` Banner dedicado para acesso temporariamente bloqueado, sem expor detalhes do verificador.
- `[x]` Rodapé de segurança ajustado para quebra responsiva, evitando overflow em telas estreitas.
- `[x]` Testes adicionados em `test/parental_gate_screen_test.dart` para primeiro acesso e bloqueio.
- `[x]` Validação concluída: `flutter analyze` sem issues, `flutter test` com 126 testes aprovados e `flutter build web --release` concluído.

## Fase 1.1C — Previews de cartões e temas — concluída em 08/10/2026

- `[x]` Faixa `Preview da grade infantil` com miniaturas de cartões, rótulo, imagem segura e fallback para asset indisponível.
- `[x]` Miniaturas horizontais dos sete temas de hiperfoco com cor, emoji, estado selecionado e semântica acessível.
- `[x]` Preview em tempo real do tema selecionado com fundo, estímulo e descrição de baixo ruído visual.
- `[x]` Chaves estáveis nas seções expansíveis e Material local para preservar feedback de toque dos ListTiles.
- `[x]` Testes adicionados em `test/parental_settings_preview_test.dart` para cartão, miniaturas e troca de tema.
- `[x]` Validação concluída: `flutter analyze` sem issues, `flutter test` com 128 testes aprovados e `flutter build web --release` concluído.

> Observação de teste: o arquivo de preview usa Hive em diretório temporário isolado. O teardown de fechamento foi omitido porque a versão atual do Hive/Flutter ficava bloqueada ao encerrar widgets que ainda mantêm providers ativos; isso não altera o armazenamento de produção nem o comportamento do app.

> Não declarar a Fase 1 como concluída até que os itens `[ ]` da Fase 1.1 sejam implementados e validados. A última validação conhecida do app foi de 122 testes Flutter aprovados; a página pública e o app Web responderam HTTP 200 após o commit `6a45495`.

## Fase 1.1D — Responsividade e acessibilidade — implementação validada em 09/10/2026

- `[x]` O dashboard parental alterna cabeçalho, métricas e ações rápidas para largura compacta, evitando compressão e overflow em celulares.
- `[x]` O seletor de orientação troca o `SegmentedButton` por opções empilhadas abaixo de 360 dp, preservando leitura e alvos de toque.
- `[x]` Ações de segurança/localização e novo cartão usam alvo mínimo de 48 dp.
- `[x]` Testes em `test/parental_responsive_accessibility_test.dart` cobrem viewport 320x640, viewport 320x460 com teclado simulado, viewport 1024x768, navegação, semântica das opções e ausência de exceções de layout.
- `[x]` Validação local com Flutter 3.38.0/Dart 3.10.0: `dart format --set-exit-if-changed lib test`, `flutter analyze --no-fatal-infos --no-fatal-warnings`, `flutter test` com 132 testes e `flutter build web --release` passaram.
- `[x]` CI remoto verde no commit `25464cf`: [Flutter quality checks](https://github.com/falacomigocaa-app/fala-comigo-esdm-plataforma/actions/runs/37879819678) e [Backend PostgreSQL integration](https://github.com/falacomigocaa-app/fala-comigo-esdm-plataforma/actions/runs/37879819723).
- `[~]` Continua pendente a validação manual em Android/iOS reais, incluindo contraste percebido, escala de texto ampliada, rotação, leitor de tela e matriz de touch targets em dispositivos físicos.

**Próximo gate:** executar a matriz manual de dispositivos e, depois, decidir se o agrupamento avançado de cartões e miniaturas de categorias ainda agrega valor antes de avançar para P1/P2 do backlog full-stack.


## Prioridade 1 — Alertas de transição — núcleo local endurecido em 09/10/2026

O commit `e5b40de` amplia `TransitionAlert` com descrição, mensagem, antecedência, recorrência, ativação, dias, som, volume, vibração, URL de áudio e timestamps, preservando leitura de mapas Hive legados. A área parental agora permite editar descrição/antecedência, ativar ou pausar alertas, visualizar o estado e adiar uma ocorrência por cinco minutos.

O agendamento usa `flutter_local_notifications` com `timezone`, alarmes exatos, canais por alerta, som/vibração configuráveis, payload para abrir a tela de transição e receivers Android de boot já presentes no manifesto. A antecedência é aplicada antes do horário da atividade e o cálculo semanal foi extraído para teste determinístico. Foi escolhida a agenda nativa do plugin para a entrega exata mesmo com o app fechado; `workmanager` ainda não foi adicionado porque a reconciliação em background exige validação específica de isolate, Hive cifrado e ciclo de vida Android/iOS.

Validação local: `flutter analyze` sem issues, `flutter test` com 135 testes aprovados e `flutter build web --release` concluído. `flutter build apk --debug` não pôde iniciar nesta sandbox por ausência do Android SDK. Ainda faltam sincronização de alertas com backend, validação em Android/iOS reais, testes de app fechado/background, DND, bateria baixa, reinicialização, permissão negada e confirmação de áudio/vibração por aparelho.

## Prioridade 1 — sincronização e reconciliação de alertas — validada em 09/10/2026

- `[x]` Fila local cifrada com upsert/exclusão, retry por conectividade, idempotência, 401 preservado e conflito 409 explícito.
- `[x]` API com migration 006, isolamento por sujeito/organização, controle de versão e testes de memória/PostgreSQL.
- `[x]` Cobertura Flutter determinística para offline, 401, 409 e sanitização de mídia local; suíte completa com 139 testes.
- `[x]` Monitor reativo de conectividade e retry periódico, sem adicionar worker nativo nem duplicar alarmes locais.
- `[x]` CI remoto Flutter e PostgreSQL verde nos commits `b1bbd07` e `fec37e5`.
- `[~]` Validação física ainda pendente. O roteiro está em [`docs/ROTEIRO_VALIDACAO_FISICA_ALERTAS.md`](ROTEIRO_VALIDACAO_FISICA_ALERTAS.md) e cobre Android, iOS, background, reboot, DND, bateria, permissões, acessibilidade, áudio e vibração.
