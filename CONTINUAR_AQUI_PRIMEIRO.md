
## Atualização — 04/10/2026 — integração portal-web/portal-api

A base `portal-api/` foi adicionada à `main` local a partir da referência sintética auditada. Foram implementadas as rotas `GET /v1/organizations/{organizationId}/subjects`, `GET/POST /v1/subjects/{subjectId}/esdm-goals` e `GET/POST /v1/subjects/{subjectId}/school-collections`, com validação de consentimento, validade e escopos. O frontend deixou de usar fixtures e passou a consumir `APIClient` via `fetch`.

O store usa `pg` e a migration agora cria `esdm_goals` e `school_collections`. Sem `DATABASE_URL`, a execução local permanece `memory-test-only` para testes sintéticos; a persistência PostgreSQL ainda precisa de banco de staging e aplicação da migration. `npm test` do backend passou com 17 testes e 1 integração PostgreSQL pulada; `npm run check` do frontend passou; os endpoints HTTP e o preflight CORS foram exercitados com sucesso. Nenhum commit, merge ou push foi executado.
