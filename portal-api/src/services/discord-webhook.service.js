const severityLabels = {
  leve: 'Leve',
  travamento: 'Travamento',
  sugestao: 'Sugestão'
};

const severityColors = {
  leve: 0x2f80ed,
  travamento: 0xd64545,
  sugestao: 0xf2a900
};

function technicalValue(value, fallback = 'Não informado') {
  const text = typeof value === 'string' ? value.trim() : '';
  return text ? text.slice(0, 1024) : fallback;
}

export function discordEmbedForReport(report) {
  const severity = severityLabels[report.severity] ?? 'Beta';
  return {
    username: 'Fala Comigo Beta',
    allowed_mentions: { parse: [] },
    embeds: [{
      title: `Reporte do beta — ${severity}`,
      description: technicalValue(report.description, 'Sem descrição'),
      color: severityColors[report.severity] ?? 0x5865f2,
      fields: [
        { name: 'Versão do app', value: technicalValue(report.appVersion), inline: true },
        { name: 'Plataforma', value: technicalValue(report.platform), inline: true },
        { name: 'Modelo do dispositivo', value: technicalValue(report.deviceModel), inline: true }
      ],
      footer: { text: 'Fala Comigo • Beta — conteúdo técnico sanitizado' },
      timestamp: report.createdAt
    }]
  };
}

export function createDiscordNotifier({
  webhookUrl = process.env.DISCORD_WEBHOOK_URL,
  fetchImpl = globalThis.fetch,
  logger = console
} = {}) {
  const url = typeof webhookUrl === 'string' ? webhookUrl.trim() : '';
  const validWebhookUrl = /^https:\/\/(?:discord(?:app)?\.com)\/api\/webhooks\//.test(url);

  return {
    enabled: Boolean(validWebhookUrl && typeof fetchImpl === 'function'),
    async notify(report) {
      if (!validWebhookUrl || typeof fetchImpl !== 'function') return false;
      try {
        const result = await fetchImpl(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(discordEmbedForReport(report))
        });
        if (result?.ok === false) {
          throw new Error(`Discord webhook HTTP ${result.status ?? 'error'}`);
        }
        return true;
      } catch (error) {
        // O Discord é apenas uma notificação secundária; nunca falha o report persistido.
        logger?.warn?.('[portal-api] falha no webhook Discord:', error.message);
        return false;
      }
    }
  };
}
