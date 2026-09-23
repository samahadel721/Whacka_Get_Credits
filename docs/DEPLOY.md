# من الموبايل إلى سيرفر حقيقي

الموبايل ممتاز للكتابة والتجربة، وسيئ للاستضافة: اتصال خلف NAT/CGNAT بلا IP عام، البطارية والحرارة، وأندرويد يقتل العملية الطويلة. القاعدة: **اكتب على Termux، وانشر على سيرفر**.

## 1) جهّز المستودع
```bash
cd ~/projects/demo
bash ../../tools/termux-dev/scripts/backup.sh            # commit + أرشيف محلي
gh repo create demo --private --source . --push           # أو من الموقع ثم git push
```

## 2) استضافة مجانية/رخيصة حسب نوع المشروع

| المشروع | أنسب خيار | ملاحظة |
|---|---|---|
| `web-static` | GitHub Pages / Cloudflare Pages | صفر تكلفة، نشر بـ push |
| `node-api` | Fly.io / Railway / Render | `fly launch` يكفي غالبًا |
| `python-api` (SQLite) | VPS صغير + systemd + Caddy | SQLite مناسب لتطبيق واحد؛ لا تستخدمه مع نسخ متعددة |
| API عام + مستخدمون حقيقيون | VPS + Postgres | انسخ `.env` يدويًا ولا ترفعه أبدًا |

مثال Node على Fly:
```bash
fly launch --no-deploy && fly secrets set RATE_LIMIT_PER_MIN=120 && fly deploy
```

مثال systemd على VPS (يُكتب على السيرفر):
```ini
[Unit]
Description=demo api
After=network.target

[Service]
User=www-data
WorkingDirectory=/srv/demo
EnvironmentFile=/srv/demo/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=2
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload && sudo systemctl enable --now demo
sudo journalctl -u demo -f
```

## 3) بعد النشر — افحصه كما يفحصه المستخدم
```bash
curl -s https://your-app.example/api/health | jq .
curl -s -o /dev/null -w 'TTFB %{time_starttransfer}s · %{http_code}\n' https://your-app.example/
```
تحقق من A+ أمانًا على <https://securityheaders.com> ومن الأداء على <https://pagespeed.web.dev>.

---

## اختبار الضغط

هذا هو البديل الشرعي لـ«توليد زيارات» لو كنت تختبر **خدمتك أنت**: تحميل نظامك بزوار حقيقيين مُنسَّقين لمعرفة أين ينكسر.

> **شرط مطلق**: فقط على أنظمة تملكها أو لديك إذن خطي باختبارها. الضغط على ملك الغير = إتاحة خدمة ممنوعة وقد تُفهم كـ DDoS.

### Locust (Python — مناسب للتشغيل من Termux)
```bash
pip install --user locust
```
```python
# loadtest/locustfile.py
from locust import HttpUser, task, between

class Visitor(HttpUser):
    wait_time = between(1, 3)          # سلوك مستخدم حقيقي، ليس إغراقًا

    @task(5)
    def home(self):
        self.client.get("/")

    @task(3)
    def items(self):
        self.client.get("/api/items?limit=20")

    @task(1)
    def create(self):
        self.client.post("/api/items", json={"title": "من اختبار الضغط"})
```
```bash
locust -f loadtest/locustfile.py --host http://127.0.0.1:8080 \
       --headless -u 50 -r 5 -t 60s --csv results
```

### k6 (أعلى أداءً — شغّله على السيرفر لا الموبايل)
```js
// loadtest/k6.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },   // تدفئة
    { duration: '2m',  target: 100 },  // حمل الذروة
    { duration: '30s', target: 0 },    // انحدار
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],     // أقل من 1% أخطاء
    http_req_duration: ['p(95)<400'],   // 95% من الطلبات أقل من 400ms
  },
};

export default function () {
  const r = http.get(`${__ENV.BASE_URL}/api/health`);
  check(r, { ok: (res) => res.status === 200 });
  sleep(1);
}
```
```bash
BASE_URL=https://your-app.example k6 run loadtest/k6.js
```

### ماذا تقيس فعلًا
| المؤشر | المقصود | علامة الخطر |
|---|---|---|
| p95 latency | زمن الاستجابة عند الذروة | `p(95)` يقفز مع تزايد المستخدمين ⇒ عنق اختناق قاعدة بيانات |
| error rate | نسبة الطلبات الفاشلة | `429` متكرر = الـ rate limit يضرب مبكرًا؛ `5xx` = استثناء في الكود |
| Throughput | طلب/ثانية قابل للخدمة | تسطّح مبكر (plateau) ⇒ CPU-bound أو اتصال DB محدود |
| Memory/RSS | استهلاك الذاكرة | نمو مستمر = تسريب؛ أعد الاستخدام مع `--inspect` |

بعد كل تشغيل: اضبط `RATE_LIMIT_PER_MIN` على أساس النتيجة الحقيقية، واستخدم مؤشرات (`/api/health` + monitoring) بدل التخمين.
