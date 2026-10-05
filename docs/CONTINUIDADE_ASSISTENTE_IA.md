

## Atualização — 05/10/2026 — integração visual ponta a ponta

O frontend modular deixou de depender de respostas estáticas: `portal-web/src/api/client.js` concentra as chamadas `fetch` reais e envia identidade sintética, request id e JSON quando necessário. `clinica_screen.js` carrega subjects e metas, permite POST de meta e recarrega a tabela; `escola_screen.js` carrega coletas e recalcula os cards/resumo semanal. Ambas as telas explicitam loading, sucesso, vazio e erro de API/rede.

Foi adicionada a suíte `portal-web/test/client.test.js` e o script `npm test`. Os três testes passaram, cobrindo URLs parametrizadas, headers, POST de meta e erro `SCOPE_DENIED`. `npm run check` também passou. Os endpoints `/subjects`, `/esdm-goals` e `/school-collections` responderam por HTTP durante o smoke test, e o handoff registra que a revisão visual completa no navegador permanece como próximo gate.
