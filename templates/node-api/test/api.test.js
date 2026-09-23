'use strict';
/**
 * اختبارات سريعة تعمل بأدوات Node المدمجة (لا تحتاج Jest):
 *   npm test    ==   node --test
 */
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');

let child;
const PORT = 18099;
const BASE = `http://127.0.0.1:${PORT}`;

before(async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'td-test-'));
  child = spawn(process.execPath, [path.join(__dirname, '..', 'server.js')], {
    env: { ...process.env, PORT: String(PORT), DATA_DIR: tmp },
    stdio: 'ignore',
  });
  // انتظر حتى يردّ المنفذ
  for (let i = 0; i < 50; i++) {
    try {
      const r = await fetch(`${BASE}/api/health`);
      if (r.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('الخادم لم يبدأ');
});

after(() => child?.kill('SIGTERM'));

test('health يعيد ok', async () => {
  const h = await (await fetch(`${BASE}/api/health`)).json();
  assert.equal(h.status, 'ok');
});

test('دورة حياة العنصر: إنشاء ثم قائمة ثم حذف', async () => {
  const created = await (await fetch(`${BASE}/api/items`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: 'اختبار' }),
  })).json();
  assert.ok(created.id);

  const list = await (await fetch(`${BASE}/api/items`)).json();
  assert.equal(list.total, 1);

  const del = await fetch(`${BASE}/api/items/${created.id}`, { method: 'DELETE' });
  assert.equal(del.status, 204);
});

test('رفض عناوين فارغة وكبيرة', async () => {
  const bad = await fetch(`${BASE}/api/items`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ title: '' }),
  });
  assert.equal(bad.status, 422);
});

test('منع path traversal في الملفات الثابتة', async () => {
  const r = await fetch(`${BASE}/../server.js`);
  assert.ok([400, 403, 404].includes(r.status), 'يجب ألا يخدم ملفات خارج public/');
});

test('JSON غير صالح → 400', async () => {
  const r = await fetch(`${BASE}/api/items`, { method: 'POST', body: '{oops' });
  assert.equal(r.status, 400);
});
