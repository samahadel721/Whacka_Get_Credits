# Cheat sheet — Termux

## النظام
```bash
termux-wake-lock              # أبقِ المعالج مستيقظًا (افعلها أول شيء لكل مهمة طويلة)
termux-info                   # معلومات الجهاز والإصدارات
pkg search <كلمة>             # ابحث في المستودعات
pkg install -y <حزمة>
pkg autoremove -y && pkg clean -y
termux-setup-storage          # إعادة طلب صلاحية الملفات
termux-reload-settings        # بعد تعديل ~/.termux/termux.properties
```

## أدوات التطبيق الرسمية (`pkg install termux-api`)
```bash
termux-open-url https://example.com      # افتح في المتصفح
termux-open ./report.pdf                 # افتح بملف
termux-share -a clip                     # شارك نصًا/ملفًا
termux-clipboard-set "text"              # انسخ
termux-clipboard-get                       # الصق إلى الطرفية
termux-notification -t "انتهى" -c "npm build"   # إشعار نظام
termux-vibrate -d 300
termux-battery-status
termux-wifi-connectioninfo
termux-torch on|off
termux-camera-photo out.jpg
termux-sms-list -l 3                       # رسائل الهاتف (للاستخدام الشخصي فقط)
termux-location                            # موقع تقريبي
```

## الشبكة
```bash
ifconfig wlan0                             # أو: ip -4 addr show wlan0
netstat -tlnp | grep 8080                  # من يسمع على المنفذ
ssh-keygen -t ed25519 -C "phone"           # مفتاح GitHub
ssh -T git@github.com                       # اختبار المصادقة
curl -I -m 8 https://api.github.com         # فحص الوصول
ssh -R 8080:localhost:8080 serveo.net       # نفق سريع (بديل tunnel.sh)
```

## ملفات ومجلدات
```bash
du -sh ~/projects/* | sort -h               # أكبر المشاريع
find . -name '*.log' -mtime +7 -delete
tree -L 2 -I 'node_modules|.git'
rsync -a --delete ./ ~/storage/shared/backup/    # مزامنة لمجلد الهاتف
tar czf ~/backups/app-$(date +%F).tar.gz -C ~/projects/app .
```

## Node / Python
```bash
npm run dev        # مع --watch
npx --yes <حزمة>   # شغّل حزمة بدون تثبيت عام
node --test
python3 -m venv .venv && source .venv/bin/activate
python3 -m unittest -v
```

## Git اليومي
```bash
git switch -c feat/x
git add -p
git commit -m "fix: ..."
git stash && git pull --rebase && git stash pop
git log --oneline --graph -10
gh repo create myapp --private --source . --push
```

## بورت عالق (السيرفر السابق لم يمت)
```bash
bash scripts/serve.sh --status --port 8080   # من يسمع عليه؟
bash scripts/serve.sh --stop   --port 8080   # إيقافه بالأمان
make status PORT=8080 ; make stop PORT=8080  # نفس الشيء عبر make
```

## هذا المستودع
```bash
bash scripts/setup.sh -y
bash scripts/doctor.sh --json | jq '.[] | select(.level!="pass")'
bash scripts/project.sh demo -t node-api
bash scripts/serve.sh ~/projects/demo --port 8080 --open
bash scripts/backup.sh --push --shared
```
