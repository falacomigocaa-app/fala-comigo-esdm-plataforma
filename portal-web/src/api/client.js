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

function sameIdentity(left, right) {
  return left?.userId === right?.userId && left?.organizationId === right?.organizationId;
}

function sameSession(left, right) {
  return sameIdentity(left, right) && left?.token === right?.token && left?.refreshToken === right?.refreshToken;
}

function notifyAuthenticationRequired(expectedSession) {
  if (!sameSession(expectedSession, getSession())) return;
  clearSession();
  const event = typeof CustomEvent === 'function'
    ? new CustomEvent('fala-comigo:auth-required')
    : { type: 'fala-comigo:auth-required' };
  globalThis.window?.dispatchEvent?.(event);
}

export class APIClient {
  constructor({ baseUrl = globalThis.window?.PORTAL_API_BASE || DEFAULT_API_BASE } = {}) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.refreshPromises = new Map();
  }

  async request(path, { method = 'GET', body } = {}, canRefresh = true, operationId = requestId()) {
    const session = getSession();
    const headers = {
      accept: 'application/json',
      'x-request-id': operationId
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
      const currentSession = getSession();
      if (!sameIdentity(session, currentSession)) throw new Error('SESSION_CHANGED');
      const error = new Error(payload.error || `HTTP_${response.status}`);
      error.status = response.status;
      error.renewalRequired = payload.renewalRequired === true;
      if (response.status === 401 && canRefresh && error.renewalRequired) {
        try {
          // Another request may have already rotated the token before this 401 arrived.
          if (sameSession(session, currentSession)) await this.refreshSession(session);
          return this.request(path, { method, body }, false, operationId);
        } catch (_) {
          notifyAuthenticationRequired(session);
        }
      } else if (response.status === 401) {
        notifyAuthenticationRequired(session);
      }
      throw error;
    }
    if (!sameIdentity(session, getSession())) throw new Error('SESSION_CHANGED');
    return payload;
  }

  async refreshSession(expectedSession = getSession()) {
    const session = expectedSession;
    if (!sameSession(session, getSession())) throw new Error('SESSION_CHANGED');
    if (!session?.refreshToken) throw new Error('REFRESH_TOKEN_MISSING');
    if (this.refreshPromises.has(session.refreshToken)) return this.refreshPromises.get(session.refreshToken);
    const promise = (async () => {
      const response = await fetch(`${this.baseUrl}/v1/auth/refresh`, {
        method: 'POST',
        headers: { accept: 'application/json', 'content-type': 'application/json' },
        body: JSON.stringify({ refreshToken: session.refreshToken })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok || typeof payload.accessToken !== 'string' || typeof payload.refreshToken !== 'string') {
        if (!sameIdentity(session, getSession())) throw new Error('SESSION_CHANGED');
        const error = new Error(payload.error || 'REFRESH_TOKEN_INVALID');
        error.status = response.status;
        throw error;
      }
      if (!sameSession(session, getSession())) throw new Error('SESSION_CHANGED');
      saveSession({
        ...session,
        token: payload.accessToken,
        refreshToken: payload.refreshToken,
        accessTokenExpiresAt: payload.expiresIn ? Date.now() + payload.expiresIn * 1000 : undefined
      });
      return payload;
    })().finally(() => {
      this.refreshPromises.delete(session.refreshToken);
    });
    this.refreshPromises.set(session.refreshToken, promise);
    return promise;
  }

  async login(email, password) {
    const response = await fetch(`${this.baseUrl}/v1/auth/login`, {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(payload.error || 'INVALID_CREDENTIALS');
      error.status = response.status;
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

  carregarProfissionais(organizationId) {
    return this.request(`/v1/organizations/${encodeURIComponent(organizationId)}/memberships`);
  }

  convidarProfissional(organizationId, payload) {
    return this.request(`/v1/organizations/${encodeURIComponent(organizationId)}/invitations`, {
      method: 'POST',
      body: payload
    });
  }
}

export const apiClient = new APIClient();
