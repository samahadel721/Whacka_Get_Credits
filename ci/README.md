# ملف CI (اختياري)

لا يملك هذا المستودع صلاحية `workflows` من التطبيق المرتبط، لذا يُخزَّن الملف هنا.
لتفعيله على GitHub Actions:

```bash
mkdir -p .github/workflows
cp ci/github-workflows-ci.yml .github/workflows/ci.yml
git add .github/workflows && git commit -m "ci: enable toolkit tests on Actions" && git push
```

ماذا يفعل: `make check` (صيغة كل ملف) ثم `bash tests/run.sh` (اختبارات التكامل التي تشغّل خوادم القوالب فعليًا)، ويعرض تقرير shellcheck بدون إفشال البناء.

بديل بلا Actions — فحص محلي قبل أي push:

```bash
bash tests/run.sh && git push
```
