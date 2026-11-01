# Plano sequencial para funcionamento real do Fala Comigo

Este documento define a ordem obrigatória para concluir o beta real. Nenhuma etapa posterior deve ser considerada concluída enquanto o respectivo critério de aceite não estiver comprovado.

## Regra principal

Não gerar APK/AAB final e não declarar o sistema pronto enquanto o fluxo abaixo não for executado de ponta a ponta com contas reais isoladas:

```text
Instalação → login do responsável → PIN parental → criar convite
→ compartilhar convite → abrir link → cadastro/login convidado
→ aceitar convite → acesso limitado no Portal → revogar acesso
→ confirmar bloqueio após revogação
```

## Fase 0 — Congelamento e ambiente

### Objetivo
Garantir que todos os componentes apontem para o mesmo ambiente beta.

### Tarefas

- [ ] Confirmar branch `main` como fonte do Render, GitHub Pages e Codemagic.
- [ ] Confirmar commit de trabalho no repositório.
- [ ] Confirmar URL do backend: `https://fala-comigo-api-beta.onrender.com`.
- [ ] Confirmar URL do Portal Web publicada no GitHub Pages.
- [ ] Confirmar que o projeto Supabase beta está ativo.
- [ ] Confirmar `DATABASE_URL`, `JWT_SECRET` e `MASTER_CRYPTO_KEY` somente no Render.
- [ ] Confirmar que senhas, tokens e chaves não estão no Git.

### Portão de aceite

O backend responde por HTTPS, o Portal carrega e o Render está conectado ao commit correto da `main`.

## Fase 1 — Identidade do responsável no aplicativo

### Objetivo
Fazer o responsável entrar uma vez e manter uma sessão segura sem armazenar a senha.

### Tarefas

- [ ] Exibir `Entrar ou criar conta` no primeiro acesso que exigir recursos online.
- [ ] Salvar somente access token e refresh token no armazenamento seguro do aparelho.
- [ ] Renovar o access token automaticamente usando refresh token rotativo.
- [ ] Limpar a sessão quando o refresh token expirar ou for revogado.
- [ ] Manter o PIN parental como proteção local independente da senha online.
- [ ] Exibir claramente se o aplicativo está online, offline ou sem sessão.
- [ ] Impedir que o modo offline seja apresentado como sincronizado.

### Portão de aceite

Após fechar e reabrir o aplicativo, o responsável continua autenticado sem redigitar a senha. Após logout, a sessão não é recuperada.

## Fase 2 — Convite remoto pelo aplicativo

### Objetivo
Permitir que o responsável convide uma clínica, escola ou profissional de forma clara.

### Tarefas

- [ ] Abrir `Área parental → Gerenciar acessos → Convidar`.
- [ ] Informar organização, e-mail ou WhatsApp do destinatário.
- [ ] Escolher se o acesso é de clínica, escola ou profissional.
- [ ] Selecionar a criança ou sujeito autorizado.
- [ ] Selecionar finalidade do acesso.
- [ ] Selecionar permissões mínimas.
- [ ] Definir data de expiração.
- [ ] Criar o convite no backend.
- [ ] Mostrar status real: criado, compartilhado, aceito, expirado ou revogado.
- [ ] Mostrar o link retornado pelo servidor.
- [ ] Permitir copiar, compartilhar e abrir WhatsApp.

### Portão de aceite

O convite sobrevive ao fechamento do aplicativo, aparece no banco beta e não depende de registro local fictício.

## Fase 3 — Aceite no Portal Web

### Objetivo
Permitir que o convidado aceite o convite com conta própria.

### Tarefas

- [ ] Abrir `/convite/TOKEN` sem sessão prévia.
- [ ] Exibir organização, função, validade, finalidade e permissões.
- [ ] Permitir criar conta se o e-mail ainda não existir.
- [ ] Permitir entrar se a conta já existir.
- [ ] Conferir o e-mail do destinatário.
- [ ] Aceitar o convite uma única vez.
- [ ] Criar membership com os escopos autorizados.
- [ ] Criar grant/consentimento da criança quando aplicável.
- [ ] Redirecionar para a área correta do Portal.
- [ ] Rejeitar token expirado, alterado, revogado ou reutilizado.

### Portão de aceite

Uma conta de clínica ou escola consegue aceitar um convite e acessar somente a organização, criança e escopos autorizados.

## Fase 4 — Consentimento e isolamento clínico

### Objetivo
Impedir que o convite organizacional seja confundido com autorização irrestrita de dados clínicos.

### Tarefas

- [ ] Vincular convite à criança correta.
- [ ] Exigir finalidade explícita.
- [ ] Exigir escopos explícitos.
- [ ] Não permitir que o papel amplie escopos vazios ou ausentes.
- [ ] Bloquear leitura de outra organização.
- [ ] Bloquear leitura de outra criança.
- [ ] Bloquear metas, coletas e relatórios fora do consentimento.
- [ ] Revogar o acesso imediatamente quando o responsável cancelar.
- [ ] Registrar auditoria de criação, aceite e revogação.

### Portão de aceite

Testes cruzados provam que clínica A não acessa dados da escola B nem dados de outra criança.

## Fase 5 — Portal operacional

### Objetivo
Garantir que clínica, escola e administração possam trabalhar com os dados reais autorizados.

### Tarefas

- [ ] Login da clínica.
- [ ] Login da escola.
- [ ] Administração de profissionais.
- [ ] Metas ESDM.
- [ ] Coletas escolares E2EE.
- [ ] Relatórios autorizados.
- [ ] Expiração e renovação de sessão.
- [ ] Logout e revogação.
- [ ] Mensagens de erro compreensíveis para usuário leigo.

### Portão de aceite

Cada perfil executa apenas as operações previstas e todos os dados persistidos são recuperados após reiniciar o backend.

## Fase 6 — Comunicação de convites

### Objetivo
Evitar que o usuário veja “convite enviado” quando apenas o link foi criado.

### Tarefas

- [ ] Diferenciar `convite criado` de `mensagem compartilhada`.
- [ ] WhatsApp: abrir mensagem pronta e registrar que o link foi compartilhado somente quando aplicável.
- [ ] E-mail: configurar provedor transacional ou SMTP.
- [ ] Registrar falha de envio sem invalidar o convite.
- [ ] Permitir reenvio seguro.
- [ ] Impedir spam com limite por destinatário e organização.

### Portão de aceite

O sistema informa honestamente se criou, compartilhou, enviou, aceitou ou expirou o convite.

## Fase 7 — Segurança, observabilidade e recuperação

### Tarefas

- [ ] Rate limiting por IP, conta e organização.
- [ ] Health check e readiness check.
- [ ] Logs sem senha, tokens ou conteúdo clínico.
- [ ] Backup criptografado.
- [ ] Teste de restauração do backup.
- [ ] RLS validado nas tabelas beta.
- [ ] Rotação documentada de JWT e chaves.
- [ ] Teste de expiração do beta.
- [ ] Teste de fraude do relógio local.
- [ ] Teste de falha do Discord/e-mail sem perda de dados.

### Portão de aceite

Existe evidência registrada de que o serviço pode falhar, recuperar e continuar sem expor dados ou confirmar operações não persistidas.

## Fase 8 — Teste real controlado

Executar com contas reais selecionadas, usando dados de teste autorizados pela equipe beta:

1. Responsável cria sessão no aplicativo.
2. Responsável cria convite para clínica.
3. Clínica recebe e aceita.
4. Clínica acessa somente os escopos autorizados.
5. Responsável cria convite para escola.
6. Escola recebe e aceita.
7. Escola acessa somente os escopos escolares.
8. Responsável revoga clínica.
9. Clínica perde acesso imediatamente.
10. Responsável fecha e reabre o app.
11. Portal renova a sessão.
12. Convite expirado é recusado.
13. Token alterado é recusado.
14. Dados de uma organização não aparecem em outra.

### Portão de aceite

Todos os cenários passam com evidência de resposta HTTP, tela observada e estado persistido no banco beta.

## Fase 9 — Build de distribuição

Somente depois dos portões anteriores:

- [ ] Codemagic usa `main`.
- [ ] Codemagic usa o commit validado.
- [ ] Keystore correta está selecionada.
- [ ] Grupo `beta-env` está configurado.
- [ ] APK assinado é gerado.
- [ ] AAB assinado é gerado.
- [ ] APK é instalado em aparelho físico.
- [ ] Login, PIN, câmera, sincronização e Portal são testados no APK.
- [ ] SHA/versão do APK é registrada.

## Fase 10 — Distribuição beta

- [ ] Publicar APK para a equipe selecionada.
- [ ] Entregar instrução de instalação.
- [ ] Entregar instrução de login.
- [ ] Entregar instrução de convite.
- [ ] Entregar canal de suporte/bug report.
- [ ] Monitorar logs e erros.
- [ ] Registrar incidentes e correções.
- [ ] Não liberar acesso além da equipe autorizada.

## Estado atual

A implementação atual já cobre parte das Fases 2 e 3:

- Convite remoto básico.
- Token com hash no banco.
- Link seguro.
- Página pública de convite.
- Cadastro por convite.
- Criação de membership.
- Sessão de Portal.
- Compartilhamento manual por WhatsApp.

Ainda não deve ser considerado 100% concluído porque as Fases 1, 4, 6 e 8 ainda precisam de validação completa no aplicativo e com PostgreSQL beta real.

## Regra de decisão

Se qualquer portão falhar, a build final fica bloqueada. Primeiro corrige-se o código, executam-se os testes novamente e só depois se avança para a próxima fase.
