# API local do Portal Cuidado Conectado

Esta pasta contém a implementação local do portal com autenticação JWT para desenvolvimento e staging. Ela testa autorização, isolamento entre organizações, sujeito infantil, consentimento, convites, grants, revogação, benefícios, auditoria, idempotência, metas ESDM e coletas escolares sem criar contas externas ou conectar um provedor real.

## Executar

Requer Node.js 22 ou superior:

```bash
cd portal-api
npm install
npm test
npm start
```

O servidor local inicia em `http://127.0.0.1:8787`. Configure `JWT_SECRET` com pelo menos 32 caracteres e envie um token emitido pelo serviço de autenticação no header padrão:

```bash
curl -H 'Authorization: Bearer <JWT>' \
  http://127.0.0.1:8787/v1/organizations/org-demo-alpha/subjects
```

Para ativar persistência PostgreSQL, aplique `migrations/001_initial.sql` até `migrations/006_membership_scopes.sql` em um banco de staging e inicie com `DATABASE_URL`:

```bash
cp .env.example .env
# Edite .env e substitua DATABASE_URL pelos dados do seu container/servidor de staging.
set -a
. ./.env
set +a
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_refresh_tokens.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/003_user_credentials.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_e2ee_school_collections.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/005_organization_keys.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/006_membership_scopes.sql
npm start
```

O `store.js` cria um `pg.Pool` estável quando `DATABASE_URL` está presente. O pool usa `PGPOOL_MAX`, timeouts de conexão/ociosidade e, opcionalmente, TLS com `PGSSLMODE=require`. Em modo de servidor, cada requisição hidrata autorização do PostgreSQL e persiste alterações de memberships, consentimentos, convites, relacionamentos, grants, benefícios e auditoria em transação.

Sem `DATABASE_URL`, metas e coletas usam `memory-test-only` somente para testes sintéticos e são descartadas ao reiniciar. Não declarar persistência de staging validada sem executar a migration e o teste de integração contra o banco.

## Contratos integrados

```text
POST /v1/auth/login
GET  /v1/organizations/{organizationId}/subjects
POST /v1/auth/refresh
GET  /v1/subjects/{subjectId}/esdm-goals
POST /v1/subjects/{subjectId}/esdm-goals
GET  /v1/subjects/{subjectId}/school-collections
POST /v1/subjects/{subjectId}/school-collections
```

As rotas de metas validam os códigos `CE_N1_I5`, `CE_N1_I6` e `SOC_N1_I3`, retornando `missaoPais` e `dicaPratica`. As rotas escolares validam os blocos `Lanche`, `Recreio`, `Roda de Conversa` e `Atividade Sentada`, além dos níveis `Independente`, `Ajuda Verbal`, `Ajuda Física` e `Recusa`.

`POST /v1/auth/refresh` recebe `{ "refreshToken": "..." }`, grava apenas o hash SHA-256 do token e retorna um novo `accessToken` de 15 minutos e um novo `refreshToken` de sete dias. O token anterior é revogado antes da nova emissão; replay, expiração ou token desconhecido retornam `401 REFRESH_TOKEN_INVALID`.

`POST /v1/auth/login` recebe `{ "email": "...", "password": "..." }`, verifica `password_hash` com bcrypt e retorna o mesmo par de tokens, além de `userId`, `organizationId` e `scopes`. Credenciais inválidas têm resposta uniforme `401 INVALID_CREDENTIALS`.

Antes de qualquer leitura ou escrita, o backend valida membership, consentimento ativo, data de expiração e escopo (`esdm_goal.read`, `esdm_goal.write`, `school_collection.read` ou `school_collection.write`). O CORS local permite o frontend em `http://127.0.0.1:4173` e pode ser ajustado por `PORTAL_WEB_ORIGIN`.

## Conteúdo

- `src/store.js`: dicionário ESDM, fixtures de autorização para testes, `pg.Pool` e queries parametrizadas das tabelas funcionais;
- `src/services/auth.service.js`: emissão e validação de JWT com expiração padrão de 15 minutos;
- `src/store.js`: verificação bcrypt e seleção de membership/escopos para login;
- `src/services/auth.service.js` e `src/store.js`: refresh tokens opacos hashados e rotação de uso único;
- `src/middlewares/auth.middleware.js`: extração do Bearer, validação de claims e erros 401 padronizados;
- `src/authorization.js`: membership, escopos, erros estáveis e auditoria;
- `src/app.js`: rotas `/v1`, autorização, contratos e idempotência;
- `src/server.js`: adaptador HTTP local, CORS e parsing JSON;
- `migrations/001_initial.sql`: schema de identidade, organização, sujeito, consentimento, autorização, metas e coletas;
- `migrations/002_refresh_tokens.sql`: armazenamento hashado e expirável de refresh tokens;
- `migrations/003_user_credentials.sql`: email e `password_hash` bcrypt na tabela de usuários;
- `migrations/006_membership_scopes.sql`: escopos explícitos persistidos por vínculo;
- `test/authorization.test.js`: casos permitidos e negados;
- `test/postgres.integration.test.js`: verificação do schema quando `PGTEST_URL` está definido.
- `.env.example`: variáveis documentais para iniciar o servidor conectado ao PostgreSQL de staging.

## Limites

O JWT e o servidor atual são destinados a desenvolvimento/staging. O login local usa bcrypt para o ciclo central de credenciais; antes de produção, deve ser conectado ao provedor de identidade corporativo e provisionado com hashes reais. Tokens expiram em 15 minutos por padrão, e o cliente renova a sessão com rotação ao receber `401` com `error: TOKEN_EXPIRED` e `renewalRequired: true`. O modo `NODE_ENV=test` mantém fixtures em memória para testes unitários; o servidor com `DATABASE_URL` hidrata e persiste autorização em PostgreSQL.

Não adicionar senhas, tokens, nomes reais, dados de crianças, conteúdo clínico, fotos, vídeos, áudios ou credenciais a esta pasta.

### Resultado da auditoria de 10/10/2026

Com `NODE_ENV=test`, a autorização continua baseada em fixtures em memória para manter os testes determinísticos. Em servidor, memberships, consentimentos, grants, convites, relacionamentos e auditoria são hidratados e persistidos por transação; ainda é obrigatório executar as migrations e validar reinício, backup, concorrência, identidade real e isolamento do provedor antes de inserir dados de crianças.

Login entrega chave somente com `organization.key.read`. Refresh revalida membership atual; histórico escolar filtra organização; idempotência é local ao processo e separada por usuário/organização/operação, com 409 para payload diferente. Convites limitam escopos ao papel e ao consentimento; escopo `report.read` ainda não é suportado. Detalhes e gates: [auditoria](../docs/auditoria/2026-10-10/README.md).
