
## Atualização — 05/10/2026 — validação PostgreSQL efêmera concluída

Docker e `psql` não estavam disponíveis inicialmente; foi instalado PostgreSQL 16 localmente apenas para esta validação. O cluster `16/main` foi iniciado, o banco `fala_comigo_staging` foi criado com a URL documentada, a migration `portal-api/migrations/001_initial.sql` foi aplicada sem erros e foram inseridas somente fixtures sintéticas mínimas para satisfazer as chaves estrangeiras.

Com `DATABASE_URL` e `PGTEST_URL` apontando para `postgres://postgres:postgres@localhost:5432/fala_comigo_staging`, `npm run test:db` passou em modo `postgres`, `npm test` passou com 18/18 testes e sem skips, e um round-trip real confirmou INSERT/SELECT de `esdm_goals` e `school_collections` via `pg.Pool`. O banco foi removido e o cluster foi parado ao final; nenhuma instância persistente ficou ativa. A alteração do teste de migration inclui agora as tabelas funcionais.
