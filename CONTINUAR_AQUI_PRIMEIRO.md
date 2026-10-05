
## Encerramento da sessão — 05/10/2026 — handoff operacional

O portal-api ficou com Pool PostgreSQL condicional por `DATABASE_URL`, queries parametrizadas de metas/coletas e script `npm run test:db`. A migration foi aplicada em PostgreSQL local efêmero; `npm run test:db`, `npm test` com 18/18 e o round-trip real de `saveGoal/getGoalsBySubject` e `saveCollection/getCollectionsBySubject` passaram. O banco e o cluster foram removidos ao final.

No mobile, a fila criptografada `sync_queue_box` usa `SyncItem`, `SyncQueueAdapter` TypeId 14, `SyncQueueStore`, `SyncQueueService`, `connectivity_plus`, `http`, `HiveAesCipher` e chave de 32 bytes no `flutter_secure_storage`. A coleta é salva localmente; com concessão vigente tenta POST real, e offline/timeout/falha mantém o payload com `attempts` para retry. O bootstrap inicia o monitor e o `DataWipeService` remove a fila. Os três `--dart-define` necessários são `PORTAL_API_BASE_URL`, `PORTAL_SUBJECT_ID` e `PORTAL_USER_ID`; o último ainda representa identidade sintética do staging.

Esta sessão termina após o commit e push deste escopo. O próximo passo exato para a próxima agente é executar `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`, `flutter analyze` e `flutter test` em ambiente com Flutter/Dart, corrigir qualquer incompatibilidade de versões e só então validar a identidade real/OAuth e o POST em staging.
