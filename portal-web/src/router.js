import { clearSession, getSession } from './api/client.js';
import { renderAuthScreen } from './screens/auth_screen.js';
import { hydrateClinicaScreen, renderClinicaScreen } from './screens/clinica_screen.js';
import { hydrateEscolaScreen, renderEscolaScreen } from './screens/escola_screen.js';

const routes = new Set(['/login', '/clinica', '/escola']);

function normalizedPath(pathname = window.location.pathname) {
  const path = pathname.replace(/\/+/g, '/').replace(/\/$/, '');
  return routes.has(path || '/login') ? path || '/login' : '/login';
}

export function createRouter({ root }) {
  function navigate(path) {
    const nextPath = normalizedPath(path);
    window.history.pushState({}, '', nextPath);
    render();
  }

  function handleAuthenticationRequired() {
    clearSession();
    window.history.replaceState({}, '', '/login');
    render();
  }

  window.addEventListener?.('fala-comigo:auth-required', handleAuthenticationRequired);

  function render() {
    const session = getSession();
    let path = normalizedPath();

    if (!session && path !== '/login') {
      path = '/login';
      window.history.replaceState({}, '', path);
    }
    if (session && path === '/login') {
      path = '/clinica';
      window.history.replaceState({}, '', path);
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

    root.innerHTML = renderAuthScreen(context);
    root.querySelector('[data-auth-form]')?.addEventListener('submit', (event) => {
      event.preventDefault();
      const form = new FormData(event.currentTarget);
      const token = String(form.get('token') || '').trim();
      const userId = String(form.get('userId') || '').trim();
      const organizationId = String(form.get('organizationId') || '').trim();
      if (!token || !userId || !organizationId) return;
      window.localStorage.setItem('fala-comigo.portal.session', JSON.stringify({ token, userId, organizationId }));
      navigate('/clinica');
    });
  }

  return { navigate, render };
}
