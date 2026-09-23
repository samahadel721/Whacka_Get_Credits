# استكشاف الأخطاء

شغّل أول شيء: `bash scripts/doctor.sh` — أغلب هذه الحالات يفحصها تلقائيًا ويعطيك الحل.

| الرسالة | السبب | الحل |
|---|---|---|
| `CANNOT LINK EXECUTABLE "…": library "libc++_shared.so" not found` | حزم قديمة بعد ترقية أندرويد | `pkg upgrade -y` ثم `pkg reinstall -y <الحزمة>` |
| `proot error: 'sh' not found` أو انهيار فوري | Termux من Play Store | احذفه وثبّت من [GitHub Releases](https://github.com/termux/termux-app/releases) |
| `permission denied` على أمر بعد `pkg install` | صلاحيات الملفات داخل `$PREFIX/bin` مكسورة | `chmod -R u+x $PREFIX/bin` |
| `Unable to lock the download directory` | عمليتا `pkg/apt` تعملان معًا | `ps -A \| grep -E 'apt\|dpkg'` ثم `pkill -f apt`، وإن استمر: `rm -f $PREFIX/var/lib/dpkg/lock*` |
| `EACCES: permission denied` في `npm install -g` | npm يكتب في نظام الجذور | `npm config set prefix $HOME/.npm-global` + `export PATH=$HOME/.npm-global/bin:$PATH` (setup.sh يفعله) |
| `error: externally-managed-environment` في pip | حماية بايثون الحديثة | لبيئة معزولة: `python3 -m venv .venv && source .venv/bin/activate`، أو `pip install --user` |
| لا يظهر `~/storage` | صلاحية التخزين مرفوضة | `termux-setup-storage` واقبل النافذة، ثم أعد تشغيل التطبيق |
| `open failed: EACCES` عند كتابة ملف في Downloads | أندرويد 11+ يقيّد الكتابة خارج مجلداتك | استخدم `~/storage/shared/Download/` ولا تكتب في جذر الذاكرة |
| `curl: (6) Could not resolve host` | DNS/طيران/VPN | `ping -c 2 1.1.1.1`؛ لو نجح فالمشكلة DNS: جرّب شبكة أخرى أو `termux-change-repo` |
| `No space left on device` | ممتلئ | `pkg clean -y && npm cache clean --force && rm -rf ~/.cache ~/.npm/_cacache` ثم `df -h ~` |
| `address already in use ::8080` | المنفذ مشغول (غالبًا سيرفر سابق لم يمت) | `bash scripts/serve.sh --status --port 8080` لمعرفة القاتل، ثم `bash scripts/serve.sh --stop --port 8080` أو `make stop PORT=8080` |
| الجهاز لا يفتح رابط الشبكة رغم تشغيل السيرفر | «عزل العملاء» في الراوتر (AP Isolation) أو شبكة ضيف | جرّب hotspot من موبايل آخر، أو استخدم الموبايل نفسه `http://127.0.0.1:PORT`، أو `scripts/tunnel.sh` |
| السيرفر يتوقف بعد دقائق | البطارية Optimization قتلت Termux | `termux-wake-lock` + عدم تقييد البطارية (راجع [INSTALL.md](INSTALL.md#4-أوقف-قتل-أندرويد-للعملية-ضروري)) |
| `git: ... Author identity unknown` | لا هوية في git | `git config --global user.name "اسمك" && git config --global user.email "you@mail.com"` |
| `gh: To use GitHub CLI in Termux` لا يعمل للتسجيل | متصفح غير موثّق | استخدم Token: أنشئ **Fine-grained PAT** من الموقع ثم `export GH_PAT=...` (`echo $GH_PAT \| gh auth login --with-token`) |
| بايثون لا يجد `sqlite3` | حزمة ناقصة | `pkg install -y python` (sqlite ضمن المكتبة القياسية) أو `pkg install -y sqlite` لواجهة الطرف السطر |

> `--stop` يعمل بدون `ss` أو `lsof` أيضًا: يقرأ `/proc/net/tcp` ويطابق الـ inode بمفاتح `/proc/<pid>/fd`، لذا يشتغل على Termux مجرد من أي حزمة. لو كانت العملية تخص مستخدمًا آخر (سيرفر systemd مثلاً) ستحتاج `sudo` أو إيقافها من مدير الخدمات.

| سكربت يتوقف في منتصفه **بدون أي رسالة** | `set -u` يقابل متغيّرًا غير مضبوط (رسالتها تُبتلع لو كان الخطأ داخل `$( )`)، أو أمر فرعي قرأ stdin أثناء تشغيل السكربت بأنبوب مثل `curl … \| bash` | شغّل `bash -x script.sh \| tail -20`، واستخدم `bash script.sh` بدل الأنبوب، ومرّر `</dev/null` للأوامر الداخلية |

## السلوك الغريب في Termux تحديدًا
- **الشاشة تنطفئ ⇒ العملية تتوقف**: `termux-wake-lock` ضروري، ويمكن `termux-wake-unlock` عند الانتهاء.
- **الأرقام/الأسهم تُدخل محارف غريبة**: أنت في «insert mode» أو بدون `extra-keys` — أعد تشغيل `termux-reload-settings`.
- **لوحة المفاتيح تختفي**: اذهب `Volumes up + down` سويًا (أو اسحب شريط Termux للأسفل) لتبديل لوحة النظام.
- **لا يمكنك لصق مفتاح SSH**: `termux-clipboard-set` لنسخه ثم لصقه من لوحة المفاتيح.

## لو السكربت نفسه فشل
كل السكربتات `set -euo pipefail` وتتوقف عند أول خطأ بدون آثار جانبية كبيرة. لإصلاح يدوي:

```bash
bash -x scripts/setup.sh 2>&1 | tail -40     # يعرض الأوامر لحظة تنفيذها
```

وافتح Issue فيه السطر الأخير من الخطأ + ناتج `bash scripts/doctor.sh`.
