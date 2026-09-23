'use strict';
/**
 * تخزين JSON بسيط على القرص مع كتابة ذرية (atomic) — يناسب التطبيقات الصغيرة.
 * لما تكبر: استبدله بـ SQLite (node:sqlite في Node ≥22) أو Postgres — واجهة API هنا تبقى كما هي.
 */
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function createStore(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });

  let cache;
  const load = () => {
    if (cache) return cache;
    try {
      cache = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      cache = { items: [] };
    }
    if (!Array.isArray(cache.items)) cache.items = [];
    return cache;
  };

  const flush = () => {
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(load(), null, 2));
    fs.renameSync(tmp, file); // rename ذري: لا يفسد الملف لو انقطع التيار
  };

  return {
    file,
    list: () => load().items.slice(),
    count: () => load().items.length,
    get: (id) => load().items.find((i) => i.id === id) || null,
    create({ title, meta = null }) {
      const item = {
        id: crypto.randomUUID(),
        title,
        meta,
        createdAt: new Date().toISOString(),
      };
      load().items.unshift(item);
      // سقف معقول حتى لا ينفخ الملف بلا حد
      if (load().items.length > 5000) load().items.length = 5000;
      flush();
      return item;
    },
    remove(id) {
      const items = load().items;
      const next = items.filter((i) => i.id !== id);
      if (next.length === items.length) return false;
      load().items = next;
      flush();
      return true;
    },
  };
}

module.exports = { createStore };
