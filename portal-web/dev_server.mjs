import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const port = Number(process.env.PORT || 4173);
const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8'
};

const server = http.createServer(async (request, response) => {
  const requestPath = decodeURIComponent(new URL(request.url, `http://${request.headers.host}`).pathname);
  const safePath = normalize(requestPath).replace(/^\.\.(\/|\\|$)/, '');
  const candidate = join(root, safePath === '/' ? 'index.html' : safePath);
  const fallback = join(root, 'index.html');

  try {
    const filePath = extname(candidate) ? candidate : fallback;
    let body = await readFile(filePath);
    if (filePath.endsWith('index.html') && process.env.PORTAL_API_BASE) {
      const apiBase = JSON.stringify(process.env.PORTAL_API_BASE.replace(/\/$/, ''));
      body = Buffer.from(body.toString('utf8').replace(
        '</head>',
        `<script>window.PORTAL_API_BASE=${apiBase};</script></head>`,
      ));
    }
    response.writeHead(200, { 'content-type': contentTypes[extname(filePath)] || 'text/plain; charset=utf-8' });
    response.end(body);
  } catch (_) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
  }
});

server.listen(port, '0.0.0.0', () => {
  console.log(`Portal Web local: http://127.0.0.1:${port}`);
});
