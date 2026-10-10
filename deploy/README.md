# Executar e publicar

Use Node24, Flutter3.47.6/Dart3.13.5 e PostgreSQL16. O kit foi exercitado localmente; domínios, TLS público e aparelho real têm gates próprios em `docs/PRONTIDAO_PRODUCAO.md`.

## Preparação privada

Copie `.env.example` para `.env` (ignorado pelo Git), com permissão600. Use valores próprios e aleatórios. `DATABASE_URL` deve apontar `postgres://fala_comigo:<senha-percent-encoded>@db:5432/fala_comigo`; a senha deve corresponder a `POSTGRES_PASSWORD`. `JWT_SECRET` requer32+ caracteres; `MASTER_CRYPTO_KEY` deve ser uma chave aleatória de32 bytes codificada em base64. Guarde cópias protegidas dos segredos: perder a chave mestra impede recuperar as chaves de organização.

Preencha três hostnames com DNS para o servidor: site, portal e API. Somente Caddy expõe80/443; banco/API ficam na rede privada. Se usar PostgreSQL externo, adapte conscientemente a composição e configure TLS validado (`PGSSLMODE=require`) e a CA do provedor. Nunca desative validação de certificado.

## Instalação (na raiz do repositório)

```bash
flutter pub get --enforce-lockfile
flutter build web --release --base-href /app/ \
  --dart-define=PORTAL_API_BASE_URL=https://SEU_HOST_DA_API

docker compose --env-file deploy/.env -f deploy/compose.yml build
docker compose --env-file deploy/.env -f deploy/compose.yml up -d db
docker compose --env-file deploy/.env -f deploy/compose.yml run --rm api node scripts/migrate.js
```

`SEU_HOST_DA_API` é um placeholder; substitua antes de compilar. Os binários locais desta tarefa usam loopback para validação e precisam ser recompilados para uma API pública.

Crie a primeira conta com `scripts/provision-admin.js`. Forneça `ADMIN_EMAIL`, `ADMIN_PASSWORD` (16+ caracteres), `ORGANIZATION_ID` e `ORGANIZATION_NAME` por variáveis privadas do processo. O container já recebe banco e chave mestra da composição:

```bash
docker compose --env-file deploy/.env -f deploy/compose.yml run --rm \
  -e ADMIN_EMAIL -e ADMIN_PASSWORD -e ORGANIZATION_ID -e ORGANIZATION_NAME \
  api node scripts/provision-admin.js

docker compose --env-file deploy/.env -f deploy/compose.yml up -d api portal edge
```

Não cole senha em comandos compartilhados/histórico. O bootstrap recusa sobrescrever uma conta. Não execute `seed-demo.js` em produção. Migrations são ordenadas e têm ledger/checksum; não edite migrations já aplicadas.

## Uso conectado

1. Entre no portal com a conta provisionada; Equipe cria convites por email.
2. Selecione somente permissões necessárias. Ler/enviar coletas cifradas requer permissão de chave. O papel sozinho não concede acesso a pacientes.
3. Copie o link pessoal de ativação e entregue ao destinatário por canal privado. O link dura7 dias; gerar outro invalida o anterior. Não existe envio automático de email.
4. O destinatário define a própria senha. Nunca peça que ele entregue essa senha ao administrador.
5. O responsável legal cadastra a pessoa e, em Pacientes e acessos, escolhe profissional, finalidade, prazo e permissões. Pode revogar a qualquer momento.
6. Clínica registra metas; Escola registra coletas; Relatórios reúne dados autorizados. O aplicativo escolhe o paciente após login; a CAA básica continua sem conta.
7. Minha conta permite alterar senha. A alteração invalida refresh tokens anteriores; access tokens já emitidos expiram em até15 minutos. Recuperação de senha esquecida requer suporte com verificação de identidade; não existe email automático de recuperação.

## Android

Use a keystore/upload key definitiva em `android/key.properties`, fora do Git. Não use chave temporária de CI na loja. Depois de definir `versionCode`/`versionName` e a URL real:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=PORTAL_API_BASE_URL=https://SEU_HOST_DA_API
flutter build appbundle --release \
  --dart-define=PORTAL_API_BASE_URL=https://SEU_HOST_DA_API
```

Verifique assinatura com `apksigner verify`/`jarsigner -verify`. AAB é pacote de envio à Play Console, não arquivo instalável diretamente. Teste APK em instalação limpa e em atualização sobre a versão anterior; confira dados, permissões, fala, mídia, notificações e modo avião.

## Operação e backup

- Verifique `/health` e login/consulta sintética após cada implantação; observe logs sem corpos clínicos/tokens.
- Faça `pg_dump -Fc` do banco, com saída em local privado e armazenamento externo cifrado sob sua gestão. Backup do banco não substitui cópia protegida da chave mestra/keystore.
- Teste restauração com `createdb <banco-novo>` e `pg_restore --no-owner --dbname <banco-novo> <dump>`, nunca sobre produção como teste.
- Defina retenção de dados, agenda de backup, responsável por alertas e recuperação antes de admitir dados reais.
- Limitação atual: o limitador HTTP usa IP da conexão e memória do processo. Atrás do proxy, os usuários compartilham o limite; implantações maiores precisam de política para proxy confiável e armazenamento compartilhado antes de escalar.
- O host Web precisa de HTTPS; mídia privada e notificações ainda têm limitações registradas no app. Não remover esses avisos para simular paridade.

## Gates locais

```bash
npm ci --prefix portal-api
npm test --prefix portal-api
npm test --prefix portal-web
npm run check --prefix portal-web
node --test tests/*.test.mjs
flutter analyze --no-pub
flutter test --no-pub
```

Para integrar testes PostgreSQL, use somente banco descartável local com migrations e `seed-demo.js` (`ALLOW_DEMO_SEED=1`), chaves sintéticas, `DATABASE_URL` e `PGTEST_URL`. A suíte altera fixtures de teste. Não aponte para produção.
