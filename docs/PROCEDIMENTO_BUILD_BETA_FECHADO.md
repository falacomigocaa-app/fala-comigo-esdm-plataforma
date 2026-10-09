# Procedimento de build e teste fechado

**Projeto:** Fala Comigo
**Lote:** 21 participantes autorizados
**Objetivo:** validar o build de teste em Android e iOS sem usar dados reais por padrão.

## Limites do ambiente atual

O workspace Linux não possui Flutter, Dart nem Xcode. Portanto, o build Android deve ser executado pelo workflow `Android test APK artifact` em um runner Ubuntu, e o build iOS pelo workflow `iOS test build` em um runner macOS.

O APK do beta é assinado com uma chave efêmera de teste e não deve ser publicado na Play Store. O artefato iOS do workflow é técnico e não assinado; instalação em aparelho e TestFlight exigem certificados, provisioning profile e credenciais Apple configurados fora do repositório.

## Execução dos workflows

1. Confirmar que o commit do candidato está na branch de teste.
2. Executar manualmente `Android test APK artifact`.
3. Conferir no artifact o APK e o SHA-256.
4. Executar manualmente `iOS test build`.
5. Conferir no artifact o pacote `.app` técnico e o SHA-256.
6. Guardar os hashes no relatório do beta.
7. Para distribuição TestFlight ou Play Console, criar uma etapa separada com credenciais oficiais e revisão de assinatura; nunca colocar keystore, certificado ou token no Git.

## Preparação dos aparelhos

Usar aparelhos Android e iOS atualizados, com bateria suficiente, data/hora automáticas e rede disponível para login inicial. Depois do login, repetir os cenários essenciais em modo avião.

Cada participante deve receber um código de teste, não um nome de criança. O conjunto inicial deve conter dados sintéticos, cartões genéricos e coordenadas não reais. A conta deve ser individual e revogável.

## Lotes de 21 participantes

| Lote | Participantes | Foco |
|---|---:|---|
| Piloto | 3 | instalação, login, comunicação offline, acessibilidade e exclusão local |
| Expansão | 8 | alertas, consentimento, localização sob demanda e revogação |
| Confirmação | 10 | sincronização, rotação de sessão, exportação e regressão offline |

O lote seguinte só começa se não houver falha crítica no lote anterior. Falha crítica significa: perda da comunicação básica offline, envio sem consentimento, exposição de plaintext, acesso entre organizações, revogação que não interrompe o acesso ou crash no fluxo principal.

## Evidências mínimas por aparelho

Registrar somente versão do app, sistema operacional, modelo, lote, cenário, resultado e hash do artefato. Não registrar tokens, chaves, PINs, nomes, e-mails pessoais, coordenadas exatas, áudio, vídeo ou diagnóstico.

Para Android, confirmar instalação do APK, abertura, permissões de localização, notificações, rotação, modo offline, sincronização posterior e remoção local. Para iOS, confirmar instalação pelo canal assinado aprovado, permissões equivalentes, notificações, localização em primeiro plano, modo offline e revogação.

## Gate de encerramento

O teste fechado só pode ser encerrado quando todos os cenários críticos do roteiro de privacidade estiverem aprovados nos dois sistemas, os hashes estiverem arquivados e as falhas conhecidas tiverem responsável e decisão registrada.

A aprovação deste procedimento não equivale à aprovação jurídica, à publicação comercial, à certificação de segurança ou à liberação de pagamentos reais.
