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
