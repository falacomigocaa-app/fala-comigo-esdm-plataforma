# Auditoria de prontidão do beta real — Fala Comigo

**Data:** 19/10/2026  
**Branch auditada:** `main`  
**Commit auditado:** `1000f67`  
**Conclusão global:** **BLOQUEADO para uso com dados clínicos reais e para declaração de “100% pronto”.**

## 1. Resumo executivo

A base do projeto está funcional em vários pontos: a API possui autenticação JWT/bcrypt, refresh token rotativo, autorização por escopos, convites, beta gate e persistência PostgreSQL; o portal web passa sua suíte; o Flutter passou a análise e testes quando executado no ambiente com Flutter; o Pages publicou com sucesso; e o projeto Supabase está saudável com RLS habilitado.

Entretanto, os gates decisivos de produção ainda não foram comprovados. Há falhas que podem impedir login/sincronização no APK release, risco de isolamento entre organizações, possibilidade de iniciar o backend em modo sintético sem banco, divergência de migrations, deep links quebrados no Pages, ausência de backup/restore demonstrado, ausência de rate limiting/limites de corpo e falta de teste físico do APK/AAB.

As duas contas beta administrativas foram criadas e o login delas foi validado na API Render. Isso valida a autenticação dessas contas, mas não valida ainda os fluxos completos de clínica, escola, metas, coletas, E2EE, câmera, sincronização ou operação em aparelho real.

## 2. Resultado por frente

| Frente | Status | Principal conclusão |
|---|---|---|
| Backend e autenticação | PARTIAL / alto risco | 70 testes passaram e 2 testes PostgreSQL foram pulados. Persistência real e isolamento completo ainda não foram certificados. |
| Portal Web e GitHub Pages | PARTIAL / bloqueado para uso | Login raiz funciona, mas deep links por acesso direto/reload retornam 404 e o workflow não executa a suíte do `portal-web`. |
| Flutter Mobile/APK | BLOCKED | O Manifest efetivo do release não contém `android.permission.INTERNET`; não há AAB verificado nem teste em aparelho. |
| Supabase/RLS/migrations | PARTIAL / alto risco | Projeto saudável e RLS habilitado, mas há migration remota não versionada, uso de role privilegiada e backup/restore não demonstrado. |
| Codemagic/CI | PARTIAL | O YAML referencia grupo e keystore, porém não há evidência auditável de build final APK+AAB com fingerprint aprovado. |
| Segurança operacional | BLOCKED | O backend pode iniciar em produção sem `DATABASE_URL` usando fixtures em memória; faltam rate limit, health/readiness, monitoramento, RTO/RPO e enforcement de HTTPS. |

## 3. Bloqueadores P0

1. **Backend fail-open:** fora de `NODE_ENV=test`, a ausência de `DATABASE_URL` não impede a inicialização; o serviço pode usar usuários e organizações sintéticos em memória e perder dados no restart.
2. **Isolamento de dados:** `esdm_goals` não possui `organization_id` e foi identificada possibilidade de leitura cruzada entre organizações. `organizations.status` também não participa adequadamente da autorização.
3. **APK release:** falta `INTERNET` no Manifest principal. Login, beta/status, sincronização, telemetria e reportador não funcionarão corretamente no release até a correção e reconstrução.
4. **Portal publicado:** o router usa `pushState`, mas acesso direto a rotas como `/portal/clinica` e `/portal/escola` pode retornar 404. O `base-href` do Flutter Web também está divergente do slug atual do Pages.
5. **Staging PostgreSQL:** `npm run test:db` não foi certificado com `DATABASE_URL`/`PGTEST_URL`; os testes de integração foram pulados.
6. **Backup e restauração:** não há restore drill comprovado nem RTO/RPO documentado.
7. **Segurança operacional:** não há HTTPS obrigatório na aplicação, rate limiting distribuído, limite explícito de corpo, health/readiness separado, métricas ou alertas suficientes.
8. **Migrations:** o Supabase possui uma migration remota de RLS que não está representada no conjunto local `001..007`.

## 4. Cronograma recomendado

### Fase 0 — congelamento e separação de ambientes

- Não usar dados de crianças/pacientes reais ainda.
- Manter staging isolado com dados sintéticos.
- Classificar os registros existentes no Supabase sem exibir conteúdo bruto.
- Registrar a origem das duas contas beta e da organização beta recém-criadas.

**Critério de saída:** ambientes e dados claramente separados; nenhum fixture usado fora de teste.

### Fase 1 — backend e banco, prioridade máxima

- Tornar o backend fail-closed quando faltar `DATABASE_URL`, `MASTER_CRYPTO_KEY`, origem HTTPS ou configuração obrigatória.
- Adicionar `organization_id` às metas e corrigir filtros, constraints e testes cross-tenant.
- Fazer organização suspensa bloquear leituras e escritas.
- Reconstituir e versionar a migration remota de RLS.
- Aplicar `001..007` em staging e executar `npm run test:db` sem skips.
- Definir role de aplicação não-owner ou estratégia equivalente com isolamento efetivo.
- Fazer backup e restore em projeto descartável.

**Critério de saída:** zero testes PostgreSQL pulados; cross-tenant retorna 403/404; restart preserva dados; restore é comprovado.

### Fase 2 — APK/AAB e Codemagic

- Adicionar `android.permission.INTERNET` ao Manifest principal.
- Exigir URL HTTPS no build e remover defaults localhost/sintéticos do release.
- Confirmar no Codemagic `beta-env` e `fala-comigo-release`.
- Gerar APK e AAB para commit imutável.
- Conferir Manifest mesclado, `versionCode`, fingerprint e assinatura com `apksigner`.
- Instalar em aparelhos/emuladores API 24, 33, 34 e 36.
- Testar login, beta gate, refresh, logout, câmera, galeria, microfone, notificações, alarmes, sync e bug report.
- Executar MobSF ou scanner equivalente no candidato.

**Critério de saída:** APK e AAB assinados e identificados; login e sincronização funcionam no aparelho; nenhum valor HTTP/localhost no release.

### Fase 3 — Portal Web e publicação

- Corrigir deep links por fallback `404.html` ou adotar hash routing.
- Tornar todos os `href` base-aware.
- Corrigir o `base-href` do Flutter para `/fala-comigo-esdm-plataforma/app/` ou definir oficialmente outro domínio/base path.
- Incluir `portal-web npm run check` e `npm test` no workflow Pages.
- Testar raiz, login, clínica, escola, relatórios, administração, reportar bug, reload e acesso direto.

**Critério de saída:** todas as rotas funcionam por clique, acesso direto e reload no mesmo prefixo.

### Fase 4 — segurança e operação

- Rate limiting para login, refresh, telemetria e report de bugs.
- Limite de `Content-Length`, timeout e quota por endpoint.
- HTTPS obrigatório, HSTS e headers de segurança.
- TLS PostgreSQL com validação de certificado.
- Endpoint separado de liveness/readiness.
- Métricas e alertas para 5xx, persistência, latência, login inválido e replay de refresh.
- Política de retenção/expurgo para telemetria, auditoria, bug reports e Discord.
- Runbook de incidente, recuperação de senha, revogação de sessões, rotação de chaves e restore.

**Critério de saída:** falhas e abuso são detectados, limitados e recuperáveis.

### Fase 5 — piloto beta controlado

- Usar somente contas descartáveis e dados sintéticos na primeira rodada.
- Executar E2E autorizado com equipe selecionada.
- Validar convite, aceite, escopos, clínica, escola, metas, coletas e reportador.
- Revogar contas, tokens e credenciais temporárias após o ensaio.
- Só depois aprovar o uso gradual de dados reais, com autorização formal e controles de privacidade.

## 5. O que já foi comprovado

- Portal funcional publicado no GitHub Pages.
- Suíte do portal: 29 testes aprovados.
- Testes públicos do site: 13 aprovados.
- Backend: 70 testes aprovados; 2 testes PostgreSQL pulados por falta de banco de teste.
- Flutter: análise sem problemas e 137 testes aprovados no ambiente que possui Flutter.
- Supabase: projeto ativo, RLS habilitado e advisor sem alerta de segurança imediato.
- Login das duas contas beta administrativas validado diretamente na API Render.
- Git limpo e alinhado à `origin/main` no commit auditado.

## 6. Decisão de prontidão

O sistema deve permanecer classificado como **PARTIAL/BLOCKED**, não como READY. A próxima execução deve começar pela Fase 1, especialmente fail-closed do backend, isolamento de metas, testes PostgreSQL reais em staging e backup/restore. Em paralelo, a correção do Manifest Android é necessária antes de qualquer distribuição do APK para teste remoto.
