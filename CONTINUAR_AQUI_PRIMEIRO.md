
## Atualização — 04/10/2026 — Pool PostgreSQL de staging documentado

O `portal-api/src/store.js` agora cria um `pg.Pool` configurável quando `DATABASE_URL` está presente, com limite, timeouts, TLS opcional via `PGSSLMODE=require` e tratamento de erro do pool. Os métodos explícitos `saveGoal`, `getGoalsBySubject`, `saveCollection` e `getCollectionsBySubject` executam queries parametrizadas nas tabelas `esdm_goals` e `school_collections`; aliases antigos foram preservados para compatibilidade. Foi criado `portal-api/.env.example` e o README documenta aplicação da migration e carregamento do ambiente. Sem `DATABASE_URL`, os testes continuam no modo `memory-test-only`; nenhum banco real foi conectado nesta etapa.
