#!/usr/bin/env bash
# ============================================================
#  disk.sh — أرقام المساحة الحقيقية، قبل وبعد التثبيت
#  التشغيل:
#    bash disk.sh                    # تقرير كامل للريبو + القرص + الكاشات
#    bash disk.sh --plan             # كم يضيف كل ملف تثبيت؟ (محاكاة apt، بلا تنزيل)
#    bash disk.sh --plan minimal     # ملف واحد فقط
#    bash disk.sh --project ~/projects/demo
#    bash disk.sh --clean            # ينظّف الكاشات ويعرض كم وفّرت
#    bash disk.sh --json             # للسكريبتات
# ============================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

MODE="report"; PROFILE="full"; TARGET="$ROOT"; JSON=0
TD_PREFIX="${PREFIX:-${HOME}/usr}"      # وعاء الحزم — خارج Termux يصير ~/usr فلا ينكسر الفحص

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)
      MODE="plan"
      # القبول الاختياري لاسم الملف — مع ضمان shift في كل الأحوال
      if [ $# -ge 2 ] && [ "${2:0:2}" != "--" ]; then PROFILE="$2"; shift; fi
      shift ;;
    --clean) MODE="clean"; shift ;;
    --project)
      MODE="project"
      [ $# -ge 2 ] || die "استخدام: --project <مسار-المشروع>"
      TARGET="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

kb() { printf '%s' "${1:-0}"; }
human() { # كيلوبايت → صيغة مقروءة
  local k="${1:-0}"
  awk -v k="$k" 'BEGIN{ if (k>=1048576) printf "%.2f GB", k/1048576; else if (k>=1024) printf "%.1f MB", k/1024; else printf "%.0f KB", k }'
}
dir_kb() { # du -sk آمن مع مسارات غير موجودة
  local d="$1" v
  v="$(du -sk "$d" 2>/dev/null | awk '{print $1; exit}')"
  printf '%s' "${v:-0}"
}
apparent_bytes() { # حجم الحقائق لا حجم الكتل
  local d="$1"
  find "$d" -type f -not -path '*/.git/*' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{printf "%d", s+0}'
}

# ============================================================ PLAN
if [ "$MODE" = "plan" ]; then
  printf '\n%s\n' "${C_BOLD}تقدير مساحة التثبيت لكل ملف (apt simulation — لا يُنزَّل شيء)${C_RESET}"
  printf '%-10s %-6s %-14s %-16s %s\n' "PROFILE" "PKGS" "DOWNLOAD" "DISK +" "الحزم"
  printf '%s\n' "--------------------------------------------------------------------------"
  for prof in $(td_profiles); do
    list="$(td_profile_packages "$prof" | tr '\n' ' ')"
    n="$(td_profile_packages "$prof" | wc -l | tr -d ' ')"
    proj="$(apt_projection "$prof" || true)"
    if [ -n "$proj" ]; then
      IFS='|' read -r new dl extra <<<"$proj"
      printf '%-10s %-6s %-14s %-16s %s\n' "$prof" "$n" "${dl:-?}" "${extra:-?}" "$(printf '%s' "$list" | cut -c1-46)…"
    else
      printf '%-10s %-6s %-14s %-16s %s\n' "$prof" "$n" "n/a" "n/a" "$(printf '%s' "$list" | cut -c1-46)…"
    fi
  done
  printf '\n%s\n' "${C_DIM}«DISK +» هو ما تضيفه الحزم نفسها. أضف فوقه:
  • ~120–180MB لتطبيق Termux + bootstrap (لو لسه مثبتّه)
  • حجم مستودعك: $(human $(( $(dir_kb "$ROOT") ))) (يشمل .git)
  • كل مشروع تُولّده: ~40–60KB قبل أي إضافات${C_RESET}"
  printf '\n%s\n' "${C_BOLD}نصيحة${C_RESET}: لو مساحتك ضيقة، استخدم ${C_BOLD}bash setup.sh --tools-only${C_RESET} ثم أضف nodejs-lts أو python وقت الحاجة فقط."
  [ "$PROFILE" != "full" ] && printf 'ملف مختار للاختبار السريع: %s\n' "$PROFILE"
  exit 0
fi

# ============================================================ PROJECT
if [ "$MODE" = "project" ]; then
  [ -d "$TARGET" ] || die "المجلد غير موجود: $TARGET"
  ab="$(apparent_bytes "$TARGET")"
  printf '\n%s\n' "${C_BOLD}مساحة المشروع: $TARGET${C_RESET}"
  printf '  %-26s %s\n' "الحجم الفعلي للملفات" "$(awk -v b="$ab" 'BEGIN{printf "%.1f KB", b/1024}')"
  printf '  %-26s %s\n' "المساحة على القرص (كتل)" "$(human "$(dir_kb "$TARGET")")"
  printf '  %-26s %s\n' "عدد الملفات" "$(find "$TARGET" -type f -not -path '*/.git/*' | wc -l | tr -d ' ')"
  for sub in node_modules .venv data .git; do
    if [ -e "$TARGET/$sub" ]; then
      printf '  %-26s %s\n' "↳ $sub" "$(human "$(dir_kb "$TARGET/$sub")")"
    fi
  done
  nm="$(dir_kb "$TARGET/node_modules")"
  if [ "${nm:-0}" -gt 20480 ]; then
    warn "node_modules = $(human "$nm") — لو مش محتاجه دلوقتي: rm -rf '$TARGET/node_modules' (يرجع بـ npm install)"
  fi
  exit 0
fi

# ============================================================ CLEAN
if [ "$MODE" = "clean" ]; then
  step "تنظيف الكاشات (لا يمسح أي كود أو commit)"
  before="$(dir_kb "$TD_PREFIX")"
  freed=0
  for c in "$TD_PREFIX/var/cache/apt/archives" "$TD_PREFIX/var/lib/apt/lists" \
           "$HOME/.npm" "$HOME/.cache" "$HOME/.gradle/caches"; do
    [ -d "$c" ] || continue
    sz="$(dir_kb "$c")"
    [ "${sz:-0}" -gt 0 ] || continue
    printf '  %-46s %s\n' "$(basename "$c")" "$(human "$sz")"
    freed=$((freed + sz))
    case "$c" in
      *apt*) try apt-get clean >/dev/null 2>&1 || rm -rf "$c"/* ;;
      "$HOME/.npm") try npm cache clean --force >/dev/null 2>&1 ;;
      *) rm -rf "${c:?}"/* 2>/dev/null ;;
    esac
  done
  after="$(dir_kb "$TD_PREFIX")"
  printf '\n'
  ok "المساحة التي تم تحريرها: ~$(human "$freed")"
  [ "$before" != 0 ] && [ "$after" != 0 ] && say "$before KB → $after KB في ${PREFIX:-$HOME}"
  say "للتأكيد: df -h ${PREFIX:-$HOME}"
  exit 0
fi

# ============================================================ REPORT
if [ "$JSON" != "1" ]; then
  printf '\n%s\n' "${C_BOLD}تقرير المساحة — termux-dev${C_RESET}"
fi
if [ "$JSON" = "1" ]; then
  printf '{"repo_apparent_bytes":%s,"repo_kb":%s,"git_kb":%s,"files":%s,"lines":%s,"free_kb":%s,"prefix_kb":%s' \
      "$(apparent_bytes "$ROOT")" "$(dir_kb "$ROOT")" "$(dir_kb "$ROOT/.git")" \
      "$(git -C "$ROOT" ls-files 2>/dev/null | wc -l | tr -d ' ')" \
      "$(git -C "$ROOT" ls-files -z 2>/dev/null | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')" \
      "$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')" \
      "$(dir_kb "$TD_PREFIX")"
    printf ',"caches":{'
    first=1
    for c in "$TD_PREFIX/var/cache/apt/archives" "$TD_PREFIX/var/lib/apt/lists" "$HOME/.npm" "$HOME/.cache"; do
      [ -d "$c" ] || continue
      [ "$first" = 1 ] || printf ','
      first=0
      printf '"%s":%s' "$(basename "$c")" "$(dir_kb "$c")"
    done
    printf '},"profile_full":'; printf '%s' "$(apt_projection full | awk -F'|' '{printf "\"%s/%s\"", $2, $3}' 2>/dev/null || echo '"n/a"')"
    printf '}\n'
  exit 0
fi

step "1) المستودع نفسه"
ab="$(apparent_bytes "$ROOT")"
printf '  %-30s %s\n' "حجم الملفات (فعلي)" "$(awk -v b="$ab" 'BEGIN{printf "%.1f KB", b/1024}')"
printf '  %-30s %s\n' "على القرص (مع الكتل)" "$(human "$(dir_kb "$ROOT")")"
printf '  %-30s %s\n' ".git (التاريخ كاملاً)" "$(human "$(dir_kb "$ROOT/.git")")"
printf '  %-30s %s\n' "ملفات متتبَّعة / أسطر" "$(git -C "$ROOT" ls-files 2>/dev/null | wc -l | tr -d ' ') / $(git -C "$ROOT" ls-files -z 2>/dev/null | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')"
printf '  %-30s %s\n' "أكبر ملف" "$(find "$ROOT" -type f -not -path '*/.git/*' -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | awk -v r="$ROOT" '{gsub(r"/", "", $2); printf "%.1f KB %s", $1/1024, $2}')"
say "الـ clone الكامل (شجرة + تاريخ) = $(human $(( $(dir_kb "$ROOT") ))) — أي أقل من 1MB"

step "2) مساحة كل ملف تثبيت (apt simulation)"
for prof in $(td_profiles); do
  proj="$(apt_projection "$prof" || true)"
  n="$(td_profile_packages "$prof" | wc -l | tr -d ' ')"
  if [ -n "$proj" ]; then
    IFS='|' read -r new dl extra <<<"$proj"
    printf '  %-9s %s حزمة  →  تنزيل %s ، قرص +%s\n' "$prof" "$n" "${dl:-?}" "${extra:-?}"
  else
    printf '  %-9s %s حزمة  →  (apt غير متاح هنا — نفّذه على Termux:  pkg install -s %s)\n' \
      "$prof" "$n" "$(td_profile_packages "$prof" | head -3 | tr '\n' ' ')"
  fi
done

step "3) القرص الآن"
FREE_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
USED_PCT="$(df -P "$HOME" 2>/dev/null | awk 'NR==2{print $5}')"
printf '  %-30s %s\n' "حرة" "$(human "${FREE_KB:-0}") ($USED_PCT مستخدمة)"
if is_termux; then
  printf '  %-30s %s\n' "$PREFIX (حزم Termux)" "$(human "$(dir_kb "$TD_PREFIX")")"
else
  printf '  %-30s %s\n' "حزم Termux" "غير متاح خارج Termux ($TD_PREFIX)"
fi
if [ -n "${FREE_KB:-}" ] && [ "$FREE_KB" -lt 512000 ]; then
  warn "أقل من 500MB حرة — التثبيت الكامل سيفشل غالبًا. استخدم --tools-only أو نظّف أولًا: bash disk.sh --clean"
elif [ -n "${FREE_KB:-}" ] && [ "$FREE_KB" -lt 1048576 ]; then
  warn "أقل من 1GB حرة — الكافي لـ minimal فقط، وبعدها pkg clean"
else
  ok "المساحة تكفي التثبيت الكامل"
fi

step "4) الكاشات (أول مكان يتنفّخ)"
total_cache=0
for c in "$TD_PREFIX/var/cache/apt/archives" "$TD_PREFIX/var/lib/apt/lists" \
         "$HOME/.npm" "$HOME/.cache" "$HOME/.venvs" "$ROOT/.tmp-tests"; do
  [ -d "$c" ] || continue
  sz="$(dir_kb "$c")"
  printf '  %-46s %s\n' "${c/#$HOME/~}" "$(human "$sz")"
  total_cache=$((total_cache + ${sz:-0}))
done
printf '  %-46s %s\n' "${C_BOLD}الإجمالي${C_RESET}" "$(human "$total_cache")"
[ "$total_cache" -gt 10240 ] && say "توفير سريع:  bash disk.sh --clean"

step "5) ما الذي يكبر فعلًا بعد التوليد"
cat <<EOF
  • قالب node-api:   ~55KB  (0 حزم — يعمل بـ Node stdlib)
  • قالب python-api: ~30KB  + ملف SQLite ينمو مع البيانات
  • قالب web-static: ~14KB  (بلا اعتماديات)
  • إضافة express:   +2–6MB في node_modules داخل المشروع فقط
  • npm cache:       +30–150MB بعد أول install ثقيل  ← يُنظَّف بـ --clean
EOF
printf '\n'
say "حجم هذا المستودع بعد clone: $(human $(( $(dir_kb "$ROOT") ))) · ومساحة مشروع تُولّده: ~50KB"
say "أرقام اليوم: Termux + bootstrap ≈ 120–180MB · nodejs-lts ≈ 120MB · python ≈ 70MB · git ≈ 30MB (تقريبي، و«2» فوق يعطيك رقم جهازك بدقة)"
