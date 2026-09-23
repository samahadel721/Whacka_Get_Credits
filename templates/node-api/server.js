'use strict';
/**
 * __PROJECT_NAME__ — خادم REST بسيط بدون اعتماديات خارجية.
 * مصمَّم ليعمل على Termux (Node LTS) وعلى أي سيرفر Linux بنفس الكود.
 */
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const { createStore } = require('./src/store');
const { rateLimit } = require('./src/rateLimit');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const PUBLIC_DIR = process.env.PUBLIC_DIR || path.join(__dirname, 'public');
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const MAX_BODY = 64 * 1024; // 64KB — احمِ نفسك من أجسام الطلب الضخمة

const store = createStore(path.join(DATA_DIR, 'items.json'));
const limiter = rateLimit({
  windowMs: 60_000,
  max: Number(process.env.RATE_LIMIT_PER_MIN || 120),
});

/* ------------------------------ أدوات مساعدة ------------------------------ */
const log = (...a) => console.log(new Date().toISOString(), ...a);

function send(res, status, body, headers = {}) {
  const payload = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, {
    'content-type': typeof body === 'object' && !Buffer.isBuffer(body) ? 'application/json; charset=utf-8' : 'text/plain; charset=utf-8',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'cache-control': 'no-store',
    ...headers,
  });
  res.end(payload);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(Object.assign(new Error('payload_too_large'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      if (!chunks.length) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(Object.assign(new Error('invalid_json'), { status: 400 }));
      }
    });
    req.on('error', reject);
  });
}

const clientIp = (req) =>
  (req.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
  req.socket.remoteAddress ||
  'unknown';

/* -------------------------------- الـ API -------------------------------- */
async function handleApi(req, res, url) {
  const [, section, id] = url.pathname.split('/').filter(Boolean); // api / items / :id

  if (section === 'health') {
    return send(res, 200, {
      status: 'ok',
      uptimeSec: Math.round(process.uptime()),
      items: store.count(),
      node: process.version,
      pid: process.pid,
    });
  }

  if (section !== 'items') return send(res, 404, { error: 'not_found' });

  if (req.method === 'GET' && !id) return send(res, 200, { items: store.list(), total: store.count() });
  if (req.method === 'GET' && id) {
    const item = store.get(id);
    return item ? send(res, 200, item) : send(res, 404, { error: 'not_found' });
  }

  if (req.method === 'POST') {
    const body = await readJson(req);
    const title = String(body.title ?? '').trim();
    if (!title || title.length > 200) {
      return send(res, 422, { error: 'title_required', hint: 'title مطلوب (1..200 حرف)' });
    }
    const item = store.create({ title, meta: body.meta ?? null });
    return send(res, 201, item, { location: `/api/items/${item.id}` });
  }

  if (req.method === 'DELETE' && id) {
    return store.remove(id) ? send(res, 204, '') : send(res, 404, { error: 'not_found' });
  }

  return send(res, 405, { error: 'method_not_allowed' }, { allow: 'GET, POST, DELETE' });
}

/* ----------------------- ملفات ثابتة آمنة (من ./public) ----------------------- */
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

function serveStatic(res, url) {
  const rel = decodeURIComponent(url.pathname === '/' ? 'index.html' : url.pathname.slice(1));
  const abs = path.resolve(PUBLIC_DIR, rel);
  // منع الخروج من المجلد (path traversal)
  if (!abs.startsWith(PUBLIC_DIR + path.sep) && abs !== PUBLIC_DIR) {
    return send(res, 403, { error: 'forbidden' });
  }
  if (path.basename(abs).startsWith('.')) return send(res, 403, { error: 'forbidden' });
  fs.readFile(abs, (err, buf) => {
    if (err) return send(res, 404, { error: 'not_found' });
    send(res, 200, buf, { 'content-type': MIME[path.extname(abs).toLowerCase()] || 'application/octet-stream' });
  });
}

/* -------------------------------- الخادم -------------------------------- */
const server = http.createServer(async (req, res) => {
  const started = process.hrtime.bigint();
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const ip = clientIp(req);

  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - started) / 1e6;
    log(`${req.method} ${url.pathname} → ${res.statusCode} (${ms.toFixed(1)}ms) ${ip}`);
  });

  const check = limiter(ip);
  if (!check.allowed) {
    return send(res, 429, { error: 'rate_limited', retryAfterSec: Math.ceil(check.retryAfterMs / 1000) },
      { 'retry-after': String(Math.ceil(check.retryAfterMs / 1000)) });
  }

  try {
    if (url.pathname.startsWith('/api/')) return await handleApi(req, res, url);
    if (req.method === 'GET' || req.method === 'HEAD') return serveStatic(res, url);
    return send(res, 405, { error: 'method_not_allowed' });
  } catch (e) {
    log('error', e.message);
    return send(res, e.status || 500, { error: e.status ? e.message : 'internal_error' });
  }
});

server.listen(PORT, HOST, () => {
  log(`✅ __PROJECT_NAME__ يعمل على http://${HOST}:${PORT}  (token: ${crypto.randomBytes(4).toString('hex')})`);
});

const shutdown = (sig) => {
  log(`${sig} — إغلاق آمن`);
  server.close(() => process.exit(0));
  // fetch/axios يبقيان keep-alive مفتوحًا، فينتظر server.close() للأبد.
  // نغلق الصلات الخاملة ثم كلها، مع سقف زمني مضمون الخروج.
  if (typeof server.closeIdleConnections === "function") server.closeIdleConnections();
  setTimeout(() => server.closeAllConnections?.(), 200);
  setTimeout(() => process.exit(1), 2000).unref();
};
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
