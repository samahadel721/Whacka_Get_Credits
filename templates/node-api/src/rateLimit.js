'use strict';
/**
 * Rate limiting بحركة النافذة المنزلقة (sliding window) لكل IP.
 * الغرض: حماية السيرفر من الضغط العنيف/سوء الاستخدام — وليس بديلاً عن حماية على مستوى الشبكة.
 * الذاكرة O(number of IPs) مع تنظيف دوري.
 */
function rateLimit({ windowMs = 60_000, max = 120, cleanupMs = 5 * 60_000 } = {}) {
  const hits = new Map();

  const sweep = setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [key, arr] of hits) {
      while (arr.length && arr[0] <= cutoff) arr.shift();
      if (!arr.length) hits.delete(key);
    }
  }, cleanupMs);
  if (typeof sweep.unref === 'function') sweep.unref();

  return function check(ip) {
    const now = Date.now();
    const arr = hits.get(ip) || [];
    const cutoff = now - windowMs;
    while (arr.length && arr[0] <= cutoff) arr.shift();

    if (arr.length >= max) {
      hits.set(ip, arr);
      return { allowed: false, remaining: 0, retryAfterMs: arr[0] + windowMs - now };
    }
    arr.push(now);
    hits.set(ip, arr);
    return { allowed: true, remaining: max - arr.length, retryAfterMs: 0 };
  };
}

module.exports = { rateLimit };
