# __PROJECT_NAME__

API بمكتبات بايثون القياسية + SQLite.

```bash
python3 app.py                 # http://0.0.0.0:8080
python3 -m unittest -v         # اختبارات الدخان
```

| المسار | الطريقة | الوظيفة |
|---|---|---|
| `/api/health` | GET | حالة الخدمة |
| `/api/items?limit=50&offset=0` | GET | قائمة مع ترقيم |
| `/api/items` | POST | إضافة `{"title":"..."}` |
| `/api/items/:id` | GET / PATCH / DELETE | قراءة / تبديل done / حذف |

ملاحظة: `data/app.db` خارج Git لأنه بيانات تشغيلية حقيقية.
