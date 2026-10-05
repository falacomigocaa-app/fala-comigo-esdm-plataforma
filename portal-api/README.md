# API local do Portal Cuidado Conectado

Esta pasta contém a implementação local do portal com identidade sintética para desenvolvimento. Ela testa autorização, isolamento entre organizações, sujeito infantil, consentimento, convites, grants, revogação, benefícios, auditoria, idempotência, metas ESDM e coletas escolares sem criar contas externas ou conectar um provedor real.

## Executar

Requer Node.js 22 ou superior:

```bash
cd portal-api
npm install
npm test
npm start
```

O servidor local inicia em `http://127.0.0.1:8787`. A identidade de desenvolvimento é informada pelo header sintético `x-synthetic-user-id`, por exemplo:

```bash
curl -H 'x-synthetic-user-id: user-professional-alpha' \
  http://127.0.0.1:8787/v1/organizations/org-demo-alpha/subjects
```

Para ativar persistência PostgreSQL, aplique `migrations/001_initial.sql` em um banco de staging e inicie com `DATABASE_URL`:

```bash
cp .env.example .env
# Edite .env e substitua DATABASE_URL pelos dados do seu container/servidor de staging.
set -a
. ./.env
set +a
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial.sql
npm start
```

O `store.js` cria um `pg.Pool` estável quando `DATABASE_URL` está presente. O pool usa `PGPOOL_MAX`, timeouts de conexão/ociosidade e, opcionalmente, TLS com `PGSSLMODE=require`. As escritas e leituras de metas/coletas usam queries parametrizadas contra `esdm_goals` e `school_collections`.

Sem `DATABASE_URL`, metas e coletas usam `memory-test-only` somente para testes sintéticos e são descartadas ao reiniciar. Não declarar persistência de staging validada sem executar a migration e o teste de integração contra o banco.

## Contratos integrados

```text
GET  /v1/organizations/{organizationId}/subjects
GET  /v1/subjects/{subjectId}/esdm-goals
POST /v1/subjects/{subjectId}/esdm-goals
GET  /v1/subjects/{subjectId}/school-collections
POST /v1/subjects/{subjectId}/school-collections
```

As rotas de metas validam os códigos `CE_N1_I5`, `CE_N1_I6` e `SOC_N1_I3`, retornando `missaoPais` e `dicaPratica`. As rotas escolares validam os blocos `Lanche`, `Recreio`, `Roda de Conversa` e `Atividade Sentada`, além dos níveis `Independente`, `Ajuda Verbal`, `Ajuda Física` e `Recusa`.

Antes de qualquer leitura ou escrita, o backend valida membership, consentimento ativo, data de expiração e escopo (`esdm_goal.read`, `esdm_goal.write`, `school_collection.read` ou `school_collection.write`). O CORS local permite o frontend em `http://127.0.0.1:4173` e pode ser ajustado por `PORTAL_WEB_ORIGIN`.

## Conteúdo

- `src/store.js`: dicionário ESDM, fixtures de autorização para testes, `pg.Pool` e queries parametrizadas das tabelas funcionais;
- `src/authorization.js`: autenticação sintética, membership, escopos, erros estáveis e auditoria;
- `src/app.js`: rotas `/v1`, autorização, contratos e idempotência;
- `src/server.js`: adaptador HTTP local, CORS e parsing JSON;
- `migrations/001_initial.sql`: schema de identidade, organização, sujeito, consentimento, autorização, metas e coletas;
- `test/authorization.test.js`: casos permitidos e negados;
- `test/postgres.integration.test.js`: verificação do schema quando `PGTEST_URL` está definido.
- `.env.example`: variáveis documentais para iniciar o servidor conectado ao PostgreSQL de staging.

## Limites

O header sintético e o servidor atual são somente para desenvolvimento local. Ainda não há login real, OAuth, sessão de produção ou banco remoto configurado nesta sandbox. O próximo gate é trocar o adaptador de identidade e executar a integração PostgreSQL em staging, mantendo as decisões server-side de organização, sujeito, finalidade, escopo, consentimento e prazo.

Não adicionar senhas, tokens, nomes reais, dados de crianças, conteúdo clínico, fotos, vídeos, áudios ou credenciais a esta pasta.
