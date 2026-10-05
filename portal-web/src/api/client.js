const SESSION_KEY = 'fala-comigo.portal.session';
const DEFAULT_API_BASE = 'http://127.0.0.1:8787';

export const goalTranslations = {
  CE_N1_I5: {
    missaoPais: 'Estimular o uso da voz para pedir itens no dia a dia.',
    dicaPratica: 'Aproxime o item favorito do seu rosto, espere uma vocalização e entregue imediatamente após qualquer tentativa.'
  },
  CE_N1_I6: {
    missaoPais: 'Ajudar a criança a escolher entre duas opções.',
    dicaPratica: 'Apresente duas opções visíveis, aguarde a iniciativa e valide qualquer gesto, olhar ou vocalização de escolha.'
  },
  SOC_N1_I3: {
    missaoPais: 'Fortalecer a participação em uma troca social curta.',
    dicaPratica: 'Siga o interesse da criança, faça uma pausa previsível e responda de forma alegre quando ela iniciar a interação.'
  }
};

function requestId() {
  return globalThis.crypto?.randomUUID?.() || `portal-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function getSession() {
  if (!globalThis.window?.localStorage) return null;
  try {
    return JSON.parse(window.localStorage.getItem(SESSION_KEY) || 'null');
  } catch (_) {
    return null;
  }
}

export function saveSession(session) {
  globalThis.window?.localStorage?.setItem(SESSION_KEY, JSON.stringify(session));
}

export function clearSession() {
  globalThis.window?.localStorage?.removeItem(SESSION_KEY);
}

export function getAccessToken() {
  return getSession()?.token || null;
}

function notifyAuthenticationRequired() {
  clearSession();
  const event = typeof CustomEvent === 'function'
    ? new CustomEvent('fala-comigo:auth-required')
    : { type: 'fala-comigo:auth-required' };
  globalThis.window?.dispatchEvent?.(event);
}

export class APIClient {
  constructor({ baseUrl = globalThis.window?.PORTAL_API_BASE || DEFAULT_API_BASE } = {}) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async request(path, { method = 'GET', body } = {}) {
    const session = getSession();
    const headers = {
      accept: 'application/json',
      'x-request-id': requestId()
    };
    if (session?.token) headers.authorization = `Bearer ${session.token}`;
    if (body !== undefined) headers['content-type'] = 'application/json';

    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      if (response.status === 401) notifyAuthenticationRequired();
      const error = new Error(payload.error || `HTTP_${response.status}`);
      error.status = response.status;
      error.renewalRequired = payload.renewalRequired === true;
      throw error;
    }
    return payload;
  }

  carregarPacientes(organizationId) {
    return this.request(`/v1/organizations/${encodeURIComponent(organizationId)}/subjects`);
  }

  carregarMetas(subjectId) {
    return this.request(`/v1/subjects/${encodeURIComponent(subjectId)}/esdm-goals`);
  }

  salvarMeta(subjectId, payload) {
    return this.request(`/v1/subjects/${encodeURIComponent(subjectId)}/esdm-goals`, { method: 'POST', body: payload });
  }

  carregarHistoricoEscolar(subjectId) {
    return this.request(`/v1/subjects/${encodeURIComponent(subjectId)}/school-collections`);
  }

  salvarColeta(subjectId, payload) {
    return this.request(`/v1/subjects/${encodeURIComponent(subjectId)}/school-collections`, { method: 'POST', body: payload });
  }
}

export const apiClient = new APIClient();
