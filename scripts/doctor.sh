#!/usr/bin/env bash
# ============================================================
#  doctor.sh — تشخيص صحة بيئة Termux قبل أي عمل
#  يعطيك PASS / WARN / FAIL مع الحل الجاهز لكل مشكلة.
#  تشغيل:  bash doctor.sh   أو   bash doctor.sh --json
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

JSON=0
[ "${1:-}" = "--json" ] && JSON=1
PASS=0; WARN=0; FAIL=0
RESULTS=()

record() { # level name message fix
  local level name msg fix
  level="$1"; name="$2"; msg="$3"; fix="${4:-}"
  RESULTS+=("$level|$name|$msg|$fix")
  case "$level" in
    pass) PASS=$((PASS+1)); [ "$JSON" = "1" ] || printf '%s  %-22s %s\n' "${C_GREEN}PASS${C_RESET}" "$name" "$msg" ;;
    warn) WARN=$((WARN+1)); [ "$JSON" = "1" ] || printf '%s  %-22s %s\n' "${C_YELLOW}WARN${C_RESET}" "$name" "$msg" ;;
    fail) FAIL=$((FAIL+1)); [ "$JSON" = "1" ] || printf '%s  %-22s %s\n' "${C_RED}FAIL${C_RESET}" "$name" "$msg" ;;
  esac
  if [ "$JSON" != "1" ] && [ -n "$fix" ] && [ "$level" != "pass" ]; then
    printf '%s\n' "       ${C_DIM}الحل: ${fix}${C_RESET}"
  fi
}

check_pkg() {
  local name bin fix
  name="$1"
  bin="${2:-$1}"
  fix="pkg install -y ${name}"
  if have "$bin"; then
    record pass "$name" "$(command -v "$bin")"
  else
    record fail "$name" "غير مثبّت" "$fix"
  fi
}

printf '\n%s\n' "${C_BOLD}تقرير صحة البيئة (termux-dev doctor)${C_RESET}"
printf '%s\n' "---------------------------------------------"

# 1) هل نحن داخل Termux فعلاً
if is_termux; then
  record pass "termux" "PREFIX=${PREFIX}"
else
  record warn "termux" "لسنا داخل Termux (PREFIX غير معروف)" "شغّل السكربت من داخل تطبيق Termux"
fi

# 2) حجم صفحة الذاكرة — سبب أشهر crash على أندرويد 15+ / أجهزة 16KB
PAGE_SIZE="$(python3 -c 'import os;print(os.sysconf("SC_PAGE_SIZE"))' 2>/dev/null || echo unknown)"
if [ "$PAGE_SIZE" = "16384" ]; then
  record warn "page-size" "16KB — يحتاج Termux + حزم مبنية لدعم 16KB" \
    "ثبّت أحدث إصدار من GitHub releases (F-Droid قديم) ثم pkg upgrade -y"
elif [ "$PAGE_SIZE" = "unknown" ]; then
  record warn "page-size" "لم نتمكن من القراءة (python3 غير مثبّت؟)" "bash setup.sh -y"
else
  record pass "page-size" "${PAGE_SIZE} bytes"
fi

# 3) صلاحية التخزين المشترك
if [ -d "${HOME}/storage/shared" ]; then
  record pass "storage" "التخزين المشترك متاح"
else
  record warn "storage" "لا يوجد ~/storage/shared" "نفّذ: termux-setup-storage ثم اقبل الإذن"
fi

# 4) مساحة القرص في قسم Termux
AVAIL_KB="$(df -Pk "${HOME}" 2>/dev/null | awk 'NR==2{print $4}')"
[ -n "${AVAIL_KB:-}" ] || AVAIL_KB="$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "${AVAIL_KB:-}" ]; then
  AVAIL_MB=$((AVAIL_KB / 1024))
  if [ "$AVAIL_MB" -lt 300 ]; then
    record fail "disk" "المساحة الحرة ${AVAIL_MB}MB فقط" "نظّف: pkg clean -y && npm cache clean --force && rm -rf ~/.cache"
  else
    record pass "disk" "متاح ~$((AVAIL_MB/1024))GB"
  fi
else
  record warn "disk" "df لم يُرجع بيانات" ""
fi

# 5) الحزم الأساسية
check_pkg git git
check_pkg curl curl
check_pkg nodejs-lts node
check_pkg python python3
check_pkg jq jq
check_pkg ripgrep rg

# 6) npm prefix — يوفّر عليك أخطاء EACCES لاحقاً
if have npm; then
  NPMPFX="$(npm config get prefix 2>/dev/null || echo)"
  case "$NPMPFX" in
    "$HOME"*) record pass "npm-prefix" "$NPMPFX" ;;
    *) record warn "npm-prefix" "${NPMPFX:-غير معروف} خارج المجلد المنزلي" \
         "npm config set prefix \$HOME/.npm-global && export PATH=\$HOME/.npm-global/bin:\$PATH" ;;
  esac
fi

# 7) الهوية في git (من غيرّها لن تستطيع عمل commit في كثير من الإعدادات)
if have git; then
  if git config --global user.email >/dev/null 2>&1; then
    record pass "git-identity" "$(git config --global user.name) <$(git config --global user.email)>"
  else
    record fail "git-identity" "user.name / user.email غير مضبوطين" \
      'git config --global user.name "اسمك" && git config --global user.email "you@mail.com"'
  fi
fi

# 8) سلامة قاعدة dpkg (مصدر أغلب أخطاء pkg install)
if is_termux && have dpkg; then
  if dpkg --audit 2>/dev/null | grep -qi 'is not fully installed\|half-configured'; then
    record fail "dpkg" "حزم غير مكتملة التثبيت" "dpkg --configure -a && pkg upgrade -y"
  else
    record pass "dpkg" "قاعدة الحزم سليمة"
  fi
fi

# 9)Wake lock — أهم نقطة للمهام الطويلة على أندرويد
if is_termux && have termux-wake-lock; then
  record pass "wake-lock" "الأمر متاح (تأكد أنك شغّلته قبل المهام الطويلة)"
else
  record warn "wake-lock" "termux-wake-lock غير متاح" "pkg install -y termux-api"
fi

# 10) الشبكة: هل مستودع الحزم يستجيب
if have curl; then
  CODE="$(curl -s -o /dev/null -m 8 -w '%{http_code}' https://packages.termux.dev 2>/dev/null | tail -c 4 || true)"
  case "${CODE:-000}" in
    2[0-9][0-9]|3[0-9][0-9]|40[0-9]|4[1-9][0-9])
      record pass "network" "packages.termux.dev → HTTP ${CODE}" ;;
    429|5[0-9][0-9])
      record warn "network" "المستودع يستجيب لكن بـ HTTP ${CODE} (مُحمَّل أو بهبوط)" "انتظر قليلاً أو نفّذ: termux-change-repo" ;;
    *)
      record warn "network" "لم نصل إلى packages.termux.dev خلال 8 ثوانٍ" "جرّب mirror أقرب: termux-change-repo" ;;
  esac
fi

if [ "$JSON" != "1" ]; then
  printf '%s\n' "---------------------------------------------"
  printf '%s  PASS: %s   WARN: %s   FAIL: %s\n' "النتيجة" "$PASS" "$WARN" "$FAIL"
fi

if [ "$JSON" = "1" ]; then
  printf '['
  first=1
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r lvl name msg fix <<<"$r"
    [ "$first" = "1" ] || printf ','
    first=0
    printf '{"level":"%s","check":"%s","detail":%s,"fix":%s}' \
      "$lvl" "$name" "$(printf '%s' "$msg" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '"')" \
      "$(printf '%s' "$fix" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')"
  done
  printf ']\n'
  exit 0
fi

if [ "$FAIL" -gt 0 ]; then
  [ "$JSON" = "1" ] || printf '\n%s\n' "${C_RED}في مشاكل لازم تحلها قبل ما تكمّل (شوف سطر «الحل» فوق).${C_RESET}"
  exit 1
fi
[ "$JSON" = "1" ] || printf '\n%s\n' "${C_GREEN}البيئة جاهزة ✅${C_RESET}"
