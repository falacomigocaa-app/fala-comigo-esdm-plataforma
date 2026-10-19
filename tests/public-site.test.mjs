import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const siteRoot = path.join(repoRoot, 'site');
const publishedPages = [
  'index.html',
  'privacy.html',
  'portal.html',
  'console-preview.html',
  'rh/index.html',
];

function readSiteFile(relativePath) {
  return readFileSync(path.join(siteRoot, relativePath), 'utf8');
}

test('all local links and assets in published HTML resolve inside the Pages payload', () => {
  for (const relativePage of publishedPages) {
    const html = readSiteFile(relativePage);
    const references = html.matchAll(/(?:href|src)=["']([^"']+)["']/gi);

    for (const [, reference] of references) {
      if (!reference) continue;
      if (/^(?:mailto:|tel:|javascript:|data:)/i.test(reference)) continue;

      const target = new URL(reference, `https://pages-check.invalid/${relativePage}`);
      if (target.origin !== 'https://pages-check.invalid') continue;
      if (relativePage === 'index.html' && target.pathname === '/app/') continue;

      let targetPath = path.resolve(siteRoot, `.${decodeURIComponent(target.pathname)}`);
      assert.ok(
        targetPath === siteRoot || targetPath.startsWith(`${siteRoot}${path.sep}`),
        `${relativePage} links outside the Pages payload: ${reference}`,
      );
      if (targetPath === siteRoot || target.pathname.endsWith('/')) {
        targetPath = path.join(targetPath, 'index.html');
      }
      assert.ok(existsSync(targetPath), `${relativePage} points to missing file: ${reference}`);

      if (target.hash && targetPath.endsWith('.html')) {
        const targetHtml = readFileSync(targetPath, 'utf8');
        const targetIds = new Set(
          [...targetHtml.matchAll(/\b(?:id|name)=["']([^"']+)["']/gi)].map(([, id]) => id),
        );
        const fragment = decodeURIComponent(target.hash.slice(1));
        assert.ok(
          targetIds.has(fragment),
          `${relativePage} points to missing anchor: ${reference}`,
        );
      }
    }
  }
});

test('public app preview maps to the Flutter build at the Pages /app route', () => {
  const home = readSiteFile('index.html');
  const workflow = readFileSync(
    path.join(repoRoot, '.github/workflows/site-pages.yml'),
    'utf8',
  );
  assert.match(home, /href="app\/"/i);
  assert.ok(
    workflow.includes('flutter build web --release --base-href /fala-comigo-esdm-plataforma/app/'),
    'Pages workflow must build Flutter Web with the project /app base path',
  );
  assert.ok(
    workflow.includes('cp -a build/web/. public/app/'),
    'Pages workflow must publish Flutter Web at /app/',
  );
});

test('portal preview labels synthetic, non-interactive content clearly', () => {
  const portal = readSiteFile('portal.html');
  assert.match(portal, /Prévia estática com dados sintéticos/i);
  assert.match(portal, /botões não executam ações/i);
  assert.match(portal, /Contrato de domínio \(GitHub\)/);
  assert.doesNotMatch(portal, /href=["']\.\.\/docs\//i);
  const buttons = [...portal.matchAll(/<button\b[^>]*>/gi)].map(([button]) => button);
  assert.ok(buttons.length > 0, 'portal preview should contain illustrative controls');
  assert.ok(buttons.every((button) => /\bdisabled\b/i.test(button)));
});

test('RH synthetic-data badge remains visible on narrow screens', () => {
  const css = readFileSync(path.join(siteRoot, 'rh/styles.css'), 'utf8');
  assert.doesNotMatch(css, /\.environment-badge\{display:none\}/i);
  assert.match(css, /\.environment-badge\{display:inline-flex/i);
});

test('portal preview does not display stale sample calendar dates', () => {
  const portal = readSiteFile('portal.html');
  assert.doesNotMatch(portal, /Até 24\/09|Até 25\/09|amanhã às 14:00|Revisão em 20\/10/i);
});

test('homepage clearly labels pre-release status and synthetic-only use', () => {
  const home = readSiteFile('index.html');
  assert.match(home, /Prévia de validação — ainda não é um lançamento público/i);
  assert.match(home, /use somente dados sintéticos/i);
  assert.match(home, /segurança do armazenamento/i);
  assert.match(home, /Nenhum portal conectado ou piloto está ativo/i);
  assert.doesNotMatch(home, /<a href="portal\.html">Portal piloto<\/a>/i);
});

test('published privacy policy is accessible, canonical, and Web-specific', () => {
  const policy = readSiteFile('privacy.html');
  const repositoryCopy = readFileSync(path.join(repoRoot, 'privacy_policy.html'), 'utf8');
  assert.match(policy, /class="skip-link"/i);
  assert.match(policy, /id="conteudo"/i);
  assert.match(policy, /não foram validados para dados pessoais ou de saúde/i);
  assert.match(policy, /não use a prévia Web para armazenar dados pessoais ou sensíveis/i);
  assert.match(policy, /Não envie por e-mail, WhatsApp ou issues públicas/i);
  assert.match(repositoryCopy, /política canônica/i);
});

test('public FAQ describes the generated validation APK without claiming release availability', () => {
  const home = readSiteFile('index.html');
  assert.match(home, /APK de validação para Android foi gerado/i);
  assert.match(home, /não foi testado em aparelho real nem distribuído em lojas/i);
  assert.doesNotMatch(home, /preparação do primeiro build/i);
  assert.match(
    home,
    /href="https:\/\/github\.com\/falacomigocaa-app\/fala-comigo\/blob\/main\/docs\/MANUAL_DO_USUARIO\.md"/i,
  );
});
