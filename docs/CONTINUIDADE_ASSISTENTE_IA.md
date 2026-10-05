

## Atualização — 04/10/2026 — persistência PostgreSQL de staging preparada

O store do `portal-api` foi ajustado para inicializar um `pg.Pool` quando `DATABASE_URL` estiver definida, usando configuração de conexões, timeouts e TLS opcional. As operações `saveGoal`, `getGoalsBySubject`, `saveCollection` e `getCollectionsBySubject` usam SQL parametrizado nas tabelas da migration. O novo `portal-api/.env.example` documenta `PORT`, `DATABASE_URL`, `NODE_ENV` e ajustes do pool; o README inclui o comando de aplicação da migration e carregamento do `.env`.

A validação local passou com 17 testes e um teste PostgreSQL ignorado por ausência de banco. Foi validada também uma chamada com pool mock para confirmar query parametrizada. Nenhum `DATABASE_URL` real foi usado e nenhuma migration foi aplicada em staging nesta etapa.
