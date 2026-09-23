# قالب web-static
موقع ثابت بدون أي build step — افتحه فوراً من المتصفح، وانشره على GitHub Pages.

```bash
bash ../../scripts/serve.sh .          # معاينة على الشبكة المحلية
# أو: python3 -m http.server 8080
```

**النشر على GitHub Pages** (من داخل مجلد المشروع):

```bash
git init && git add -A && git commit -m "site"
gh repo create my-site --public --source . --push
gh api repos/{owner}/my-site/pages -X POST -f 'build_type=workflow' || true
```

الملفات مصممة لتعمل من أي مسار فرعي (استخدم `./` في المسارات، لا `/`).
