# Preparação do beta real — Fala Comigo

## Estado desta branch

Branch: `work/beta-real-autotest-20261010`.

A preparação adicionou:

- `/v1/beta/status` como autoridade de data do backend;
- ciclo configurável por `BETA_START_AT` e `BETA_DURATION_DAYS`;
- fallback offline no Web/mobile usando última expiração confiável;
- bloqueio por retrocesso do relógio local acima de cinco minutos;
- tela de bloqueio beta expirada no Web e no mobile;
- telemetria allowlistada: `screen_view`, `beta_expired`, `sync_success`, `sync_failed`;
- nenhum texto de input, e-mail, senha, conteúdo clínico, token ou identificador de sujeito é incluído na telemetria;
- autotestes Web, API e Flutter para expiração, fraude de relógio e sanitização.

## Ambiente temporário desta validação

- Portal Web: <https://4173-iwml1q49qdwfbaa8u5diz-9485012c.us1.manus.computer>
- API beta: <https://8787-iwml1q49qdwfbaa8u5diz-9485012c.us1.manus.computer>
- Início configurado: `2026-10-10T00:00:00.000Z`
- Expiração configurada: `2026-11-09T00:00:00.000Z`

Essas URLs são **temporárias do sandbox**, não um ambiente de produção ou staging persistente. A API utiliza fixtures em memória e não deve receber dados reais.

## APK beta configurado

Artefato: `build/app/outputs/flutter-apk/app-release.apk`

O APK foi compilado com:

```bash
flutter build apk --release --no-shrink \
  --dart-define=PORTAL_API_BASE_URL=https://8787-iwml1q49qdwfbaa8u5diz-9485012c.us1.manus.computer \
  --dart-define=BETA_START_AT=2026-10-10T00:00:00.000Z \
  --dart-define=BETA_DURATION_DAYS=30
```

SHA-256 do artefato desta execução:

```text
3feae460783705419bd949ba063253603d0b9aec94bf515714fe3d4b8e6f64dd
```

A assinatura é **efêmera de beta**, válida para teste controlado. Não é a keystore produtiva e não deve ser usada para publicação.

## Validação executada

- Portal Web: `npm run check` e `npm test` — **28 aprovados**.
- Portal API: `npm test` — **55 aprovados, 1 teste PostgreSQL condicionalmente pulado** por indisponibilidade de `PGTEST_URL`.
- Flutter: `dart format`, `flutter analyze` e `flutter test` — **136 aprovados**.
- Flutter Web release — aprovado.
- APK release beta — aprovado; `apksigner` confirmou assinatura v2.
- MobSF local — não executado: Docker indisponível nesta sandbox.

## Gates antes de dados reais/publicação

1. API de staging persistente com PostgreSQL e autorização completa, sem fixtures em memória.
2. Keystore produtiva fornecida pelo responsável e build release assinado com segredo fora do Git.
3. MobSF executado no CI ou em ambiente Docker habilitado; resolver findings críticos/altos.
4. Migração/reprocessamento formal de chaves E2EE legadas, com backup e recuperação testados.
5. HTTPS, rate limiting, logs sem dados sensíveis e política de retenção da telemetria.
6. Teste em aparelhos físicos Android/tablet e validação de acessibilidade/responsividade.
7. Somente após os gates acima, abrir PR de integração na `main`.

## Atualização de execução — persistência de autorização — 10/10/2026
A branch `work/real-beta-persistence-20261010` iniciou a conversão do portal de fixtures para persistência real. A migration `portal-api/migrations/006_membership_scopes.sql` adiciona escopos explícitos por vínculo. Em servidor com `DATABASE_URL` e `NODE_ENV` diferente de `test`, a API hidrata o estado de autorização do PostgreSQL e faz flush transacional após cada requisição. A suíte unitária permanece sintética somente no modo `NODE_ENV=test`.

Ainda bloqueiam o uso com a equipe: execução do teste PostgreSQL no CI/staging, revisão de concorrência e idempotência multi-instância, URL HTTPS estável, secrets reais cadastrados no provedor, identidade real, keystore de release, MobSF e testes físicos. O APK e o portal não devem ser apontados para dados reais até esses gates serem evidenciados.

## Hardening PR #5 — 10/10/2026
A revisão avançada corrigiu a exposição potencial de escopos: consultas de login e refresh agora carregam `m.scopes`, e a lista explícita sempre restringe o papel. Requisições concorrentes são serializadas no ciclo completo de autorização. O flush PostgreSQL opera somente em registros alterados desde o snapshot da requisição, com transação omitida para leituras sem delta. Falhas de persistência retornam `503 PERSISTENCE_UNAVAILABLE`.

Validação local: 58 testes aprovados, análise de sintaxe, audit de dependências sem vulnerabilidades e diff limpo. O uso real permanece bloqueado até os gates de infraestrutura e dispositivo descritos anteriormente.
