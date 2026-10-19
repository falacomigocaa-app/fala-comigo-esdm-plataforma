import { clearSession, getSession } from './api/client.js';
import { hydrateClinicaScreen, renderClinicaScreen } from './screens/clinica_screen.js';
import { hydrateEscolaScreen, renderEscolaScreen } from './screens/escola_screen.js';
import { hydrateReportsView, renderReportsView } from './views/reports-view.js';
import { hydrateLoginView, renderLoginView } from './views/login-view.js';
import { hydrateAdminProfessionalsView, renderAdminProfessionalsView } from './views/admin-professionals-view.js';
import { hydrateBugReportView, renderBugReportView } from './views/bug-report-view.js';
import { checkBetaAccess } from './services/beta-gate.js';
import { trackTelemetry } from './services/telemetry.js';

const routes = new Set(['/login', '/clinica', '/escola', '/relatorios', '/admin/profissionais', '/reportar-bug']);
const appBasePath = (() => {
  const marker = '/portal';
  const index = window.location.pathname.indexOf(marker);
  return index >= 0 ? window.location.pathname.slice(0, index + marker.length) : '';
})();

function routeUrl(path) {
  return `${appBasePath}${path}` || '/';
}

function normalizedPath(pathname = window.location.pathname) {
  const relative = pathname.startsWith(appBasePath)
    ? pathname.slice(appBasePath.length)
    : pathname;
  const path = relative.replace(/\/+/g, '/').replace(/\/$/, '');
  return routes.has(path || '/login') ? path || '/login' : '/login';
}

export function createRouter({ root }) {
  let renderSerial = 0;
  let betaExpiredReported = false;

  function navigate(path) {
    const nextPath = normalizedPath(path);
    window.history.pushState({}, '', routeUrl(nextPath));
    render();
  }

  function handleAuthenticationRequired() {
    clearSession();
    window.history.replaceState({}, '', routeUrl('/login'));
    render();
  }

  window.addEventListener?.('fala-comigo:auth-required', handleAuthenticationRequired);

  async function render() {
    const serial = ++renderSerial;
    const betaStatus = await checkBetaAccess();
    if (serial !== renderSerial) return;
    if (!betaStatus.allowed) {
      root.innerHTML = renderBetaExpired(betaStatus.reason);
      if (!betaExpiredReported) {
        betaExpiredReported = true;
        trackTelemetry('beta_expired', { reason: betaStatus.reason });
      }
      return;
    }
    const session = getSession();
    let path = normalizedPath();
    trackTelemetry('screen_view', { screen: path });

    if (!session && path !== '/login') {
      path = '/login';
      window.history.replaceState({}, '', routeUrl(path));
    }
    if (session && path === '/login') {
      path = '/clinica';
      window.history.replaceState({}, '', routeUrl(path));
    }

    const context = {
      session,
      navigate,
      logout() {
        clearSession();
        navigate('/login');
      }
    };

    if (path === '/clinica') {
      root.innerHTML = renderClinicaScreen(context);
      hydrateClinicaScreen(context).catch((error) => {
        root.querySelector('[data-clinic-status]')?.replaceChildren(document.createTextNode(`Falha ao carregar a clínica: ${error.message}`));
      });
      return;
    }

    if (path === '/escola') {
      root.innerHTML = renderEscolaScreen(context);
      hydrateEscolaScreen(context).catch((error) => {
        root.querySelector('[data-school-status]')?.replaceChildren(document.createTextNode(`Falha ao carregar a escola: ${error.message}`));
      });
      return;
    }

    if (path === '/relatorios') {
      root.innerHTML = renderReportsView(context);
      hydrateReportsView(context).catch((error) => {
        root.querySelector('[data-report-status]')?.replaceChildren(document.createTextNode(`Falha ao carregar relatórios: ${error.message}`));
      });
      return;
    }

    if (path === '/admin/profissionais') {
      root.innerHTML = renderAdminProfessionalsView(context);
      hydrateAdminProfessionalsView(context).catch((error) => {
        root.querySelector('[data-admin-status]')?.replaceChildren(document.createTextNode(`Falha ao carregar administração: ${error.message}`));
      });
      return;
    }

    if (path === '/reportar-bug') {
      root.innerHTML = renderBugReportView(context);
      hydrateBugReportView(context);
      return;
    }

    root.innerHTML = renderLoginView(context);
    hydrateLoginView(context);
  }

  return { navigate, render };
}

function renderBetaExpired(reason) {
  const message = reason === 'clock_rollback'
    ? 'O relógio deste dispositivo parece ter sido alterado. Ajuste a data e a hora e conecte-se novamente.'
    : reason === 'not_started'
      ? 'O ciclo de avaliação ainda não começou.'
      : 'O período de avaliação selecionada terminou. Entre em contato com a equipe do beta para obter uma nova autorização.';
  return `<main class="beta-expired" role="alert"><h1>Avaliação beta indisponível</h1><p>${message}</p></main>`;
}
