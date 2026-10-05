

## Encerramento da sessão — 05/10/2026 — estado consolidado

### PostgreSQL e portal-api

- `portal-api/src/store.js` usa `pg.Pool` quando `DATABASE_URL` está definida, com `PGPOOL_MAX`, timeouts de conexão/ociosidade e TLS opcional via `PGSSLMODE=require`.
- `saveGoal`, `getGoalsBySubject`, `saveCollection` e `getCollectionsBySubject` executam queries SQL parametrizadas contra `esdm_goals` e `school_collections`; aliases antigos permanecem para compatibilidade.
- `portal-api/scripts/test-db-connection.js` executa `SELECT 1 + 1 AS result` e retorna exit code explícito.
- A migration PostgreSQL foi aplicada em uma instância local efêmera; `npm run test:db`, `npm test` e round-trip real de metas/coletas passaram. O teste de integração passou com 18/18, sem skips.
- O banco efêmero e o cluster foram removidos/parados após a validação. Nenhuma instância PostgreSQL persistente ou credencial real ficou configurada.

### Portal-web

- `portal-web/src/api/client.js` usa `fetch` real para subjects, metas ESDM e coletas escolares, sem fixtures nas telas.
- As telas de clínica e escola tratam loading, sucesso, estado vazio e erro HTTP/rede.
- `portal-web/test/client.test.js` cobre URLs parametrizadas, headers, POST JSON e `SCOPE_DENIED`; os 3 testes e o check de sintaxe passaram.
- A revisão visual completa em navegador continua sendo um gate separado.

### Fila offline mobile

- Criados `SyncItem` e `SyncQueueAdapter` TypeId 14 em `lib/features/esdm_aba/domain/models/`.
- Criados `SyncQueueStore` e `SyncQueueService`; a box `sync_queue_box` usa `SecureBoxService`, chave de 32 bytes no `flutter_secure_storage` e `HiveAesCipher`.
- A `ColetaEscolaController` sempre salva localmente. Com concessão escolar vigente, tenta POST real para `/v1/subjects/{subjectId}/school-collections`; offline, timeout ou falha preserva o item na fila.
- `connectivity_plus` dispara sincronização no retorno da rede e há fallback periódico de um minuto. Itens são processados sequencialmente, `attempts` é incrementado em falhas e a remoção ocorre somente em HTTP 200/201.
- Concessão expirada/revogada bloqueia o envio. O bootstrap registra o adapter e inicia o monitor; `DataWipeService` inclui `sync_queue_box` no apagamento seguro.
- Configuração de staging sintético: `--dart-define=PORTAL_API_BASE_URL=...`, `--dart-define=PORTAL_SUBJECT_ID=...` e `--dart-define=PORTAL_USER_ID=...`. O header `x-synthetic-user-id` não é autenticação de produção.

### Onde o trabalho parou

Todos os arquivos foram implementados e estão prontos para o commit desta sessão. A validação estática e `git diff --check` passaram; Flutter/Dart não estão instalados nesta sandbox, então `flutter analyze` e `flutter test` precisam ser executados no CI ou em uma máquina com a toolchain Flutter.

### Próximo passo exato

Executar o pipeline Flutter com `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze` e `flutter test`. Em seguida, configurar identidade real/OAuth no mobile e no portal-api, substituir o header sintético e executar um teste de staging com `DATABASE_URL`, `PORTAL_API_BASE_URL`, `PORTAL_SUBJECT_ID` e concessão escolar real antes de qualquer release.

## Consolidação da toolchain mobile — 05/10/2026

A validação da raiz mobile usou Flutter stable **3.47.6** e Dart **3.13.5**. O `flutter pub get` concluiu com as dependências de `connectivity_plus` e `http` resolvidas; o `flutter pub run build_runner build --delete-conflicting-outputs` concluiu sem conflitos e gerou o adapter `SyncQueueAdapter` TypeId 14 em `sync_item.g.dart`; `flutter analyze` concluiu com `No issues found!`; e `flutter test` concluiu com **114 testes passando**.

A consolidação foi publicada na `main` em `788212c`, com a mensagem `feat(mobile): compile build_runner artifacts and clean sync queue types`.
