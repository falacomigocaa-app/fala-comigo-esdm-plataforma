

## Atualização — 05/10/2026 — PostgreSQL staging efêmero validado

Foi instalado PostgreSQL 16 localmente porque Docker e `psql` não estavam disponíveis. O cluster efêmero foi iniciado, o banco `fala_comigo_staging` foi criado com a URL do `.env.example`, a migration completa foi aplicada e fixtures sintéticas mínimas foram inseridas para satisfazer as foreign keys de `child_subjects` e `users`.

A execução com `DATABASE_URL` e `PGTEST_URL` confirmou: `npm run test:db` passou com `storageMode: postgres`; `npm test` passou com 18 testes, incluindo o teste PostgreSQL antes ignorado; e o round-trip real de `saveGoal/getGoalsBySubject` e `saveCollection/getCollectionsBySubject` passou contra as tabelas PostgreSQL. O teste de schema foi ampliado para verificar `esdm_goals` e `school_collections`. O banco foi apagado e o cluster parado depois da validação. Nenhuma credencial real ou dado de criança foi usado.
