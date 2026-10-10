import { renderActivateView, hydrateActivateView, renderAccountView, hydrateAccountView } from './views/account-views.js';
import { renderPatientsView, hydratePatientsView } from './views/patients-view.js';
import { clearSession, getSession } from './api/client.js';
import { hydrateClinicaScreen, renderClinicaScreen } from './screens/clinica_screen.js';
import { hydrateEscolaScreen, renderEscolaScreen } from './screens/escola_screen.js';
import { hydrateReportsView, renderReportsView } from './views/reports-view.js';
import { hydrateLoginView, renderLoginView } from './views/login-view.js';
import { hydrateAdminProfessionalsView, renderAdminProfessionalsView } from './views/admin-professionals-view.js';

const routes = new Set(['/login', '/clinica', '/escola', '/relatorios', '/admin/profissionais', '/pacientes', '/conta', '/ativar']);

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

    if (!session && !['/login','/ativar'].includes(path)) {
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

    if (path === '/ativar') { root.innerHTML = renderActivateView(); hydrateActivateView(); return; }
    if (path === '/conta') { root.innerHTML = renderAccountView(context); hydrateAccountView(context); return; }
    if (path === '/pacientes') {
      root.innerHTML = renderPatientsView(context);
      hydratePatientsView(context).catch(() => { root.querySelector('[data-access-status]').textContent = 'Não foi possível carregar pacientes e acessos.'; });
      return;
    }
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

    root.innerHTML = renderLoginView(context);
    hydrateLoginView(context);
  }

  return { navigate, render };
}
