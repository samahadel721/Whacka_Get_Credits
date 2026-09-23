# __PROJECT_NAME__

API + صفحة متابعة، بدون اعتماديات خارجية.

```bash
npm run dev      # يعمل مع --watch
npm test         # اختبارات node:test المدمجة
```

| المسار | الوصف |
|---|---|
| `GET /` | لوحة المتابعة |
| `GET /api/health` | حالة الخدمة (للفحص من Uptime monitoring) |
| `GET /api/items` | قائمة العناصر |
| `POST /api/items` | إضافة عنصر `{ "title": "..." }` |
| `DELETE /api/items/:id` | حذف عنصر |

الملفات تكتب في `data/items.json`. أضف `data/` إلى gitignore — لا ترفع بيانات تشغيلية.
