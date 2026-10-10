
## Correção do novo cartão pela câmera — 10/10/2026

Corrigido o fluxo de criação de cartão personalizado pela câmera. A causa era o `didChangeAppLifecycleState` do `main.dart`: a pausa temporária causada pela Activity da câmera era interpretada como saída da Área Parental, bloqueando a sessão e reabrindo o PIN no retorno. `ParentalSessionService` agora marca atividades externas temporárias; o ciclo de vida não bloqueia a sessão durante câmera/seletor, mas mantém o bloqueio normal quando o app realmente vai para segundo plano. O rascunho e a recuperação do `image_picker` continuam ativos.

Validação: `flutter analyze` sem issues, teste focado da sessão parental passou com 5 testes e suíte Flutter passou com 137 testes. APK debug atualizado gerado com a API beta configurada: `build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `423a4211f79fa62c92b71500e65d3483a520746949ff55ae09499e5379434663`. Aviso existente não bloqueador do Flutter sobre migração futura para Built-in Kotlin/KGP permanece.

## Persistência do beta real — início — 10/10/2026
A branch `work/real-beta-persistence-20261010` foi criada sobre a `origin/main` no merge `24c148c`. Foi adicionada a migration `portal-api/migrations/006_membership_scopes.sql`, o modo servidor passou a hidratar users, organizations, memberships, subjects, consents, invitations, relationships, grants, benefits e audit events do PostgreSQL e a persistir alterações de autorização em transação ao final de cada requisição. `NODE_ENV=test` mantém fixtures isoladas para a suíte unitária.

Validação local: `npm test` da API passou com 55 aprovados e 2 testes PostgreSQL condicionados sem `PGTEST_URL`; `node --check` de `store.js`/`app.js` e `git diff --check` passaram. Foi adicionado teste de integração que comprova status de membership após recriar o store quando `PGTEST_URL` estiver disponível. Limitação: a integração PostgreSQL ainda precisa passar no CI com a migration 006; o ambiente real, HTTPS, provedor de identidade, keystore, MobSF e teste físico ainda não estão configurados.
