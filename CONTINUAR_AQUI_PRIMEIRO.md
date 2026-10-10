
## Preparação do beta real e auto-teste — 10/10/2026

Criada a branch `work/beta-real-autotest-20261010` a partir de `work/complete-audit-20261010`. Implementados status beta público no backend (`/v1/beta/status`), ciclo configurável de 30 dias, fallback offline com última expiração confiável e bloqueio por retrocesso de relógio acima de cinco minutos. Web e mobile exibem tela de bloqueio após expiração. A telemetria aceita somente `screen_view`, `beta_expired`, `sync_success` e `sync_failed`; a carga não inclui inputs, e-mails, senhas, tokens, conteúdo clínico ou identificadores de sujeito.

Auto-testes: portal-web 28 aprovados; portal-api 55 aprovados e 1 integração PostgreSQL condicionalmente pulada sem `PGTEST_URL`; Flutter 136 aprovados, analyzer limpo e formatter limpo. `flutter build web --release` passou. Foi gerado `build/app/outputs/flutter-apk/app-release.apk` apontando para a API temporária pública do sandbox, assinado com chave efêmera de beta e verificado pelo `apksigner` v2; SHA-256 `3feae460783705419bd949ba063253603d0b9aec94bf515714fe3d4b8e6f64dd`.

Limites explícitos: as URLs públicas são temporárias; o portal-api ainda usa fixtures de autorização em memória; a keystore produtiva não está disponível; Docker/MobSF não está disponível nesta sandbox; a migração de chaves E2EE legadas e validação em aparelho físico continuam pendentes. Por isso não abrir PR para a `main` nem declarar prontidão para dados reais/publicação. Runbook: `docs/BETA_REAL_EXECUCAO.md`.
