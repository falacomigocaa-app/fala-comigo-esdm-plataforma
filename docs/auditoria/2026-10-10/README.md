# Auditoria técnica — Fala Comigo — 10/10/2026

## Resultado

Auditoria dos fluxos críticos do aplicativo Flutter, Portal API, Portal Web e configuração de CI. Correções implementadas na branch `coderabbit/audit-and-fix-issues/0959ae64`, commit `68ff6c1b26af1bf25fadf9a869592f7b0aabeb4f`. Base inspecionada: `200f9b9ba303d6884a105044baad7124532bfb39`.

Não é uma certificação de segurança nem uma declaração de prontidão de todo o produto. Foram reproduzidos inicialmente 13 cenários de falha da API; a cobertura final acrescenta 16 regressões na API, 7 no portal e 4 no Flutter.

## Falhas corrigidas

| Área | Falha e correção |
|---|---|
| Validade | Relógio da API estava fixo em setembro. Agora usa a hora atual; datas inválidas em membership, consentimento, grant e convite falham fechadas. |
| Autorização clínica | Leitura/escrita de metas e coletas agora exige membership vigente e escopo no JWT e no vínculo atual. Grant confere organização ativa no token e correspondência do consentimento com indivíduo, destinatário, organização, finalidade e escopo. |
| Consentimento | A listagem de indivíduos deixa de revelar registros quando o consentimento está revogado/expirado. |
| Isolamento | Histórico escolar agora é filtrado pela organização do token, também na query PostgreSQL; envelopes de outro tenant deixam de ser retornados. |
| Idempotência | Cache separado por usuário, organização, método e caminho; requisições concorrentes compartilham a gravação; payload diferente retorna 409; falha permite retry; resposta fica preservada mesmo após mutações. |
| Chaves no login | Login deixa de expor a chave da organização a quem não tem `organization.key.read`, aplicando a mesma restrição do endpoint de chaves. |
| Refresh | Renovação valida membership atual e remove privilégios que deixaram de existir; vínculo revogado/expirado é rejeitado. |
| Convites | Rejeita papel `owner`, escopos fora do papel e prazo inválido; aceite respeita escopos explícitos (inclusive lista vazia), atualiza vínculo existente e limita o grant ao consentimento. A tabela web respeita escopos vazios. |
| Validação de metas | Propriedades herdadas, como `toString`, deixam de ser aceitas como códigos ESDM. |
| Sessão web | 401 tardio reutiliza token já renovado; retry preserva request ID; refresh não ressuscita logout nem sobrescreve login novo; sessões distintas têm promises distintas. |
| Resumo escolar | Descriptografa envelopes antes de calcular autonomia e montar o histórico, evitando campos `undefined` e métricas ausentes. |
| E2EE mobile | Login importa a chave legítima de 32 bytes do servidor. Novas chaves aleatórias por aparelho deixam de ser criadas para organização remota. Conflito de chave preserva os dados e bloqueia substituição; sem chave a coleta já salva permanece local. |
| Exclusão local | Wipe inclui metas, concessões, coletas atuais/legadas, fila legada, tokens access/refresh e chaves E2EE/ESDM; interrompe o monitor de sincronização antes da exclusão. |
| Tokens mobile | Refresh vazio é validado antes de alterar o access token existente. |
| CI e dependências | Workflows/Codemagic usam Flutter 3.47.6, compatível com o Dart do lockfile e validado localmente; `pub get --enforce-lockfile` preserva as versões. Dependências Node ficam ignoradas pelo Git. |
| Isolamento de testes | Testes de permissão/chave usam stores em memória isolados; integração PostgreSQL cobre chave, isolamento de coletas e revogação/remoção de escopos em transação. Evita contaminar o seed cifrado entre execuções. |

## Evidência de validação

Executada neste sandbox com Flutter 3.47.6 / Dart 3.13.5 e Node 24.14.1 / npm 11.11.0.

| Verificação | Resultado |
|---|---|
| `flutter pub get --enforce-lockfile` | Aprovado; lockfile preservado. |
| `flutter analyze --no-pub` | Nenhum problema. |
| `dart format --output=none --set-exit-if-changed lib test` | 139 arquivos, nenhuma alteração. |
| `flutter test` | 132 aprovados. |
| `flutter build web --release` | Build gerado; avisos do dry run WASM em plugins de terceiros. Build JavaScript aprovado. |
| Portal API: `npm test`, PostgreSQL 16 | 53 aprovados, zero falhas, zero skips; migrations 001–005 e seeds sintéticos aplicados. |
| Portal API: `npm test`, memória | 52 aprovados; 1 teste PostgreSQL condicional ignorado. Esse teste passou no banco real. |
| Portal Web: `npm test` e `npm run check` | 25 aprovados e sintaxe aprovada. |
| `node --test tests/*.test.mjs` | 13 aprovados antes das alterações; resultado reutilizado, site e testes permanecem iguais. |
| YAML de workflows e Codemagic | Arquivos parseados sem erro com pacote `yaml`. |
| Política de assinatura debug/release e `git diff --check` | Aprovados. |

A primeira repetição da suíte PostgreSQL encontrou um login 500 porque um teste anterior havia regravado o seed com outra chave mestra sintética. O isolamento foi corrigido, o seed restaurado e a suíte final passou; uma nova execução também passou sem restaurar chaves, comprovando que os testes deixaram de contaminar o seed.

## Pendências e limites reais

1. **Produção do portal:** `createStore` ainda inicializa usuários, memberships, consentimentos, grants, convites, relações e auditoria a partir de fixtures em memória. PostgreSQL persiste credenciais/login, refresh, chaves, metas e coletas, mas não há autorização totalmente persistente nas rotas. Não usar dados reais nem declarar o portal pronto para produção. O próximo gate é substituir as fixtures por repositórios de autorização transacionais, com testes de reinício/revogação.
2. **Instalações antigas:** uma chave E2EE aleatória já criada por versão anterior não é substituída silenciosamente. Migração/reprocessamento dos envelopes legados precisa de etapa própria com recuperação de dados. Sem chave provisionada, a coleta permanece local; não é prometido upload automático retroativo de registros que nunca entraram na fila.
3. **Política de papéis/chaves:** profissionais sem o escopo dedicado deixam de receber chave no login. Ampliação de papéis para relatórios/coletas e compartilhamento de chaves deve ser especificada e autorizada, mantendo consentimento e privilégio mínimo. `report.read` exibido no formulário ainda não corresponde a uma capacidade implementada na API; a API rejeita escopos não suportados.
4. **Mobile:** o refresh HTTP automático ainda não está implementado; a fila conserva os itens e exige reautenticação em 401. A cobertura anterior que simulava a expiração de refresh não comprovava chamada real de renovação.
5. **Dispositivo e CI remoto:** não foram executados APK/AAB, teste Android/iOS físico, MobSF nem jobs remotos após a atualização. Os YAML foram validados localmente; publicação/release e assinatura produtiva continuam pendentes.
6. **Segurança previamente documentada:** migração das camadas CBC/Hive/secure storage, rate limiting de produção, HTTPS operacional e recuperação/2FA continuam pendentes. Não foram alteradas criptografia Hive nem política de migração para fazer esta auditoria passar.
7. **UX:** responsividade/acessibilidade completa da Fase 1.1D continua pendente. O build web é evidência de compilação, não substitui teste visual ou validação em aparelho.

## Próximo gate

Revisar esta branch e executar CI da PR. Priorizar persistência de autorização e recuperação das chaves legadas antes de qualquer piloto com dados reais. Em seguida validar aparelho, refresh HTTP mobile e responsividade.
