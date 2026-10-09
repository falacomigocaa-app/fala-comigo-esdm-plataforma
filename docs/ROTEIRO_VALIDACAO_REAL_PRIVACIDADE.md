# Roteiro de validação real — Privacidade e consentimento

**Produto:** Fala Comigo
**Fase:** Prioridade 6 — privacidade, consentimento e preparação para validação real
**Participantes previstos:** 21 usuários/clínicas
**Regra:** iniciar com dados sintéticos; dados reais só podem entrar após aprovação do protocolo e da política.

## Critérios de entrada

Antes de convidar qualquer participante, confirmar que a política de privacidade foi revisada pela organização responsável, que os contatos do controlador e do canal de privacidade foram preenchidos e que o build usado no teste possui identificação de versão.

Cada participante deve receber uma conta de teste individual, sem reutilização de senha, e um identificador de teste que não contenha nome de criança, diagnóstico, telefone ou coordenada real. O ambiente de teste deve usar banco separado do ambiente de produção.

## Matriz de validação

| ID | Cenário | Resultado esperado | Evidência | Status |
|---|---|---|---|---|
| PRIV-01 | Abrir a área de privacidade sem rede | Texto local e controles continuam disponíveis | captura sem dados pessoais | ☐ |
| PRIV-02 | Tentar localização sem consentimento | Leitura bloqueada e nenhuma fila criada | log/teste local | ☐ |
| PRIV-03 | Conceder localização e negar permissão do sistema | App explica a diferença e não promete compartilhamento | captura | ☐ |
| PRIV-04 | Conceder consentimento e permissão | Leitura sob demanda funciona | captura com coordenada sintética ou ambiente controlado | ☐ |
| PRIV-05 | Revogar localização | Novas leituras bloqueadas, fila local removida e revogação remota enfileirada | log sanitizado | ☐ |
| PRIV-06 | Criar consentimento para profissional | Destinatário, finalidade, escopos, versão e validade aparecem | resposta sanitizada | ☐ |
| PRIV-07 | Revogar consentimento | Grant deixa de autorizar acesso imediatamente | teste de autorização | ☐ |
| PRIV-08 | Tentar acesso entre organizações | Requisição recusada sem revelar existência de dados | status HTTP e auditoria | ☐ |
| PRIV-09 | Exportar metadados | Exportação não contém plaintext clínico nem envelope descriptografado | arquivo sanitizado | ☐ |
| PRIV-10 | Excluir dados remotos do sujeito | Registros remotos são removidos e grants/consents revogados | resposta e contagem | ☐ |
| PRIV-11 | Apagar dados locais | Caixas locais e chaves temporárias são removidas | checklist do aparelho | ☐ |
| PRIV-12 | Comunicação offline | Cartões, fala e comunicação básica funcionam sem rede e sem plano pago | vídeo curto sem dados pessoais | ☐ |
| PRIV-13 | Reinstalar e reautenticar | Nenhum dado antigo reaparece sem restauração autorizada | log | ☐ |
| PRIV-14 | Expiração de consentimento | Sincronização é bloqueada e o item permanece pendente localmente | log sanitizado | ☐ |
| PRIV-15 | Access token expirado | Fila tenta uma renovação controlada e preserva o item em caso de falha | log sem token | ☐ |

## Regras de coleta de evidência

Nunca registrar tokens, chaves E2EE, PINs, nomes reais, e-mails reais, coordenadas exatas, áudio, foto, vídeo ou conteúdo clínico em capturas e logs. Os logs de validação devem ser sanitizados antes de sair do aparelho.

Para cada cenário, guardar apenas versão do app, sistema operacional, modelo do aparelho, data/hora aproximada, resultado e código de erro não sensível. O responsável pelo teste deve marcar o cenário como aprovado, reprovado ou bloqueado, com uma observação curta.

## Critérios de aprovação do beta

O beta só pode avançar quando os cenários **PRIV-02, PRIV-05, PRIV-07, PRIV-08, PRIV-09, PRIV-10 e PRIV-12** estiverem aprovados em Android e iOS, sem falha crítica aberta. Qualquer vazamento de plaintext, acesso entre organizações, envio sem consentimento ou bloqueio da comunicação offline interrompe a distribuição.

Os 21 participantes devem ser testados em lotes pequenos. O primeiro lote deve validar a instalação, login, comunicação offline e revogação. O segundo lote deve validar localização e consentimentos. O lote final deve repetir os cenários críticos com atualização de versão.

## Saída para a Prioridade 7

Ao concluir esta matriz, anexar o relatório sanitizado, a versão do build, os hashes dos artefatos e a lista de dispositivos. Só então executar o build final de distribuição e a validação física completa de alertas, localização, notificações, acessibilidade, autenticação e sincronização.
