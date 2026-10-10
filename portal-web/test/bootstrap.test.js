import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');

test('bootstrap web usa caminhos absolutos para funcionar em rotas profundas', async () => {
  const [html, main] = await Promise.all([
    readFile(resolve(root, 'index.html'), 'utf8'),
    readFile(resolve(root, 'src/main.js'), 'utf8'),
  ]);

  assert.match(html, /href="\/src\/styles\.css"/u);
  assert.match(html, /src="\/src\/main\.js"/u);
  assert.doesNotMatch(main, /import\s+['"]\.\/styles\.css['"]/u);
});
