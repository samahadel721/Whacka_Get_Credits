# shellcheck shell=bash
# مشترك بين سكربتات الـ toolkit. يتم تضمينه عبر: source "$(dirname "$0")/lib/common.sh"

TD_HOME="${HOME}/.termux-dev"
TD_VERSION="1.0.0"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

say()  { printf '%s\n' "${C_DIM}•${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GREEN}✓${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}!${C_RESET} $*" >&2; }
err()  { printf '%s\n' "${C_RED}✗${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

step() { printf '\n%s\n' "${C_BOLD}${C_BLUE}▸ $*${C_RESET}"; }

is_termux() { [ -n "${PREFIX:-}" ] && case "$PREFIX" in *com.termux*) return 0;; *) return 1;; esac; }

have() { command -v "$1" >/dev/null 2>&1; }

# ينفّذ أمراً ويعيد 0 لو نجح، بدون إخراج صاخب.
try() { "$@" >/dev/null 2>&1; }

# وضع عدم التفاعل: ./setup.sh -y  أو  TD_ASSUME_YES=1
assume_yes() { [ "${TD_ASSUME_YES:-0}" = "1" ]; }

confirm() {
  local prompt="${1:-متأكد؟}" reply
  if assume_yes; then return 0; fi
  if [ ! -t 0 ]; then
    warn "لا يوجد تفاعل (stdin مقفول) — تم تخطي: $prompt"
    return 1
  fi
  printf '%s [y/N] ' "${prompt}" >&2
  read -r reply
  case "$reply" in [yY]|[yY][eE][sS]) return 0;; *) return 1;; esac
}

# IP المحلي بدون أي حزم إضافية (الاتصال لا يُرسل بيانات فعلياً).
local_ip() {
  if have ip; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -1
  fi
  if [ -z "${REPLY_IP:-}" ] && have python3; then
    python3 - <<'PY' 2>/dev/null
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("1.1.1.1", 80))
    print(s.getsockname()[0])
except Exception:
    pass
finally:
    s.close()
PY
  fi
}

# طبقة أمان على ~/.bashrc: بلوك له بداية/نهاية حتى لا يتكرّر التثبيت.
BASHRC="${HOME}/.bashrc"
TD_MARK_BEGIN="# >>> termux-dev >>>"
TD_MARK_END="# <<< termux-dev <<<"

patch_bashrc() {
  local block="$1"
  touch "$BASHRC"
  if grep -qF "$TD_MARK_BEGIN" "$BASHRC" 2>/dev/null; then
    local tmp; tmp="$(mktemp)"
    awk -v b="$TD_MARK_BEGIN" -v e="$TD_MARK_END" '
      index($0,b){skip=1; next } index($0,e){skip=0; next} !skip {print}
    ' "$BASHRC" > "$tmp" || { rm -f "$tmp"; return 1; }
    printf '%s\n%s\n%s\n' "$TD_MARK_BEGIN" "$block" "$TD_MARK_END" >> "$tmp"
    cat "$tmp" > "$BASHRC"
    rm -f "$tmp"
  else
    printf '\n%s\n%s\n%s\n' "$TD_MARK_BEGIN" "$block" "$TD_MARK_END" >> "$BASHRC"
  fi
  ok "تم تحديث ${BASHRC}"
}
