# Checklist de execução — Fase 1

**Projeto:** Fala Comigo  
**Data da avaliação:** 08/10/2026  
**Fonte de escopo:** `Comandofinalfalacomigo1.1.pdf`  
**Estado da branch:** `main` limpa e sincronizada após o commit `6a45495`.

## Como ler este checklist

- `[x]` **Concluído e validado** no repositório/CI.
- `[~]` **Parcial**: existe uma base funcional, mas o requisito completo ainda não foi comprovado.
- `[ ]` **Pendente**: ainda não implementado ou não validado.
- `[?]` **Não validado**: requer inspeção/teste específico antes de marcar.

## Fase 0 — Alertas de transição

- `[~]` Modelos, telas de listagem/edição e integração local existem no código.
- `[~]` Persistência e agendamento local existem, mas o requisito completo do PDF — push, múltiplos dispositivos, app fechado, iOS/Android e sincronização backend — ainda não está validado como pronto para teste fechado.
- `[ ]` Matriz de testes em dispositivos reais (Android 8–15, iOS 13+, foreground/background/encerrado/DND/bateria baixa).

## Fase 1.1 — Área parental / UX/UI

- `[ ]` Dashboard inicial separado da lista de configurações. Atualmente a entrada continua sendo `SettingsScreen`, com uma lista longa de seções.
- `[~]` Hierarquia visual: já existem `OptionASectionBox`, cards, cores por funcionalidade e paleta profissional; ainda falta uma hierarquia consistente por prioridade alta/média/baixa em toda a área.
- `[ ]` BottomNavigationBar funcional. O componente existe em `settings_screen.dart`, mas `currentIndex` está fixo em `0` e `onTap` é um no-op.
- `[~]` Gate de PIN: primeiro acesso, login, erro e lockout já possuem textos e feedback; ainda faltam representação visual dos quatro dígitos e uma diferenciação visual completa do estado bloqueado.
- `[~]` Cartões: há fluxo de criação/edição; preview/thumbnail, agrupamento por categoria e drag-and-drop ainda precisam ser confirmados ou implementados.
- `[ ]` Temas de hiperfoco em miniaturas: atualmente são `ChoiceChip` com emoji/nome; falta mini-preview visual e preview em tempo real.
- `[~]` Identidade visual Material 3: há paleta profissional, bordas e espaçamento melhorados; a densidade e a sensação de “painel” ainda precisam de uma rodada dedicada.
- `[ ]` Validação visual responsiva e acessibilidade da área parental em telas pequenas, tablet, contraste e touch targets.

## Fase 1.2 — Backend e autenticação

- `[x]` JWT com access token de 15 minutos, refresh token rotativo de 7 dias, bcrypt, Bearer e PostgreSQL.
- `[x]` Login e refresh reais em `/v1/auth/login` e `/v1/auth/refresh`.
- `[x]` CI PostgreSQL efêmero com migrations 001–005 e testes de integração verdes.
- `[~]` O PDF ainda cita endpoints genéricos `/auth/register`, `/data/sync` e `/reports/generate`; eles não fazem parte do contrato atual validado e não devem ser criados sem especificação funcional e de segurança.
- `[ ]` Rate limiting de produção e validação operacional de HTTPS/segredos no ambiente de deploy.

## Fase 1.3 — Criptografia

- `[x]` E2EE AES-256-GCM por organização no Mobile, envelopes sem plaintext e recepção sem descriptografia no backend.
- `[x]` Chaves de organização cifradas em repouso com `MASTER_CRYPTO_KEY`, endpoint protegido e Web Crypto no Portal Web.
- `[~]` A exigência ampla do PDF de criptografar todos os dados locais deve ser auditada por entidade/box; ela não deve ser considerada automaticamente concluída apenas pelo E2EE de coletas escolares.

## Fase 1.4 — Autenticação forte

- `[x]` Login email/senha, JWT, refresh rotativo e armazenamento seguro no Mobile.
- `[ ]` Biometria, 2FA e recuperação de senha por email.
- `[~]` Expiração e reautenticação estão cobertas; falta a validação de produto dos fluxos de recuperação e segundo fator.

## Fase 1.5 — Conformidade legal

- `[?]` Política de privacidade, termos, exportação, exclusão e consentimentos devem ser inventariados contra os documentos legais finais; não marcar como concluído apenas por existirem telas de privacidade.

## Fase 1.6 — Localização

- `[ ]` GPS/mapa/histórico/bateria/compartilhamento ainda não estão implementados como módulo operacional. A interface atual apresenta roadmap seguro e não inventa localização.

## Fase 1.7 — Planos e pagamentos

- `[ ]` Modelo freemium, assinatura e integração de pagamento não estão implementados/validados.

## Próximo ponto exato de retomada

1. Implementar a **Fase 1.1A: dashboard parental + navegação funcional**, sem alterar stores ou contratos clínicos.
2. Criar testes de widget para: dashboard visível, contadores de cartões/alertas, ações rápidas e quatro destinos da navegação.
3. Depois implementar a **Fase 1.1B: gate de PIN visual**, com quatro indicadores de dígitos, estados primeiro acesso/login/erro/bloqueado e acessibilidade.
4. Em seguida abordar cartões, temas e responsividade em commits separados.
5. Rodar `dart format`, `flutter analyze`, `flutter test` e o build Web antes de cada publicação.

> Não declarar a Fase 1 como concluída até que os itens `[ ]` da Fase 1.1 sejam implementados e validados. A última validação conhecida do app foi de 122 testes Flutter aprovados; a página pública e o app Web responderam HTTP 200 após o commit `6a45495`.
