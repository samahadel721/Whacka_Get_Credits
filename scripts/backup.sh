#!/usr/bin/env bash
# ============================================================
#  backup.sh — نسخة احتياطية للمشروع: commit + push + أرشيف على الهاتف
#  التشغيل (من داخل مجلد المشروع):
#    bash backup.sh                      # commit + أرشيف في ~/backups
#    bash backup.sh --push               # + رفع على origin
#    bash backup.sh --pull               # اسحب آخر تعديل من origin
#    bash backup.sh --shared             # الأرشيف في Downloads (يظهر في مدير الملفات)
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

PUSH=0; PULL=0; TO_SHARED=0; MSG="chore: backup $(date '+%Y-%m-%d %H:%M')"
PROJ="${2:-$PWD}"

while [ $# -gt 0 ]; do
  case "$1" in
    --push) PUSH=1; shift ;;
    --pull) PULL=1; shift ;;
    --shared) TO_SHARED=1; shift ;;
    -m) MSG="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) PROJ="$1"; shift ;;
  esac
done
PROJ="$(cd "$PROJ" && pwd)"
NAME="$(basename "$PROJ")"
have git || die "git غير مثبّت"

cd "$PROJ"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "المجلد ليس مستودع git: $PROJ"

if [ "$PULL" = "1" ]; then
  step "سحب من origin"
  git remote get-url origin >/dev/null 2>&1 || die "لا يوجد remote 'origin' — أضفه:  git remote add origin <url>"
  git pull --ff-only origin "$(git symbolic-ref --short HEAD)" && ok "تم السحب"
  exit 0
fi

step "تسجيل التغييرات"
if [ -z "$(git status --porcelain)" ]; then
  say "لا تغييرات — لا حاجة لـ commit"
else
  if ! git config user.email >/dev/null 2>&1 && ! git config --global user.email >/dev/null 2>&1; then
    die "هوية git غير مضبوطة — نفّذ:  git config --global user.name \"اسمك\" && git config --global user.email \"you@mail.com\""
  fi
  git add -A
  git commit -qm "$MSG"
  ok "commit: $(git rev-parse --short HEAD) — $(git log -1 --pretty=%s)"
fi

if [ "$PUSH" = "1" ]; then
  step "رفع إلى GitHub"
  if git remote get-url origin >/dev/null 2>&1; then
    branch="$(git symbolic-ref --short HEAD)"
    if git push -u origin "$branch"; then ok "تم الرفع"; else die "فشل الرفع — تأكد من الصلاحيات: gh auth status"; fi
  else
    die "لا يوجد remote. أنشئ مستودع: gh repo create ${NAME} --private --source . --push"
  fi
fi

step "أرشيف محلي"
DEST_DIR="${HOME}/backups"
[ "$TO_SHARED" = "1" ] && [ -d "${HOME}/storage/shared/Download" ] && DEST_DIR="${HOME}/storage/shared/Download/termux-backups"
mkdir -p "$DEST_DIR"
OUT="${DEST_DIR}/${NAME}-$(date +%Y%m%d-%H%M).tar.gz"
tar --exclude='./node_modules' --exclude='./.git/objects' --exclude='./__pycache__' \
    --exclude='./*.sqlite' --exclude='./.venv' -czf "$OUT" -C "$PROJ" . 2>/dev/null
sz="$(du -h "$OUT" | cut -f1)"
ok "الأرشيف: ${OUT} (${sz})"
say "للاستعادة:  tar -xzf ${OUT} -C /path/to/target"
