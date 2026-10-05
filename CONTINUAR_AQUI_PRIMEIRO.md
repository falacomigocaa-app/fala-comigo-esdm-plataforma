
## Encerramento da sessão — 05/10/2026 — handoff operacional

O portal-api ficou com Pool PostgreSQL condicional por `DATABASE_URL`, queries parametrizadas de metas/coletas e script `npm run test:db`. A migration foi aplicada em PostgreSQL local efêmero; `npm run test:db`, `npm test` com 18/18 e o round-trip real de `saveGoal/getGoalsBySubject` e `saveCollection/getCollectionsBySubject` passaram. O banco e o cluster foram removidos ao final.

No mobile, a fila criptografada `sync_queue_box` usa `SyncItem`, `SyncQueueAdapter` TypeId 14, `SyncQueueStore`, `SyncQueueService`, `connectivity_plus`, `http`, `HiveAesCipher` e chave de 32 bytes no `flutter_secure_storage`. A coleta é salva localmente; com concessão vigente tenta POST real, e offline/timeout/falha mantém o payload com `attempts` para retry. O bootstrap inicia o monitor e o `DataWipeService` remove a fila. Os três `--dart-define` necessários são `PORTAL_API_BASE_URL`, `PORTAL_SUBJECT_ID` e `PORTAL_USER_ID`; o último ainda representa identidade sintética do staging.

Esta sessão termina após o commit e push deste escopo. O próximo passo exato para a próxima agente é executar `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze` e `flutter test` em ambiente com Flutter/Dart, corrigir qualquer incompatibilidade de versões e só então validar a identidade real/OAuth e o POST em staging.

## Consolidação dos artefatos — 05/10/2026

A toolchain Flutter stable 3.47.6 (Dart 3.13.5) foi provisionada e executada na raiz mobile. `flutter pub get` concluiu; `flutter pub run build_runner build --delete-conflicting-outputs` terminou sem conflitos e gerou os adapters, incluindo `SyncQueueAdapter` TypeId 14 em `sync_item.g.dart`; `flutter analyze` terminou com `No issues found!`; e `flutter test` passou com 114 testes.

Os artefatos gerados, ajustes estáticos e dependências foram consolidados e publicados na branch `main` no commit `788212c` (`feat(mobile): compile build_runner artifacts and clean sync queue types`).

## Segurança JWT no portal-api — 05/10/2026

O backend agora emite e valida tokens JWT com `jsonwebtoken`, `JWT_SECRET` obrigatório (mínimo de 32 caracteres), payload com `userId`, `organizationId` e `scopes`, e expiração padrão rígida de 15 minutos. O middleware Bearer substituiu o header `x-synthetic-user-id`; tokens ausentes/corrompidos retornam 401 e tokens expirados retornam `TOKEN_EXPIRED` com `renewalRequired: true`. A suíte `npm test` passou com 21 testes, 1 teste PostgreSQL opcional ignorado.

## Integração JWT web/mobile — 05/10/2026

O `portal-web` agora persiste o token na sessão local, envia `Authorization: Bearer` nas chamadas de metas/coletas e limpa a sessão/sinaliza login em respostas 401. O mobile usa `AuthTokenService` com `flutter_secure_storage`; a fila envia o Bearer ativo, mantém o payload em 401 e interrompe o processamento para reautenticação. Validação final: backend 21 testes aprovados e 1 PostgreSQL condicional ignorado; web 4 testes aprovados e check sintático; Flutter analyze sem issues e 114 testes aprovados.

## Relatórios visuais no portal-web — 05/10/2026

Após o push bem-sucedido da integração JWT, o desenvolvimento avança para a camada visual de relatórios clínicos. O próximo escopo é compilar coletas escolares e metas ESDM/ABA por indivíduo no portal-web, com filtros temporais, estados assíncronos e base de impressão/exportação.

## Sincronização de metas mobile — 05/10/2026

O aplicativo agora baixa metas ativas de `/v1/subjects/{subjectId}/esdm-goals` com JWT Bearer, valida a resposta antes de alterar o cache e persiste os dados na box Hive criptografada `esdm_goals_box`. A coleta carrega primeiro as metas locais e sincroniza em background; o seletor funciona offline e a meta selecionada acompanha o payload local. `dart run build_runner build --delete-conflicting-outputs` concluiu com 20 outputs, `flutter analyze` não encontrou issues e `flutter test` passou com 114 testes.
