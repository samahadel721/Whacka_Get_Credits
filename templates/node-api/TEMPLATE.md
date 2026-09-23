# قالب node-api
REST API صغير بدون أي اعتماديات خارجية — يعمل مباشرة بعد التثبيت (لا يحتاج npm install).

**لماذا بدون حزم؟** لأن تنزيل الحزم على الموبايل يستهلك بيانات ومساحة؛ ابدأ بالنواة (Node stdlib) ثم أضف express/fastify وقت ما تحتاج فعلاً.

**التشغيل**

```bash
node server.js                 # أو: npm run dev  (مع --watch لإعادة التشغيل)
PORT=3000 node server.js
bash ../../scripts/serve.sh .   # تشغيل من الـ toolkit + طباعة رابط الشبكة
```

**ما يحتويه**: أمان أساسي (helmet-like headers)، Rate limiting لكل IP، قراءة JSON بحجم محدود، SQLite-like store بسيط، Health endpoint جاهز للـ monitoring.
