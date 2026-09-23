# قالب python-api
REST API بمكتبات بايثون القياسية فقط + SQLite — لا يحتاج `pip install` لكي يعمل، وهذا مهم على Termux لأن بعض الحزم تحتاج ترجمة.

**التشغيل**

```bash
python3 app.py
PORT=3000 python3 app.py
sqlite3 data/app.db 'SELECT * FROM items ORDER BY id DESC LIMIT 5;'
```

**النقاط الجاهزة**: SQLite بوضع WAL، قفل خيط للكتابة، Rate limit لكل IP، تحقق من حجم/type البيانات، أخطاء JSON موحّدة، Health endpoint.

**لما تحتاج إطار عمل**: `pip install fastapi uvicorn` ثم انقل نفس دوال البيانات (`list_items`, `add_item` …) إلى مسار FastAPI — طبقة البيانات هنا مستقلة عن الخادم لهذا السبب.
