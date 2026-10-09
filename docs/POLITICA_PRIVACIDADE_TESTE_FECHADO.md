# Política de Privacidade — Fala Comigo

**Versão:** 1.0 — 09/10/2026
**Escopo:** teste fechado com dados sintéticos e participantes autorizados

> Este documento é uma base de produto para revisão jurídica antes de qualquer publicação. Ele não substitui assessoria jurídica nem representa uma certificação de segurança ou conformidade.

## 1. Princípios

O Fala Comigo é uma aplicação de Comunicação Aumentativa e Alternativa. O produto adota minimização, privacidade por padrão, consentimento explícito e funcionamento offline para a comunicação básica.

A comunicação básica, os cartões locais, os controles parentais e a acessibilidade não dependem de assinatura paga, conexão permanente ou compartilhamento remoto.

## 2. Dados que podem ser tratados

Dependendo da funcionalidade ativada pelo responsável, o aplicativo pode tratar:

- configurações locais, cartões e rotinas visuais;
- registros de uso e acompanhamento inseridos pelo responsável;
- alertas de transição e configurações de notificação;
- localização, somente após consentimento explícito, permissão do sistema e ativação pelo responsável;
- informações de conta necessárias para autenticação e sincronização;
- arquivos de mídia selecionados pelo responsável para uso local;
- dados administrativos de plano e assinatura, sem armazenar cartão ou CVV no aplicativo.

Dados clínicos e registros de comunicação são cifrados antes da sincronização. O Portal API deve armazenar apenas envelopes E2EE para esses conteúdos.

## 3. Localização

A localização fica desativada por padrão. O aplicativo solicita uma ação clara do responsável e uma permissão do sistema operacional antes de obter uma posição.

A revogação interrompe novas leituras, remove o estado de consentimento local e solicita a remoção dos envelopes remotos autorizados. A localização não é usada para publicidade, venda de perfil ou rastreamento oculto.

## 4. Compartilhamento com clínicas, escolas e profissionais

O compartilhamento depende de um consentimento com:

- sujeito ao qual o consentimento se refere;
- destinatário identificado;
- finalidade;
- escopos limitados;
- versão do aviso;
- prazo de validade;
- possibilidade de revogação.

A revogação bloqueia o grant correspondente e impede novas operações autorizadas. Revogar não desfaz cópias que um terceiro já tenha exportado por decisão própria.

## 5. Voz, áudio, fotos e vídeos

Mídias selecionadas ou gravadas são armazenadas localmente por padrão. O responsável decide quando exportar ou compartilhar. O app não deve enviar mídia automaticamente sem uma ação e uma autorização correspondentes.

## 6. Retenção e exclusão

O responsável pode apagar os dados locais pela Área Parental. A exclusão local remove o conteúdo protegido deste aparelho, mas não consegue apagar cópias já exportadas para fora do app.

O endpoint de direitos do titular permite solicitar exportação de metadados e exclusão dos dados remotos vinculados ao sujeito autorizado. Conteúdo E2EE não é descriptografado pelo portal durante a exportação.

Prazos de retenção operacional, backups e registros de auditoria devem ser definidos antes da publicação comercial.

## 7. Segurança

- tokens de sessão usam access token de curta duração e refresh token rotacionável;
- chaves E2EE são versionadas e armazenadas no Keychain/Keystore do aparelho;
- PINs não são armazenados em claro;
- caixas locais sensíveis usam armazenamento protegido;
- endpoints validam organização, sujeito, escopo, consentimento e expiração;
- webhooks de cobrança sandbox exigem assinatura HMAC e idempotência.

Nenhum ambiente de teste deve usar nomes, diagnósticos, fotos, áudios, coordenadas ou credenciais reais.

## 8. Direitos do participante do teste

Durante o teste fechado, o participante pode solicitar:

- informação sobre os dados tratados;
- exportação de metadados;
- correção de informações administrativas;
- revogação de consentimento;
- exclusão dos dados remotos e locais;
- encerramento da participação no teste.

O canal de atendimento, controlador, operador, prazos legais e base legal devem ser preenchidos pela organização responsável antes do convite real aos 21 participantes.

## 9. Contatos e publicação

Os campos abaixo são obrigatórios antes da distribuição externa:

- **Controlador:** a definir pela organização responsável;
- **Contato de privacidade:** a definir;
- **Encarregado/DPO:** a definir;
- **URL pública desta política:** a definir;
- **Data de revisão:** antes do início do teste com dados reais.
