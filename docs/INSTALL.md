# التثبيت على Termux (من الصفر)

## 0) احصل على Termux من المصدر الصحيح — أهم خطوة

**لا تثبّت Termux من Google Play**: النسخة هناك قديمة وموقوفة التطوير، وتسبب انهيار أغلب الحزم على أندرويد 14/15/16.

المصادر الصحيحة:

1. **GitHub Releases** (الموصى به): <https://github.com/termux/termux-app/releases> — اختر `Termux-app_v0.118.x+...-arm64-v8a.apk` (الأحدث).
2. **F-Droid**: <https://f-droid.org/packages/com.termux/>

> تحديث من Play إلى نسخة GitHub يستلزم حذف التطبيق (ستفقد بياناته)، لذا ابدأ بالنسخة الصحيحة.

### خطأ «CANNOT LINK EXECUTABLE … page size 16384»
أجهزتك الحديثة (خصوصًا بيكسل/سامسونج 2024+) تستخدم ذاكرة 16KB. الحل: أحدث إصدار من termux-app (يدعم 16KB) ثم:

```bash
pkg upgrade -y
```

---

## 0.5) احسب المساحة قبل ما تنزّل

مشروع termux-dev نفسه صغير جدًا (أقل من 1MB مع التاريخ)؛ المساحة فعليًا بتروحه على **حزم Termux**. قبل التثبيت اسأل apt نفسه:

```bash
bash scripts/disk.sh --plan          # جدول مقارنة بين ملفات التثبيت
bash scripts/disk.sh --plan minimal   # أو ملف معين
df -h ~                              # كم فاضل عندك فعلًا
```

الأرقام المرجّعية (aarch64، تقريبية):

| البند | تنزيل | على القرص |
|---|---|---|
| Termux app + bootstrap | ~110MB | ~120–180MB |
| `tools` (git, curl, wget, ripgrep, jq, zip/unzip/tar, openssh, nano) | ~25MB | ~45–60MB |
| `nodejs-lts` | ~35MB | ~110–130MB |
| `python` + `python-pip` | ~18MB | ~65–80MB |
| `tmux tree fd` | ~3MB | ~8MB |
| **الإجمالي لملف `full`** | **~80MB** | **~330–420MB** |

نصائح التوفير:

- `bash scripts/setup.sh --tools-only` ثم `pkg install -y nodejs-lts` لما تبدأ مشروع Node فعلًا.
- بعد كل `pkg upgrade`: `bash scripts/disk.sh --clean` (يفرّغ كاش apt وnpm ويطبع كم وفّرت).
- `node_modules` بياخد 2–6MB للحزمة الواحدة وبيكبر بسرعة؛ امسحه لما مش محتاجه: `bash scripts/disk.sh --project ~/projects/myapp` بيورّيك الحجم أولًا.
- لو الموبايل أقل من 2GB حرة، بلا `proot-distro` (التوزيعة وحدها 1GB+).

> أعمدة «تنزيل/قرص» دي لتقدير الخطة فقط؛ `disk.sh --plan` بيجيب رقم جهازك من apt مباشرة.

---

## 1) التجهيز الأساسي داخل التطبيق

```bash
termux-setup-storage          # اقبل نافذة الإذن ليظهر ~/storage/shared
pkg update -y && pkg upgrade -y
```

## 2) مستودعات الحزم بطيئة
من مصر/الخليج المستودع الافتراضي قد يكون بعيدًا.

```bash
termux-change-repo
# اختر مرآة «GitHub» أو أقرب مرآة أوروبية، ثم:
pkg update -y
```

تحقّق من الوصول:

```bash
curl -I -m 8 https://packages.termux.dev
```

## 3) شغّل عدة سكربتات
```bash
pkg install -y git
git clone <رابط-مستودعك> ~/tools/termux-dev
cd ~/tools/termux-dev
bash scripts/setup.sh -y
bash scripts/doctor.sh
```

---

## 4) أوقف قتل أندرويد للعملية (ضروري)

أندرويد يوقف Termux لتوفير البطارية فينقطع أي سيرفر أو تنزيل طويل.

1. **السطر الأول دائمًا**: `termux-wake-lock` (أو `pkg install -y termux-api` ثم `termux-wake-lock`).
2. **إعدادات البطارية**: Settings → Apps → Termux → Battery → **Unrestricted / No restrictions**.
3. **قفل التطبيق في Recent apps** (اسحب Termux للأسفل/اضغط القفل).
4. اختياري عبر adb (من كمبيوتر):
   ```bash
   adb shell dumpsys deviceidle whitelist +com.termux
   ```

للمهام الأطول من عمر البطارية: لا تُشغّلها على الموبايل — انشرها على سيرفر (راجع [DEPLOY.md](DEPLOY.md)).

---

## 5) راحة الاستخدام

`~/.termux/termux.properties` يُضبط تلقائيًا بواسطة `setup.sh`، ويتضمن سطر مفاتيح:

```
extra-keys = [[ESC,TAB,CTRL,ALT,{,},|],[PGUP,UP,PGDN,LEFT,DOWN,RIGHT,HOME]]
```

تكبير الخط: اسحب بإصبعين، أو `font-size = 18` في نفس الملف ثم `termux-reload-settings`.

سحب/لصق: ضغطة مطوّلة → Tap to select → `termux-clipboard-set`، وخارجيًا `termux-open-url <url>`.

---

## 6) بدائل أقوى من الموبايل نفسه

- **proot-distro** — توزيعة Linux كاملة بأدوات apt:
  ```bash
  pkg install -y proot-distro
  proot-distro install ubuntu
  proot-distro login ubuntu
  ```
- **Termux + SSH من لابتوب**: `pkg install -y openssh && sshd` ثم من الكمبيوتر `ssh -p 8022 u0_aXXX@<ip الموبايل>` (استخدم `ifconfig` أو مودم الواي فاي لمعرفة الـ IP).
- **VPS رخيص** للمهام الجادة: راجع [DEPLOY.md](DEPLOY.md).
