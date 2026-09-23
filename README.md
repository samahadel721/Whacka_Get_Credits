# termux-dev — بيئة تطوير كاملة على موبايلك

عدة scripts وقوالب تحوّل **Termux** على أندرويد إلى بيئة عمل حقيقية: تثبيت، فحص بيئة، قوالب مشاريع تشتغل فوراً، سيرفر تطوير على الشبكة المحلية، أنفاق للتجربة، ونسخ احتياطي على GitHub.

> كل ما هنا أدوات تطوير شرعية 100% — لا يحتوي (ولن يحتوي) على أي مولّد زيارات وهمية أو إنشاء حسابات بالجملة. التفاصيل في [خارج النطاق](#خارج-النطاق).

---

## 30 ثانية وتبدأ

### سطر واحد — نسخ ولصق في Termux (بلا `git`)

```bash
cd ~ && curl -L -o termux-dev.tar.gz \
  https://github.com/samahadel721/Whacka_Get_Credits/archive/refs/heads/arena/01a0cde9-whacka-get-credits.tar.gz \
  && tar xzf termux-dev.tar.gz \
  && cd Whacka_Get_Credits-arena-01a0cde9-whacka-get-credits && bash install.sh
```

مجرَّب حرفيًا: **57KB** تنزيل، **174KB** على القرص، و`install.sh` يكمّل التثبيت + `doctor` لوحده.
مساحتك ضيّقة؟ `bash install.sh --tools-only` · عايز تشغّل حاجة على طول؟ `bash install.sh --demo`.

### بلا `git` — نزّل حزمة جاهزة (~80KB)

أرشيف الملفات فقط، مش محتاج `git` خالص. جرّب الأوامر دي حرفيًا في Termux:

```bash
cd ~
curl -L -o termux-dev.zip \
  https://github.com/samahadel721/Whacka_Get_Credits/archive/refs/heads/arena/01a0cde9-whacka-get-credits.zip
unzip -q termux-dev.zip
cd Whacka_Get_Credits-arena-01a0cde9-whacka-get-credits
bash install.sh        # فحص الملفات + تثبيت الحزم + doctor
```

أو في أمر واحد يولّد مشروعًا ويشغّله فورًا: `bash install.sh --demo`

- تفضّل `tar.gz`؟ `curl -L -o termux-dev.tar.gz <نفس الرابط وابدّل .zip بـ .tar.gz>` ثم `tar xzf termux-dev.tar.gz`
- نزّلتها على الكمبيوتر وحطّيتها في الموبايل؟ `termux-setup-storage` ثم `cd ~/storage/shared` قبل `unzip`
- خيارات `install.sh`: `--check-only` (بلا تثبيت) · `--minimal` / `--tools-only` / `--python-only` / `--full` · `--demo`

### لو `git` متاح عندك

```bash
# 1) داخل Termux على الموبايل
pkg update -y && pkg install -y git
git clone -b arena/01a0cde9-whacka-get-credits \
  https://github.com/samahadel721/Whacka_Get_Credits.git ~/tools/termux-dev
cd ~/tools/termux-dev
#    (الشغل على الفرع ده؛ لما يتدمج في main احذف -b وكل اللي بعده)

# 2) التثبيت الكامل (حزم + إعدادات + مجلدات)
bash scripts/setup.sh -y        # أو: bash install.sh

# 3) تأكد إن البيئة سليمة
bash scripts/doctor.sh

# 4) أول مشروع
bash scripts/project.sh demo --template node-api
bash scripts/serve.sh ~/projects/demo
#    ثم افتح في متصفح الموبايل:  http://127.0.0.1:8080
```

لو التثبيت من GitHub بطيء عندك، راجع [تغيير مستودع الحزم](docs/INSTALL.md#مستودعات-الحزم-بطيئة).

`pkg install -y make` ثم `make help` يعطيك نفس الأوامر كاختصارات (`make setup`, `make doctor`, `make new NAME=app T=node-api`, `make test`).

---

## السكربتات

| الأمر | ماذا يفعل |
|---|---|
| `scripts/setup.sh [-y] [--minimal\|--python-only\|--tools-only]` | يثبّت الحزم، يضبط سطر مفاتيح Termux، `npm prefix`، aliases، مجلد `~/projects`، وهوية git. تكراره آمن. كل ملف تثبيت يعرض التقدير من apt قبل التنزيل. |
| `scripts/doctor.sh [--json]` | يفحص 15 نقطة (صلاحية التخزين، مساحة القرص، 16KB page size، سلامة dpkg، git identity، الشبكة…) ويعطيك سطر «الحل» لكل مشكلة. |
| `scripts/project.sh <name> -t <template>` | ينسخ قالباً جاهزاً، يستبدل الاسم، `git init` + أول commit. `--list` لعرض القوالب. |
| `scripts/serve.sh [dir] [--port]` | سيرفر تطوير على `0.0.0.0` ويطبع رابط الشبكة، يحجب `.env` و`.git` تلقائياً، ويرفض المسارات خارج المجلد. |
| `scripts/disk.sh [--plan\|--clean\|--project DIR\|--json]` | أرقام المساحة الحقيقية: حجم الريبو، ما يضيفه كل ملف تثبيت (محاكاة apt)، حالة القرص، والكاشات التي تنفّخ `$PREFIX`. |
| `scripts/serve.sh --stop / --status --port N` | يوقف/يكشف من يسمع على المنفذ — عبر `ss`/`lsof` إن وُجدا، وإلا بقراءة `/proc` مباشرة. يفيد لما يعلق سيرفر على الموبايل ويحتل المنفذ. |
| `scripts/tunnel.sh <port>` | رابط مؤقت للتجربة (cloudflared → ngrok → localtunnel → serveo حسب المتاح). |
| `scripts/backup.sh [--push] [--shared]` | `commit` + رفع GitHub + أرشيف `tar.gz` في `~/backups` أو مجلد التنزيلات. |

كل السكربتات في `scripts/lib/common.sh` تشترك في نفس الألوان والدوال، وتعمل أيضاً على Linux العادي (فوق Termux بـ `dry-run` للتحقق من المنطق).

---

## القوالب

```bash
bash scripts/project.sh myapp --template node-api      # REST API بدون أي npm install
bash scripts/project.sh myapp --template python-api    # بايثون قياسي + SQLite
bash scripts/project.sh myapp --template web-static    # موقع ثابت جاهز لـ GitHub Pages
```

كل قالب يشغّل **اختباراته** في نفس لحظة إنشائه — لا يوجد «كود لم نجربّه»:

| القالب | الاختبار |
|---|---|
| `node-api` | `npm test` → `node --test` (health، CRUD، رفض payload ضخم، منع path traversal) |
| `python-api` | `python3 -m unittest -v` (خادم فعلي على منفذ عشوائي) |
| `web-static` | بدون build — منطق `app.js` يعتمد `textContent` فقط لتفادي HTML injection |

ما يُبنى في القوالب وليس اختياريًا:

- **Rate limiting** بنافذة منزلقة لكل IP (`src/rateLimit.js` / `allowed()` في `app.py`).
- **حد لحجم جسم الطلب** (64KB) و`Limit` للصفحات (≤200) حتى لا ينهار السيرفر.
- **كتابة آمنة**: ملف JSON باسم مؤقت ثم `rename` (Node)، ووضع `WAL` في SQLite (Python).
- **رؤوس أمان** `X-Content-Type-Options` / `X-Frame-Options` / `Cache-Control: no-store` على الـ API.
- `.env` خارج Git دائمًا، والقيم من متغيّرات البيئة.

---

## توثيق

- [docs/INSTALL.md](docs/INSTALL.md) — التثبيت من الصفر على الموبايل، والمصادر الصحيحة للتطبيق.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — الأخطاء الأشهر وحلولها (انهيار الحزم، صلاحيات، Termux يتوقف في الخلفية…).
- [docs/CHEATSHEET.md](docs/CHEATSHEET.md) — أوامر Termux التي تختصر عليك يوم كامل.
- [docs/DEPLOY.md](docs/DEPLOY.md) — نقل مشروعك من الموبايل إلى سيرفر فعلي ونشره.

---

## كم مساحة كل ده؟

قِياس فعلي على هذا المستودع:

| البند | الحجم |
|---|---|
| ملفات المشروع (43 ملفًا / 3,583 سطر) | **156 KB** (159,200 بايت) |
| حزمة zip على GitHub (بلا `git`) | **80 KB** — وtar.gz **55 KB** |
| `.git` بالتاريخ كاملًا | **572 KB** في مستودع العمل، و**191 KB** في clone نظيف |
| الـ clone كاملًا على القرص | **453 KB** (أقل من 1MB) |
| مشروع تُولّده من قالب (`node-api`) | **18 KB** ملفات (11 ملفًا، بلا `node_modules`) — 185 KB على القرص مع `.git` بتاعه |
| Termux + bootstrap | **~120–180 MB** |
| `bash setup.sh` (ملف `full`: 17 حزمة) | **~330–450 MB** — منها nodejs-lts وحده ~120MB وpython ~70MB |
| `--tools-only` (11 حزمة، بدون Node/Python) | **~50 MB** |

الأرقام دي تقديرية للأحجام الكبيرة؛ عشان تاخد رقم جهازك بالضبط (قبل ما تنزّل أي حاجة):

```bash
bash scripts/disk.sh --plan          # يسأل apt نفسه: كم سيُضاف؟
pkg install -s nodejs-lts python     # أو مباشرة: «additional disk space will be used»
bash scripts/disk.sh                 # تقرير القرص + الكاشات التي يمكن تفريغها
bash scripts/disk.sh --clean         # يفرّغ كاش apt/npm ويطبع كم وفّرت
```

> لو مساحتك ضيقة: ثبّت `--tools-only` (git + أدوات أساسية)، وأضِ `nodejs-lts` أو `python` وقت ما تحتاجه فعلًا. الحزم دي أكبر مستهلك للمساحة، مش ملفات المشروع.

## خارج النطاق

اسم المستودع قديم، لكن المحتوى محدد: هذه أدوات **تطوير وبناء**. أي سكربت يرسل زيارات وهمية أو ينشئ حسابات مؤقتة لمنصة مكافآت خارجية ليس «مهارة تقنية» — هو مخالفة شروط استخدام وشكل من أشكال الاحتيال على نظام مالي يخص جهة أخرى، وعقوبته عادةً حظر دائم للأجهزة والـ IPs وأرقام الهواتف (وليس الحساب فقط) واسترداد الأرصدة، وفي بعض الدول تتجاوز القضية حدود الحظر الحسابي.

عمليًا، أغلب أنظمة الكريديت لا تُحتسب فيها «زيارة» بدون إشارات حقيقية (IP مكرّر، بصمة جهاز، وقت تفاعل، تحقق برقم هاتف)، فالفشل هو النتيجة المتوقعة وليس النجاح — والوقت الذي يُصرف على بناء الأداة أفضل في بناء منتجك.

**لو المنصة التي تقصدها مملوكة لك** فأنت تحتاج اختبار ضغط حقيقي لا زيارات وهمية، وهذا مشروع شرعي تمامًا وموجود في [docs/DEPLOY.md](docs/DEPLOY.md#اختبار-الضغط) — أأمر `k6`/`Locust` جاهزة لموقعك أنت.

**لو هدفك ربحًا من الإنترنت**: نفس الأدوات هنا تبني موقعًا/تطبيقًا يُنشر فعلاً (GitHub Pages، VPS، Cloudflare) — راجع [docs/DEPLOY.md](docs/DEPLOY.md).

---

## CI

اختبارات الأداة نفسها موجودة في `tests/run.sh` (130 تحققًا: تشغّل خوادم القوالب على منافذ عشوائية وتتأكد من الحمايات). لتشغيلها على كل push انقل ملف الـ workflow وفق [ci/README.md](ci/README.md).

## الترخيص

MIT. استخدمه وعدّله بحرية.
