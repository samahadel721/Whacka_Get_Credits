#!/usr/bin/env bash
# ============================================================
#  setup.sh — تجهيز بيئة تطوير كاملة على Termux
#  تشغيل:  bash setup.sh          (تفاعلي)
#          bash setup.sh -y       (بدون أسئلة، للـ CI أو التكرار)
#  التكرار آمن: كل خطوة تفحص قبل ما تكتب.
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

# الأعلام: -y | --minimal | --python-only | --tools-only | --full | --profile=NAME
PROFILE="${TD_PROFILE:-full}"
for _arg in "$@"; do
  case "$_arg" in
    -y|--yes|--assume-yes) TD_ASSUME_YES=1 ;;
    --minimal)     PROFILE="minimal" ;;
    --python-only) PROFILE="python" ;;
    --tools-only)  PROFILE="tools" ;;
    --full)        PROFILE="full" ;;
    --profile=*)   PROFILE="${_arg#*=}" ;;
    -h|--help)     sed -n '2,8p' "$0"; exit 0 ;;
  esac
done
td_profile_packages "$PROFILE" >/dev/null 2>&1 || die "ملف تثبيت غير معروف: ${PROFILE} (المتاح: $(td_profiles))"

log_head() {
  printf '\n=== termux-dev setup v%s — profile: %s ===\n' "$TD_VERSION" "$PROFILE"
  local proj new dl extra
  proj="$(apt_projection "$PROFILE" 2>/dev/null || true)"
  if [ -n "$proj" ]; then
    IFS='|' read -r new dl extra <<<"$proj"
    say "التقدير من apt: ${new:-?} حزمة جديدة · تنزيل ${dl:-?} · قرص +${extra:-?}"
    say "لمقارنة الملفات:  bash ${HERE}/disk.sh --plan"
  fi
}

log_head

if ! is_termux; then
  warn "أنت لست داخل Termux — السكربت شغال في وضع محاكاة (dry-run) بدون pkg install."
  warn "على الموبايل نفّذه من داخل تطبيق Termux."
  DRY=1
else
  DRY=0
fi

# ----------------------------------------------------------
step "1/7  تحديث الحزم"
if [ "$DRY" = "0" ]; then
  if try dpkg --audit; then :; else warn "في حزم نصف مثبتة — سيتم إصلاحها"; fi
  pkg update -y
  DEBIAN_FRONTEND=noninteractive pkg upgrade -y
  ok "تم التحديث"
else
  say "pkg update && pkg upgrade -y   [dry-run]"
fi

# ----------------------------------------------------------
step "2/7  تثبيت الحزم الأساسية"
install_pkgs() {
  local list=("$@") missing=() p
  for p in "${list[@]}"; do
    case "$p" in
      nodejs-lts) have node || missing+=("$p") ;;
      python|python-pip) have python3 || missing+=("python") ;;
      *) have "${p%-utils}" || missing+=("$p") ;;
    esac
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "كل الحزم المطلوبة موجودة"
    return 0
  fi
  say "المطلوب تثبيته: ${missing[*]}"
  if [ "$DRY" = "1" ]; then
    say "pkg install -y ${missing[*]}   [dry-run]"
    return 0
  fi
  if DEBIAN_FRONTEND=noninteractive pkg install -y "${missing[@]}"; then
    ok "تم التثبيت"
    return 0
  fi
  # فشل التثبيت الجماعي — غالبًا حزمة واحدة غير متوفرة؛ نجرّبها واحدة واحدة
  warn "تعذّر التثبيت الجماعي — سيتم تجربة كل حزمة على حدة"
  local failed=()
  for p in "${missing[@]}"; do
    if DEBIAN_FRONTEND=noninteractive pkg install -y "$p"; then
      ok "$p"
    else
      failed+=("$p")
    fi
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    warn "حزم غير متوفرة في مستودعك (لا توقف التجهيز): ${failed[*]}"
    say "إن احتجتها فعلاً: termux-change-repo لاختيار مرآة أخرى ثم أعد المحاولة"
  fi
}
mapfile -t PKGS_WANTED < <(td_profile_packages "$PROFILE")
install_pkgs "${PKGS_WANTED[@]}"

# ----------------------------------------------------------
step "3/7  صلاحية التخزين المشترك"
if [ "$DRY" = "0" ]; then
  if [ -d "${HOME}/storage/shared" ]; then
    ok "التخزين المشترك موصول"
  elif confirm "هل نفتح صلاحية الوصول لمجلدات الهاتف؟ (سيظهر مربع تأكيد)"; then
    termux-setup-storage || warn "ارفض/اقبل من النافذة ثم أعد التشغيل"
    ok "تم طلب الصلاحية"
  else
    warn "تخطيت — بدونها لن تستطيع نسخ ملفات لمجلد Downloads"
  fi
else
  say "termux-setup-storage   [dry-run]"
fi

# ----------------------------------------------------------
step "4/7  لوحة مفاتيح Termux (سطر ESC / TAB / أسهم)"
PROPS_DIR="${HOME}/.termux"
PROPS="${PROPS_DIR}/termux.properties"
mkdir -p "$PROPS_DIR"
EXTRA_KEYS='extra-keys = [[ESC,TAB,CTRL,ALT,{,},|],[PGUP,UP,PGDN,LEFT,DOWN,RIGHT,HOME]]'
if [ -f "$PROPS" ] && grep -q '^extra-keys' "$PROPS"; then
  ok "سطر المفاتيح مُعرّف مسبقاً — لم نغيّره"
else
  [ -f "$PROPS" ] && cp "$PROPS" "${PROPS}.bak"
  printf '%s\n' "$EXTRA_KEYS" >> "$PROPS"
  printf '%s\n' 'use-black-ui = true' >> "$PROPS"
  printf '%s\n' 'terminal-cursor-blink-rate = 0' >> "$PROPS"
  ok "تمت إضافة سطر مفاتيح البرمجة إلى termux.properties"
  [ "$DRY" = "0" ] && try termux-reload-settings
fi

# ----------------------------------------------------------
step "5/7  npm global بدون صلاحيات"
NPM_PREFIX="${HOME}/.npm-global"
mkdir -p "$NPM_PREFIX"
if have npm; then
  npm config set prefix "$NPM_PREFIX" >/dev/null 2>&1 || warn "فشل ضبط npm prefix"
  ok "npm prefix = ${NPM_PREFIX}"
fi

# ----------------------------------------------------------
step "6/7  aliases ومسارات في ~/.bashrc"
BLOCK=$(cat <<EOF
export PATH="\$HOME/.npm-global/bin:\$PATH"
export EDITOR=nano
export TERMUX_DEV_PROJECTS="\$HOME/projects"
alias ll='ls -lah --color=auto'
alias up='pkg update && pkg upgrade -y'
alias dev='cd "\$HOME/projects" && ls -1'
alias wake='termux-wake-lock'
alias gpush='git add -A && git commit -m "sync" && git push'
EOF
)
patch_bashrc "$BLOCK"

# ----------------------------------------------------------
step "7/7  مجلدات العمل + هوية git"
mkdir -p "${HOME}/projects" "${HOME}/backups"
if have git; then
  if [ -z "$(git config --global user.name 2>/dev/null || true)" ]; then
    if [ ! -t 0 ] || assume_yes; then
      warn "لم يتم ضبط اسم git — نفّذ: git config --global user.name \"اسمك\" && git config --global user.email \"you@mail.com\""
    else
      read -r -p "اسمك في الـ commits: " gname || gname=""
      read -r -p "بريدك: " gemail || gemail=""
      [ -n "$gname" ] && git config --global user.name "$gname"
      [ -n "$gemail" ] && git config --global user.email "$gemail"
    fi
  fi
  git config --global init.defaultBranch main >/dev/null 2>&1 || true
  git config --global core.fileMode false >/dev/null 2>&1 || true
fi

printf '\n'
ok "انتهى التجهيز."
say "الخطوة التالية:  bash ${HERE}/doctor.sh   (فحص صحة البيئة)"
say "ثم إنشاء مشروع:  bash ${HERE}/project.sh myapp --template node-api"
if [ "$DRY" = "0" ]; then
  say "لا تنسَ تشغيل ${C_BOLD}termux-wake-lock${C_RESET} قبل أي مهمة طويلة، وإلا أندرويد سيوقف العملية."
fi
