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

# ---------------------------------------------------------------------------
# إيجاد الـ PIDs التي تستمع على بورت معيّن — بدون اعتماديات خارجية.
# ss/lsof اختيارية إن وُجدتا، وإلا نقرأ /proc مباشرة — فيشتغل على Termux مجرد من أي حزمة.
pids_listening_on() {
  local port="$1" inodes="" pid out=""
  [ -n "$port" ] || return 1

  if have ss; then
    out="$(ss -Hltnp "sport = :$port" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)"
  elif have lsof; then
    out="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u)"
  fi

  if [ -z "$out" ]; then
    local hex; hex="$(printf '%04X' "$port")"
    inodes="$(awk -v h="$hex" '$2 ~ (":" h "$") && $4 == "0A" {print $10}' \
              /proc/net/tcp /proc/net/tcp6 2>/dev/null | sort -u)"
    [ -n "$inodes" ] || return 1
    local fd
    for fd in /proc/[0-9]*/fd/*; do
      local target; target="$(readlink "$fd" 2>/dev/null)" || continue
      case "$target" in socket:*) ;; *) continue ;; esac
      local ino="${target#socket:[}"; ino="${ino%]}"
      case $'\n'"$inodes"$'\n' in
        *$'\n'"$ino"$'\n'*) pid="${fd#/proc/}"; pid="${pid%%/*}"; out="$out${nl}$pid"; nl=$'\n' ;;
      esac
    done
  fi

  [ -n "$out" ] || return 1
  printf '%s\n' "$out" | tr ' \n' '\n\n' | grep -E '^[0-9]+$' | sort -u
}

# إيقاف كل ما يسمع على بورت، مع تصعيد لطيف ثم قسري.
stop_port() {
  local port="$1" pids killed=0 p
  pids="$(pids_listening_on "$port" || true)"
  [ -n "$pids" ] || return 1
  for p in $pids; do
    kill -TERM "$p" 2>/dev/null && killed=$((killed + 1))
    printf '%s\n' "${C_DIM}  SIGTERM → pid $p ($(cat "/proc/$p/comm" 2>/dev/null || echo '?'))${C_RESET}"
  done
  sleep 1
  for p in $pids; do
    if kill -0 "$p" 2>/dev/null; then kill -KILL "$p" 2>/dev/null; printf '  %sSIGKILL → pid %s%s\n' "$C_YELLOW" "$p" "$C_RESET"; fi
  done
  [ "$killed" -gt 0 ]
}

# ---------------------------------------------------------------------------
# ملفات التثبيت (profiles) — مشتركة بين setup.sh و disk.sh
TD_PKG_CORE=(git curl wget ripgrep jq zip unzip tar gnutar openssh nano)
TD_PKG_NODE=(nodejs-lts)
TD_PKG_PY=(python python-pip)
TD_PKG_EXTRA=(tmux tree fd)

td_profile_packages() { # <profile> → قائمة الحزم
  local profile="${1:-full}"
  case "$profile" in
    full)    printf '%s\n' "${TD_PKG_CORE[@]}" "${TD_PKG_NODE[@]}" "${TD_PKG_PY[@]}" "${TD_PKG_EXTRA[@]}" ;;
    minimal) printf '%s\n' "${TD_PKG_CORE[@]}" "${TD_PKG_NODE[@]}" ;;
    python)  printf '%s\n' "${TD_PKG_CORE[@]}" "${TD_PKG_PY[@]}" ;;
    tools)   printf '%s\n' "${TD_PKG_CORE[@]}" ;;
    *) return 1 ;;
  esac
}

td_profiles() { printf 'full minimal python tools\n'; }

# تقدير المساحة قبل التثبيت من apt نفسه (محاكاة بلا تنزيل).
# يعيد سطرًا: "<حزم جديدة> <حجم التنزيل> <المساحة الإضافية>" أو يفشل بهدوء.
apt_projection() { # <profile>
  local profile="${1:-full}" pkgs=() line dl extra new
  mapfile -t pkgs < <(td_profile_packages "$profile") || return 1
  local apt_cmd=""
  for cand in "apt-get" "apt"; do
    have "$cand" && { apt_cmd="$cand"; break; }
  done
  [ -n "$apt_cmd" ] || return 1

  line="$("$apt_cmd" -s install "${pkgs[@]}" 2>/dev/null \
          | grep -E 'Need to get|additional disk space|newly installed' | tr '\n' '|' )"
  [ -n "$line" ] || return 1

  # grep -oE بدل sed: أنماط sed greedy كانت تبتلع جزءًا من الرقم
  new="$(grep -oE '[0-9]+ newly installed' <<<"$line" | head -1 | awk '{print $1}')"
  dl="$(grep -oE 'Need to get [0-9.]+ [kMG]B' <<<"$line" | head -1 | awk '{print $4" "$5}')"
  extra="$(grep -oE '[0-9.]+ ?[kMG]B of additional disk space' <<<"$line" | head -1 | sed 's/ of additional disk space//')"
  printf '%s|%s|%s\n' "${new:-?}" "${dl:-?}" "${extra:-?}"
}
