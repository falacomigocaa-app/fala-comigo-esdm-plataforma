# CONTINUIDADE — Ecossistema ESDM/ABA

## Status atual do projeto

O escopo funcional local do ecossistema `esdm_aba` está **100% implementado na branch `main` local** e preparado para a próxima etapa de validação e publicação. Nenhum commit, merge ou push foi executado durante esta sequência.

A implementação local inclui:

- modelos Hive para concessões, metas e coletas escolares;
- modelo Hive de fila offline e adapter com ID reservado `13`;
- adapters Hive com IDs reservados `10`, `11`, `12` e `13`;
- boxes cifradas para concessões e metas com chaves AES-256 armazenadas no `flutter_secure_storage`;
- coleta escolar com controller Riverpod, persistência assíncrona e interface sem teclado;
- painel parental de consentimento com expiração automática;
- plano de metas ESDM traduzido para linguagem familiar;
- exportação de relatório unificado em PDF pela folha nativa de compartilhamento;
- gráfico CustomPainter de tendência semanal de autonomia;
- dashboard com média semanal e bloco de maior autonomia na última semana;
- fila offline cifrada para coletas e metas, condicionada à concessão ativa;
- cliente local `CuidadoConectadoClient` com bloqueio terminal por expiração/revogação;
- política SQL documental de RLS para a futura API Supabase;
- Alertas de Transição sem controles de diagnóstico, com reprodução centralizada de voz gravada, TTS e fallback de alerta do sistema;
- rotas e acessos da Área Parental amarrados no `main.dart` e em `settings_screen.dart`.

> **Nota de validação:** o escopo funcional foi implementado localmente, mas o ambiente desta sessão não possui a toolchain `dart`/`flutter`. Antes de considerar a build Web certificada para produção, executar `dart format`, `flutter analyze`, testes e `flutter build web` em um ambiente Flutter configurado.

## Controle de qualidade

Suíte adicionada em `test/esdm_aba_test.dart`. Ela cobre os três cenários críticos do ecossistema:

1. **Metodologia ESDM/ABA:** `EsdmTranslator.traduzir('CE_N1_I5')` retorna a missão familiar e a dica prática curadas, não nulas e com conteúdo exato.
2. **Soberania dos dados:** uma concessão com `dataExpiracao` no passado não é retornada por `ConcessaoAcessoStore.findActive`.
3. **Resiliência offline:** um `SincronizacaoQueueModel` enfileirado é recuperado como pendente pela `SincronizacaoQueueStore`, preservando payload, endpoint e ação.

Os testes usam diretório Hive temporário e mock do channel do `flutter_secure_storage`, sem rede ou dados persistentes do usuário.

## Mapa de arquivos

### Models e adapters Hive

| Componente | Caminho | Hive typeId |
|---|---|---:|
| `ConcessaoAcessoModel` | `lib/features/esdm_aba/domain/models/concessao_acesso_model.dart` | 10 |
| Adapter de concessão | `lib/features/esdm_aba/domain/models/concessao_acesso_model.g.dart` | 10 |
| `MetaEsdmModel` | `lib/features/esdm_aba/domain/models/meta_esdm_model.dart` | 11 |
| Adapter de meta | `lib/features/esdm_aba/domain/models/meta_esdm_model.g.dart` | 11 |
| `ColetaEscolaModel` | `lib/features/esdm_aba/domain/models/coleta_escola_model.dart` | 12 |
| Adapter de coleta | `lib/features/esdm_aba/domain/models/coleta_escola_model.g.dart` | 12 |
| `SincronizacaoQueueModel` | `lib/features/esdm_aba/domain/models/sincronizacao_queue_model.dart` | 13 |
| Adapter da fila | `lib/features/esdm_aba/domain/models/sincronizacao_queue_model.g.dart` | 13 |

### Stores e segurança local

| Componente | Caminho | Responsabilidade |
|---|---|---|
| `EsdmSecureBoxService` | `lib/features/esdm_aba/data/esdm_secure_box_service.dart` | Chaves AES-256 por box via `flutter_secure_storage`; abertura de `concessoes_acesso_box` e `metas_esdm_box`. |
| `ConcessaoAcessoStore` | `lib/features/esdm_aba/data/concessao_acesso_store.dart` | Leitura e gravação cifrada das concessões parentais. |
| `MetaEsdmStore` | `lib/features/esdm_aba/data/meta_esdm_store.dart` | Leitura, gravação e remoção de metas na `metas_esdm_box`. |
| `ColetaEscolaStore` | `lib/features/esdm_aba/data/coleta_escola_store.dart` | Leitura e gravação cifrada da `coleta_escola_box`, com leitura compatível da box legada `coleta_escola`. |
| `SincronizacaoQueueStore` | `lib/features/esdm_aba/data/sincronizacao_queue_store.dart` | Fila cifrada `sincronizacao_queue_box`, pendências e marcação de processamento. |

### Services de domínio

| Componente | Caminho |
|---|---|
| `EsdmTranslator` | `lib/features/esdm_aba/domain/services/esdm_translator.dart` |
| `EsdmPdfService` | `lib/features/esdm_aba/domain/services/esdm_pdf_service.dart` |
| `CuidadoConectadoClient` | `lib/features/esdm_aba/domain/services/cuidado_conectado_client.dart` |

Política documental do backend: `lib/features/esdm_aba/supabase_rls_policy.sql`.

O `EsdmPdfService` expõe `gerarRelatorioUnificado()` e reúne metas traduzidas, coletas escolares e status das concessões.

### Controllers

| Controller | Caminho | Funções principais |
|---|---|---|
| `ColetaEscolaController` | `lib/features/esdm_aba/presentation/controllers/coleta_escola_controller.dart` | Seleção de rotina/suporte e persistência da coleta. |
| `PainelConsentimentoController` | `lib/features/esdm_aba/presentation/controllers/painel_consentimento_controller.dart` | Switches de acesso, data de expiração e revogação automática. |
| `MetaEsdmController` | `lib/features/esdm_aba/presentation/controllers/meta_esdm_controller.dart` | Carregar, adicionar, atualizar metas e compartilhar PDF. |

### Screens

| Screen | Caminho | Rota |
|---|---|---|
| `ColetaEscolaScreen` | `lib/features/esdm_aba/presentation/screens/coleta_escola_screen.dart` | `/coleta-escola` |
| `PainelConsentimentoScreen` | `lib/features/esdm_aba/presentation/screens/painel_consentimento_screen.dart` | `/painel-consentimento` |
| `MetasEsdmScreen` | `lib/features/esdm_aba/presentation/screens/metas_esdm_screen.dart` | `/metas-esdm` |
| `EsdmDashboardScreen` | `lib/features/esdm_aba/presentation/screens/esdm_dashboard_screen.dart` | `/esdm-dashboard` |

### Widgets

| Widget | Caminho |
|---|---|
| `EsdmEvolucaoChart` | `lib/features/esdm_aba/presentation/widgets/esdm_evolucao_chart.dart` |

### Frontend Portal Web — JavaScript Modular

| Componente | Caminho | Responsabilidade |
|---|---|---|
| Manifesto | `portal-web/package.json` | ES Modules nativos, scripts `start` e `check`. |
| Bootstrap | `portal-web/src/main.js` | Montagem do app, eventos de navegação e CSS. |
| Roteador | `portal-web/src/router.js` | Rotas `/login`, `/clinica` e `/escola`, com guardas de sessão. |
| Cliente/fixtures | `portal-web/src/api/client.js` | Sessão sintética, `x-synthetic-user-id`, `x-request-id`, fetch e dados de demonstração. |
| Autenticação | `portal-web/src/screens/auth_screen.js` | Login local sintético sem senha. |
| Clínica | `portal-web/src/screens/clinica_screen.js` | Pacientes autorizados e formulário de metas ESDM. |
| Escola | `portal-web/src/screens/escola_screen.js` | Rotina escolar e médias semanais de independência. |
| Estilos | `portal-web/src/styles.css` | Layout responsivo, tabelas, cartões e estados de acesso. |
| Página HTML | `portal-web/index.html` | Documento que carrega o bootstrap modular. |
| Servidor local | `portal-web/dev_server.mjs` | `node:http` com fallback de SPA para as rotas do frontend. |

## Integrações globais

### Bootstrap

Arquivo: `lib/main.dart`

Os adapters `ConcessaoAcessoModelAdapter`, `MetaEsdmModelAdapter`, `ColetaEscolaModelAdapter` e `SincronizacaoQueueModelAdapter` são registrados após `Hive.initFlutter()` e após o adapter nativo de cartões, com proteção `Hive.isAdapterRegistered(...)` para permitir retry do bootstrap sem erro de registro duplicado.

Quando a concessão correspondente está ativa e dentro do prazo, os controllers gravam eventos locais em `sincronizacao_queue_box`. O cliente atual não faz rede: `CuidadoConectadoClient` apenas simula POST/PUT/DELETE e só marca o evento como processado depois da verificação local de concessão.

### Rotas

Arquivo: `lib/main.dart`

```text
/coleta-escola
/painel-consentimento
/metas-esdm
/esdm-dashboard
```

### Área Parental

Arquivo: `lib/features/parental_area/presentation/screens/settings_screen.dart`

A lista de ações contém, nesta ordem, os acessos para:

1. Coleta rápida da escola;
2. Gerenciar Acessos e Permissões;
3. Plano de Metas Desenvolvimento (ESDM);
4. Gráficos e Relatórios de Evolução.

## Onde o projeto parou

A implementação local está na `main` e aguarda apenas:

1. instalação/seleção de uma toolchain Flutter compatível;
2. formatação, análise estática, testes e build Web;
3. revisão humana do diff;
4. commit final;
5. push para `origin/main` conforme autorização do responsável.

O working tree deliberadamente contém alterações não commitadas. Não fazer reset, checkout destrutivo ou limpeza ampla sem preservar os arquivos da feature.

## Varredura de branches

Foi feita uma comparação das 71 referências disponíveis: `main` local mais 70 referências remotas. A única branch diretamente relacionada a uma correção de paridade Web foi revisada e não integrada porque remove APIs ainda usadas por `main.dart` e pelas telas de mídia:

- `origin/fix/web-media-api-parity`
  - remove `MediaStorageService.releaseMaterializedFile`;
  - remove `MediaStorageService.clearStalePreviews`;
  - troca metadados do produto Web por valores padrão do Flutter.

As branches com `portal-api/`, `site/` e documentação de portal representam o escopo futuro do Cuidado Conectado e não foram mescladas automaticamente.

Relatório completo: `/home/ubuntu/relatorio-varredura-branches.md`.

## Diagnóstico do Portal Web para profissionais e escolas

### Resultado do rastreamento remoto

Foi executado `git fetch --all --prune` e foram encontradas 71 referências remotas. As referências diretamente relevantes para portal/site foram:

| Referência | Conteúdo encontrado | Tecnologia/status |
|---|---|---|
| `origin/feat/gate-3a-synthetic-permissions` | `portal-api/`, `site/portal.html`, `site/portal.css`, migrations e testes | API Node.js 22 com ES Modules e `node:http`; UI HTML/CSS estática; MVP sintético implementado para desenvolvimento |
| `origin/spec/mvp-portal-sintetico` | Mesmo `portal-api/`, além da especificação e ADR do portal independente | Contrato/Gate 1A e API sintética/Gate 3A; sem login real e sem dados reais |
| `origin/docs/site-published` | `site/portal.html`, `site/portal.css`, `site/rh/`, documentação de contrato | Site estático HTML/CSS; não é um cliente autenticado |
| `origin/site/creator-stable-link` | Prévia estática e documentação do site | HTML/CSS; sem backend de portal |
| `origin/site/public-contact-creator` | Prévia estática e documentação do site | HTML/CSS; sem backend de portal |
| `origin/site/visual-a11y-phase1` | Prévia estática, CSS e handoff de acessibilidade | HTML/CSS; sem backend de portal |
| `origin/feat/rh-portal-entitlement-boundary` | Ajustes de fronteira do portal RH e benefício | Alterações de site/documentação; nenhum frontend autenticado separado |
| `origin/feat/web-rh-benefit-clarity` | Clareza de benefício patrocinado no site | Alterações de site/documentação; nenhum frontend autenticado separado |
| `origin/recovery/pr29-with-current-web` | Recuperação da árvore Web e documentação | Flutter Web/site; não contém um portal profissional executável |

Não foram encontrados `package.json` de React/Vite/Next, `vite.config.*`, `next.config.*`, componentes JSX/TSX ou um diretório `portal-web/`. Portanto, o código de portal existente não é uma aplicação SPA: a interface em `site/portal.html` é uma prévia visual com botões sem integração de dados.

### Estrutura técnica existente

Na branch `origin/feat/gate-3a-synthetic-permissions`, o backend sintético está organizado assim:

```text
portal-api/
├── package.json
├── README.md
├── migrations/001_initial.sql
├── src/
│   ├── app.js             # roteador /v1, idempotência e auditoria
│   ├── authorization.js   # identidade sintética, membership, scopes e erros
│   ├── server.js          # adaptador HTTP local em 127.0.0.1:8787
│   └── store.js           # fixtures determinísticas em memória
└── test/
    ├── authorization.test.js
    └── postgres.integration.test.js
```

O servidor utiliza `x-synthetic-user-id` apenas para desenvolvimento local. A API agora cobre organizações, memberships, convites, consentimentos, grants, benefícios, auditoria, metas ESDM e histórico de coletas escolares. Ela ainda **não** possui autenticação real de produção; o `portal-api` continua restrito a ambiente sintético até a troca do adaptador de identidade e a validação server-side completa.

### Contrato inicial das duas telas

O portal profissional deve ser uma origem independente do GitHub Pages. A família continua controlando o consentimento; a interface não pode autorizar acesso apenas ocultando ou exibindo componentes. Toda leitura e escrita deverá ser revalidada no backend com `userId`, `organizationId`, `subjectId`, membership, escopo, finalidade, consentimento, validade e revogação.

#### 1. Painel da Clínica

**Objetivo:** permitir que um terapeuta autorizado consulte somente pacientes com grant ativo e proponha/registre metas ESDM.

Layout recomendado:

- navegação lateral com organização atual e estado da sessão;
- lista de pacientes autorizados, filtrada por `subjectId` e escopo vigente;
- cartão do paciente com status do vínculo, finalidade e data de expiração, sem expor prontuário integral;
- formulário de nova meta com `codigoTecnicoDenver`, tradução amigável (`missaoPais` e `dicaPratica`), status e `passoAtualAba`;
- histórico de versões da meta, autor, horário e evento de auditoria;
- confirmação explícita antes de publicar ou atualizar uma meta;
- indicação clara de acesso revogado/expirado, sem permitir edição offline silenciosa.

Endpoints a acrescentar ao contrato `/v1` — depois de revisão de segurança —:

```text
GET    /v1/organizations/{organizationId}/subjects?scope=esdm_goal.read
GET    /v1/subjects/{subjectId}/esdm-goals
POST   /v1/subjects/{subjectId}/esdm-goals
PATCH  /v1/subjects/{subjectId}/esdm-goals/{goalId}
GET    /v1/subjects/{subjectId}/esdm-goals/{goalId}/events
```

Os endpoints devem mapear `MetaEsdmModel` para DTOs versionados, nunca aceitar `subjectId` sem validar o grant, e usar `requestId` idempotente nas mutações.

#### 2. Painel da Escola

**Objetivo:** permitir que professor/equipe autorizada consulte somente a rotina pedagógica e o histórico mínimo de independência necessário ao contexto escolar.

Layout recomendado:

- seletor de turma/unidade limitado ao membership da escola;
- lista de estudantes autorizados com escopo `routine.read` e/ou `school_collection.read`;
- visão diária da rotina: Lanche, Recreio, Roda de Conversa e Atividade Sentada;
- histórico semanal com valores de independência derivados dos níveis `Recusa = 0`, `Ajuda Física = 1`, `Ajuda Verbal = 2`, `Independente = 3`;
- resumo por bloco, média semanal e observação funcional curta;
- não exibir metas clínicas, diagnóstico, prontuário ou relatórios ABC sem escopo específico;
- estados explícitos para ausência de consentimento, expiração, revogação e dados ainda não sincronizados.

Endpoints a acrescentar ao contrato `/v1` — também condicionados a escopo e finalidade:

```text
GET  /v1/organizations/{organizationId}/subjects?scope=routine.read
GET  /v1/subjects/{subjectId}/school-routine?from=...&to=...
GET  /v1/subjects/{subjectId}/school-collections?from=...&to=...
POST /v1/subjects/{subjectId}/school-collections
```

O DTO escolar deve ser uma projeção mínima de `ColetaEscolaModel`. A escola não deve receber automaticamente a lista completa de metas ESDM nem dados clínicos da clínica.

### Frontend portal-web implementado localmente

A alternativa escolhida foi JavaScript modular nativo com ES Modules, sem React, Vite ou dependências de runtime. A primeira estrutura funcional agora está presente localmente:

```text
portal-web/
├── package.json                # type: module; check de sintaxe dos módulos
├── src/
│   ├── main.js                 # bootstrap, CSS e eventos de navegação
│   ├── router.js               # /login, /clinica e /escola
│   ├── api/client.js           # sessão, header sintético, fetch e fixtures
│   ├── screens/
│   │   ├── auth_screen.js      # login sintético com x-synthetic-user-id
│   │   ├── clinica_screen.js    # pacientes e metas ESDM
│   │   └── escola_screen.js     # resumo semanal de ColetaEscolaModel
│   └── styles.css               # layout responsivo e acessível
```

O login atual é deliberadamente sintético: armazena apenas o identificador de desenvolvimento no `localStorage` e o cliente envia `x-synthetic-user-id` e `x-request-id` quando `PORTAL_API_BASE` estiver configurado. Sem API configurada, as telas usam fixtures sintéticas locais e deixam explícito que não há persistência remota.

O painel da clínica permite selecionar `CE_N1_I5`, `CE_N1_I6` e `SOC_N1_I3`, exibe a tradução familiar e tenta `POST /v1/subjects/{subjectId}/esdm-goals`. O painel escolar calcula o resumo por bloco com `Recusa = 0`, `Ajuda Física = 1`, `Ajuda Verbal = 2` e `Independente = 3`. A gravação remota real permanece bloqueada até que esses endpoints existam no backend e a autorização server-side seja validada.

Próximas extensões recomendadas: substituir a sessão sintética por um adaptador de identidade real, extrair componentes reutilizáveis, adicionar testes de navegador e conectar um `portal-api` persistente com OpenAPI, PostgreSQL, consentimento, escopos e revogação.

### Backend integrado ao frontend

O diretório `portal-api/` foi trazido para a `main` local a partir da referência sintética auditada e agora contém a camada de integração consumida pelo `portal-web`:

| Arquivo | Alteração |
|---|---|
| `portal-api/src/app.js` | Rotas autorizadas de subjects, metas ESDM, coletas escolares e validação do dicionário de códigos/níveis. |
| `portal-api/src/store.js` | Store com adaptador PostgreSQL (`pg`) para `esdm_goals` e `school_collections`; memória permanece apenas como modo explícito de teste sem `DATABASE_URL`. |
| `portal-api/src/server.js` | CORS restrito ao frontend local, preflight `OPTIONS` e tratamento de JSON inválido. |
| `portal-api/migrations/001_initial.sql` | Tabelas, checks e índices de metas e coletas ligados a `child_subjects` e `users`. |
| `portal-api/package.json` | `pg` promovido para dependência de runtime. |

Contrato integrado:

```text
GET  /v1/organizations/{organizationId}/subjects
GET  /v1/subjects/{subjectId}/esdm-goals
POST /v1/subjects/{subjectId}/esdm-goals
GET  /v1/subjects/{subjectId}/school-collections
POST /v1/subjects/{subjectId}/school-collections
```

As rotas revalidam identidade sintética, membership, consentimento, validade e escopo (`esdm_goal.read`, `esdm_goal.write`, `school_collection.read` e `school_collection.write`) antes de ler ou gravar. O cliente deixou de importar fixtures de pacientes, metas e coletas: `APIClient` usa `fetch`, envia `x-synthetic-user-id`/`x-request-id` e exibe estados de carregamento e erro.

### Evidências e limite desta integração

`npm test` do `portal-api` passou com 17 testes e 1 teste PostgreSQL pulado por ausência de banco configurado. O teste de endpoints HTTP confirmou preflight CORS, listagem de subjects, criação de meta, leitura de coletas e bloqueio do outsider. `npm run check` do `portal-web` e `git diff --check` também passaram.

Nesta sandbox, `DATABASE_URL` não está configurada; portanto, a execução local usa `storageMode: memory-test-only` para os testes sintéticos. O caminho PostgreSQL está implementado e será ativado somente após aplicar a migration e iniciar o backend com `DATABASE_URL`. Não declarar persistência real validada até executar o teste de integração contra um banco de staging.

### Limites e decisão de integração

Nenhum código dessas branches foi mesclado na `main` local durante esta auditoria. A prévia `site/portal.html` pode servir como referência visual, mas não deve ser tratada como portal autenticado. A primeira implementação funcional deve ocorrer em branch própria, com dados sintéticos, sem alterar o fluxo local-first do app Flutter e sem trocar o CTA público do site até que login, autorização, consentimento, auditoria, revogação e restauração estejam validados.

## Próximo passo recomendado — API de sincronização remota “Cuidado Conectado”

Desenvolver a sincronização somente após fechar o contrato de autorização server-side. A primeira versão deve seguir estes princípios:

### 1. Identidade e autorização

- autenticação por usuário/organização, nunca por um ID local confiável;
- convite explícito do responsável para escola ou clínica;
- token de curta duração, revogável e vinculado a `perfilAlvo`, organização e escopos;
- validação server-side de cada leitura e escrita;
- nenhuma permissão remota deve ser inferida apenas do switch local.

### 2. Escopos mínimos

Representar escopos separados, por exemplo:

```text
routine.read
school_collection.write
abc_report.read
esdm_goal.write
esdm_goal.read
```

Cada concessão deve carregar `subjectId`, `targetOrganizationId`, `scopes`, `issuedAt`, `expiresAt`, `revokedAt` e `consentVersion`.

### 3. Endpoints iniciais sugeridos

```text
POST   /v1/care-connections/invitations
POST   /v1/care-connections/invitations/{id}/accept
GET    /v1/care-connections
POST   /v1/care-connections/{id}/revoke
POST   /v1/sync/push
GET    /v1/sync/pull?cursor=...
GET    /v1/audit-events
```

O payload de sincronização deve ser versionado, idempotente e conter `deviceId`, `entityType`, `entityId`, `operation`, `payload`, `clientUpdatedAt`, `baseVersion` e `idempotencyKey`.

### 4. Offline-first e conflitos

- manter a operação local mesmo sem rede;
- fila cifrada de eventos pendentes;
- retry com backoff;
- cursor de sincronização por dispositivo;
- resolução explícita de conflito por versão, sem sobrescrever silenciosamente uma meta ou coleta;
- deduplicação por `idempotencyKey`;
- confirmação de revogação antes de enviar novos dados.

### 5. Privacidade, auditoria e retenção

- TLS obrigatório e secrets fora do repositório;
- criptografia em repouso no servidor;
- logs de concessão, leitura, escrita e revogação sem armazenar conteúdo desnecessário;
- retenção configurável por organização e finalidade;
- exportação e exclusão auditáveis;
- contrato claro de controlador/processador de dados;
- testes negativos para cross-tenant, token expirado, escopo insuficiente e concessão revogada.

### 6. Plano de entrega

1. fechar OpenAPI e modelo de dados;
2. implementar autorização e isolamento de organização;
3. criar testes de contrato e negativos;
4. implementar fila local e sync incremental;
5. adicionar indicador de estado “local / pendente / sincronizado / erro”;
6. executar piloto controlado antes de habilitar qualquer sincronização em produção.
