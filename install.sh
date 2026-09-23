#!/usr/bin/env bash
# ============================================================
#  install.sh — مدخل واحد للتجهيز، سواء جبت المستودع بـ git أو بنسخة مضغوطة
#  التشغيل (من داخل مجلد المشروع):
#    bash install.sh              # يثبّت الحزم ثم يفحص البيئة
#    bash install.sh --minimal    # ملفات تثبيت أصغر
#    bash install.sh --tools-only # git + أدوات فقط (للمساحة الضيقة)
#    bash install.sh --check-only # يفحص فقط بدون أي تثبيت
#    bash install.sh --demo       # تجهيز + فحص + توليد مشروع تجريبي وتشغيله
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

MODE="setup"
PROFILE=""
ARGS=()
for a in "$@"; do
  case "$a" in
    --check-only) MODE="check" ;;
    --demo)       MODE="demo" ;;
    --minimal|--tools-only|--python-only|--full) ARGS+=("${a}") ;;
    --profile=*)  ARGS+=("$a") ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) printf 'خيار غير معروف: %s (جرّب --help)\n' "$a" >&2; exit 2 ;;
  esac
done

need() { # <أمر> <حزمة>
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s غير متوفر — سيُثبَّت من حزمة %s\n' "$1" "$2"
    return 1
  fi
  return 0
}

step_install_git() {
  need git git && return 0
  if command -v pkg >/dev/null 2>&1; then
    printf '→ pkg install -y git\n'
    pkg install -y git >/dev/null 2>&1 || printf 'تعذّر التثبيت التلقائي لـ git — ثبّته يدويًا ثم أعد المحاولة.\n' >&2
  else
    printf 'أنت لست في Termux؛ ثبّت git من مدير الحزم عندك.\n' >&2
  fi
}

printf '\n── termux-dev · install ──\n'
printf 'المجلد: %s\n' "$HERE"
if [ -d .git ]; then
  printf 'النسخة: %s (%s)\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')" "$(git rev-parse --short HEAD 2>/dev/null || echo '-')"
else
  printf 'نسخة بلا تاريخ git (ملف مضغوط غالبًا) — لا يؤثر على الاستخدام.\n'
fi

# 1) فحص سلامة النسخة المستخرجة
if [ ! -f scripts/setup.sh ] || [ ! -f scripts/doctor.sh ] || [ ! -d templates/node-api ]; then
  printf 'الملفات ناقصة في هذا المجلد — نزّل النسخة كاملة أو فك الضغط في مجلد آخر.\n' >&2
  exit 1
fi
printf '✓ سلامة الملفات: %s سكربت + %s قالب\n' "$(ls scripts/*.sh | wc -l | tr -d ' ')" "$(ls -d templates/*/ | wc -l | tr -d ' ')"

# 2) التثبيت
case "$MODE" in
  check)
    printf '\n[وضع الفحص فقط]\n' ;;
  *)
    step_install_git
    printf '\n→ bash scripts/setup.sh -y %s\n' "${ARGS[*]:-}"
    bash scripts/setup.sh -y ${ARGS[@]:-} ;;
esac

# 3) الفحص
printf '\n'
bash scripts/doctor.sh || true

# 4) خيار المشروع التجريبي
if [ "$MODE" = "demo" ]; then
  TARGET="${HOME}/projects/termux-dev-demo"
  printf '\n→ توليد مشروع تجريبي في %s\n' "$TARGET"
  rm -rf "$TARGET"
  bash scripts/project.sh termux-dev-demo -t node-api -d "$TARGET"
  printf '\n→ تشغيله على http://127.0.0.1:8080 (Ctrl+E Ctrl+C لإيقافه من هذا الطرفية)\n'
  cd "$TARGET"
  exec node server.js
fi

printf '\nالخطوة التالية:\n'
printf '  bash scripts/project.sh myapp -t node-api && cd ~/projects/myapp && npm run dev\n'
printf '  أو: bash scripts/disk.sh --plan   (مساحة كل ملف تثبيت)\n\n'
