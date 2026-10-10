import { createRouter } from './router.js';
import { clearSession } from './api/client.js';

const root = document.querySelector('#app');

if (!root) {
  throw new Error('Elemento #app não encontrado.');
}

const router = createRouter({ root });

window.addEventListener('popstate', () => router.render());

document.addEventListener('click', (event) => {
  const link = event.target.closest('[data-route]');
  if (link) {
    event.preventDefault();
    router.navigate(link.dataset.route);
    return;
  }
  if (event.target.closest('[data-logout]')) {
    clearSession();
    router.navigate('/login');
  }
});

router.render();
