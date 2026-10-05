
## Atualização — 05/10/2026 — portal-web consumindo API real

A camada visual do `portal-web` foi auditada e confirmada sem fixtures de pacientes, metas ou coletas. `APIClient` usa `fetch` real para `GET /v1/organizations/{organizationId}/subjects`, `GET/POST /v1/subjects/{subjectId}/esdm-goals` e `GET/POST /v1/subjects/{subjectId}/school-collections`, enviando `x-synthetic-user-id` e `x-request-id`; os escopos continuam sendo decididos e verificados server-side pelo portal-api.

As telas clínica e escola agora têm render inicial de loading, hidratação assíncrona, atualização de sucesso, estado vazio e mensagens de erro HTTP/rede. Foi criada a suíte `portal-web/test/client.test.js`, com três testes para headers/URLs, POST JSON de meta e propagação de `SCOPE_DENIED`. `npm run check` e `npm test` do portal-web passaram; os endpoints reais também responderam por HTTP para pacientes, metas e coletas. A validação visual em navegador completo continua sendo um gate separado.
