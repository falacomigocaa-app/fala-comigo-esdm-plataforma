# Prontidão — Fala Comigo

Atualização de trabalho: 10/10/2026. Branch `coderabbit/audit-test-improvements/b0f933e5`, base `200f9b9ba303d6884a105044baad7124532bfb39`. Este documento será fechado após os últimos builds.

## Implementado nesta etapa

- Autorização/consentimentos persistentes em PostgreSQL; membership revalidada; idempotência transacional por ator, organização e operação.
- Exclusão local inclui tokens, chaves e concessões; login/refresh concorrente não reconstitui sessão apagada.
- Chave provisionada integrada à fila mobile; retries preservam o envelope; seleção de paciente e isolamento de coletas locais.
- Portal responsivo com login, clínica, coleta cifrada, relatórios e PDF.
- Convite de conta por email com link de ativação de uso único (entrega manual por canal privado); senha definida pelo destinatário; escopos explícitos no servidor; edição/revogação de vínculos; troca de senha.
- Cadastro pelo responsável e autorização por paciente, com finalidade, permissões, prazo e revogação.
- Prancha PDF sem fotos pessoais para apoiar comunicação quando o aparelho estiver indisponível.
- Migrations com checksum/ledger, bootstrap administrativo sem contas demo, Docker API/portal e composição com PostgreSQL/Caddy.

## Referências pesquisadas

Páginas oficiais consultadas em 10/10/2026; análise documental, sem avaliação clínica ou instalação dos produtos:

| Referência | Evidência da página | Aplicação neste projeto |
| --- | --- | --- |
| [Cboard](https://www.cboard.io/en/) | Navegadores, offline no Chrome e impressão de pranchas | Preservar CAA offline; adicionar prancha em papel; testar navegador e telas pequenas |
| [Proloquo2Go](https://www.assistiveware.com/products/proloquo2go) | Personalização, layouts e diferentes necessidades de acesso | Preservar ordem estável; ampliar validação de tamanho/contraste/teclado antes de adicionar automações |
| [Avaz](https://avazapp.com/avaz-aac/) | Aviso de compatibilidade de backup entre versões | Tratar backup/restauração/migração como gate de integridade, sem substituir implementação por cópia visual |

LetMeTalk retornou HTTP500 durante a pesquisa. Não foi usado como evidência de funcionalidades. Nenhuma imagem, marca, vocabulário ou código de concorrentes foi copiado.

## O que ainda impede lançamento público

1. Domínios e infraestrutura reais; banco de produção, segredos privados, backup e restauração testada; TLS/DNS.
2. Keystore de produção/upload e configuração da Play Console; versionCode de lançamento e AAB assinado com identidade definitiva.
3. Testes em aparelho Android: abertura fria, TTS audível, permissões, áudio/fotos, notificações, retorno do background, modo avião, atualização preservando dados e wipe.
4. Revisão da proteção de dados no navegador. O Web mantém limitações de mídia privada e notificações; não remover avisos de prévia antes da validação correspondente.
5. Recuperação de conta e operação de suporte; entrega automática de email não está configurada. Links de ativação exigem canal privado e identidade verificada pelo operador.
6. Localização, pagamentos, console comercial e licenças remotas precisam de requisitos/integração próprios. Não são habilitados apenas pela mudança de rótulo do produto.
7. Teste de carga e política de retenção/expurgo de auditoria, idempotência, convites e refresh tokens; limitação de login deve ser dimensionada para a topologia do proxy.

A criptografia atual utiliza chave por organização e autorização de paciente no servidor. Revogar acesso impede novas leituras, mas não apaga cópias já recebidas nem gira automaticamente a chave. Não descrever isso como revogação retroativa ou isolamento criptográfico por paciente.

## Próximos gates

Fechar smoke das novas telas, compilar APK/AAB/Web, testar bootstrap/deploy final, documentar comandos de operação e registrar a branch. A publicação pública depende dos itens operacionais acima; nenhum resultado local substitui esse gate.
