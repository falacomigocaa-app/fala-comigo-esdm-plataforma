

## Atualização — 04/10/2026 — integração do portal-api com portal-web

O `portal-api/` foi incorporado localmente à `main` e o frontend `portal-web` deixou de usar fixtures de pacientes, metas e coletas. O cliente `APIClient` agora chama `GET /v1/organizations/{organizationId}/subjects`, `GET/POST /v1/subjects/{subjectId}/esdm-goals` e `GET/POST /v1/subjects/{subjectId}/school-collections`, enviando identidade sintética e request id.

O backend valida membership, consentimento, expiração e escopos antes da leitura/escrita. O store implementa persistência PostgreSQL via `pg`, e a migration criou `esdm_goals` e `school_collections` com referências, checks e índices. O ambiente atual não possui `DATABASE_URL`; por isso, os testes executam o modo `memory-test-only`, sem afirmar persistência de staging. `npm test` passou com 17 casos e um caso PostgreSQL pulado; os endpoints HTTP, CORS e bloqueio do outsider foram validados.
