#!/usr/bin/env bash
# ============================================================
#  project.sh — إنشاء مشروع جديد من قالب جاهز + git init
#  تشغيل:
#    bash project.sh myapp --template node-api
#    bash project.sh myapp -t python-api --dir ~/projects
#    bash project.sh --list
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

TEMPLATES_DIR="${ROOT}/templates"
DEFAULT_DIR="${TERMUX_DEV_PROJECTS:-${HOME}/projects}"
TEMPLATE="node-api"
NAME=""
DEST=""

usage() {
  cat <<EOF
الاستخدام: bash project.sh <اسم-المشروع> [خيارات]

الخيارات:
  -t, --template <name>   القالب: $(cd "$TEMPLATES_DIR" 2>/dev/null && ls -1 | tr '\n' ' ')
  -d, --dir <path>        مجلد الوجهة (افتراضي: ${DEFAULT_DIR})
  -l, --list              عرض القوالب المتاحة
      --git-remote <url>  ربط مستودع GitHub بعد الإنشاء
  -h, --help              هذه الرسالة
EOF
}

list_templates() {
  say "القوالب المتاحة في ${TEMPLATES_DIR}:"
  for t in "${TEMPLATES_DIR}"/*/; do
    [ -d "$t" ] || continue
    local_name="$(basename "$t")"
    desc="$(sed -n '2s/^# *//p' "${t}/TEMPLATE.md" 2>/dev/null || true)"
    printf '  • %s%s%s\n' "${C_BOLD}${local_name}${C_RESET}" "${C_DIM}" " — ${desc:-قالب عام}${C_RESET}"
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--template) TEMPLATE="${2:?}"; shift 2 ;;
    -d|--dir) DEST="${2:?}"; shift 2 ;;
    --git-remote) GIT_REMOTE="${2:?}"; shift 2 ;;
    -l|--list) list_templates; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "خيار غير معروف: $1 (جرّب --help)" ;;
    *) [ -n "$NAME" ] && die "اسم واحد فقط مطلوب"; NAME="$1"; shift ;;
  esac
done

[ -n "$NAME" ] || { usage; exit 1; }
case "$NAME" in
  *[!A-Za-z0-9._-]*) die "اسم المشروع لازم يكون حروف لاتينية/أرقام/نقاط/شرطات فقط ($NAME)" ;;
esac
SRC="${TEMPLATES_DIR}/${TEMPLATE}"
[ -d "$SRC" ] || { err "القالب '${TEMPLATE}' غير موجود."; list_templates; exit 1; }
[ -z "${DEST:-}" ] && DEST="${DEFAULT_DIR}/${NAME}"
[ -e "$DEST" ] && die "المسار موجود بالفعل: $DEST"
mkdir -p "$(dirname "$DEST")"

step "نسخ القالب ${TEMPLATE} → ${DEST}"
cp -R "${SRC}/." "$DEST"

# إعادة كتابة اسم المشروع داخل الملفات النصية
if have rg; then
  HITS="$(rg -l "__PROJECT_NAME__" "$DEST" 2>/dev/null || true)"
else
  HITS="$(grep -rl "__PROJECT_NAME__" "$DEST" 2>/dev/null || true)"
fi
if [ -n "$HITS" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sed -i.bak "s/__PROJECT_NAME__/$(printf '%s' "$NAME" | sed 's/[&/\]/\\&/g')/g" "$f"
    rm -f "${f}.bak"
  done <<<"$HITS"
fi

# تنظيف مخلفات الكاش التي قد تكون تسرّبت من القالب
find "$DEST" \( -name '__pycache__' -o -name '*.pyc' -o -name '.pytest_cache' \
  -o -name '.ruff_cache' -o -name 'node_modules' -o -name '.DS_Store' \
  -o -name '*.tmp' \) -prune -exec rm -rf {} + 2>/dev/null || true

rm -f "${DEST}/TEMPLATE.md"

# .env من القالب لو موجود
[ -f "${DEST}/.env.example" ] && cp "${DEST}/.env.example" "${DEST}/.env"

if have git; then
  step "تهيئة git"
  git -C "$DEST" init -q -b main 2>/dev/null || git -C "$DEST" init -q
  git -C "$DEST" add -A
  git -C "$DEST" -c user.name="${GIT_AUTHOR_NAME:-$(git config --global user.name 2>/dev/null || echo dev)}" \
                 -c user.email="${GIT_AUTHOR_EMAIL:-$(git config --global user.email 2>/dev/null || echo dev@localhost)}" \
                 commit -qm "chore: scaffold from termux-dev template '${TEMPLATE}'"
  ok "أول commit جاهز"
  if [ -n "${GIT_REMOTE:-}" ]; then
    git -C "$DEST" remote add origin "$GIT_REMOTE"
    say "remote origin = ${GIT_REMOTE}"
  fi
else
  warn "git غير مثبّت — تم إنشاء الملفات بدون مستودع"
fi

printf '\n'
ok "تم إنشاء المشروع: ${DEST}"
need_install="no"
if have npm && [ -f "${DEST}/package.json" ]; then
  grep -Eq '"(dev)?[Dd]ependencies"' "${DEST}/package.json" && need_install="yes"
fi
{
  printf '\n  الخطوة التالية:\n'
  printf '    cd %s\n' "$DEST"
  [ "$need_install" = "yes" ] && printf '    npm install\n'
  case "$TEMPLATE" in
    python-api) printf '    python3 app.py\n' ;;
    node-api)   printf '    npm run dev\n' ;;
    web-static) printf '    bash %s/serve.sh .\n' "$ROOT/scripts" ;;
  esac
  printf '    # أو معاينة على الشبكة: bash %s/serve.sh %s\n\n' "$ROOT/scripts" "$DEST"
} | cat
