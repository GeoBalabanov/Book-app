// Local dev server for Lexi Reader.
//   node server.mjs            → http://localhost:5173
// Serves the app the same way the Claude artifact host does (wrapping
// index.html in a minimal document) and proxies DeepL so the API key stays
// on the server. Put the key in web/.env (git-ignored):
//   DEEPL_API_KEY=your-key-here
// No dependencies; Node 18+.

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { extname, join, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deeplHost } from './js/translation/deepl-core.js';

const ROOT = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 5173);

function loadEnv() {
  const file = join(ROOT, '.env');
  if (!existsSync(file)) return;
  for (const line of readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (m && !line.trim().startsWith('#') && !(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}
loadEnv();
const KEY = process.env.DEEPL_API_KEY || '';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.epub': 'application/epub+zip',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
};

// Same skeleton the artifact host wraps around index.html.
const SKELETON_HEAD = '<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"><style>:root{padding:env(safe-area-inset-top,0px) 0 env(safe-area-inset-bottom,0px);color-scheme:light}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style></head><body>';

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks).toString('utf8');
}

async function deepl(req, res) {
  if (!KEY) { res.writeHead(503, { 'Content-Type': 'application/json' }); res.end('{"error":"DEEPL_API_KEY is not set in web/.env"}'); return; }
  let body;
  try { body = JSON.parse(await readBody(req)); } catch { res.writeHead(400); res.end('bad json'); return; }
  const allowed = ['text', 'source_lang', 'target_lang', 'context', 'tag_handling', 'formality', 'preserve_formatting'];
  const clean = Object.fromEntries(Object.entries(body).filter(([k, v]) => allowed.includes(k) && v !== undefined));
  const upstream = await fetch(`${deeplHost(KEY)}/v2/translate`, {
    method: 'POST',
    headers: { Authorization: `DeepL-Auth-Key ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(clean),
  });
  res.writeHead(upstream.status, { 'Content-Type': 'application/json' });
  res.end(await upstream.text());
}

createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/api/deepl/status') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ configured: !!KEY }));
      return;
    }
    if (url.pathname === '/api/deepl/translate' && req.method === 'POST') return await deepl(req, res);

    let path = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
    if (!path || path.endsWith('/')) path += 'index.html';
    const file = join(ROOT, path);
    if (!file.startsWith(ROOT) || path.startsWith('.env')) { res.writeHead(403); res.end(); return; }
    const st = await stat(file).catch(() => null);
    if (!st?.isFile()) { res.writeHead(404); res.end('Not found'); return; }
    let data = await readFile(file);
    if (path === 'index.html') data = Buffer.from(SKELETON_HEAD + data.toString('utf8') + '</body></html>');
    res.writeHead(200, { 'Content-Type': TYPES[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(data);
  } catch (e) {
    console.error(e);
    res.writeHead(500); res.end('Server error');
  }
}).listen(PORT, () => {
  console.log(`Lexi Reader → http://localhost:${PORT}`);
  console.log(KEY ? `DeepL: key loaded (${deeplHost(KEY).includes('free') ? 'Free' : 'Pro'} API)` : 'DeepL: no key (add DEEPL_API_KEY to web/.env). Add ?mock to the URL for demo translations.');
});
