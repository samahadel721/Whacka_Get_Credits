#!/usr/bin/env bash
# ============================================================
#  serve.sh — سيرفر تطوير على 0.0.0.0 عشان تفتحه من متصفح الموبايل
#  تشغيل:
#    bash serve.sh [المجلد] [--port 8080] [--node] [--tailnet]
#  ملاحظة أمنية: أي جهاز على نفس الشبكة (واي فاي/هوتسبوت) يقدر يفتح الرابط —
#  لا تخدم ملفات حساسة (.env, مفاتيح) عبره. نضيف مسارات الخطر افتراضياً.
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

DIR="$PWD"
PORT="${PORT:-8080}"
MODE="auto"     # auto | node | python
OPEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --port|-p) PORT="${2:?}"; shift 2 ;;
    --node) MODE="node"; shift ;;
    --python) MODE="python"; shift ;;
    --open) OPEN=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) DIR="$1"; shift ;;
  esac
done
[ -d "$DIR" ] || die "المجلد غير موجود: $DIR"
DIR="$(cd "$DIR" && pwd)"

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  die "منفذ غير صالح: $PORT"
fi

# هل المنفذ مشغول؟
if have python3; then
  if python3 - "$PORT" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.4)
sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)
PY
  then
    die "المنفذ ${PORT} مشغول — جرّب: --port $((PORT + 1))"
  fi
fi

IP="$(local_ip | head -1 || true)"
[ -n "${IP:-}" ] || IP="127.0.0.1"

printf '\n%s\n' "${C_BOLD}سيرفر تطوير${C_RESET}"
say "المسار:   ${DIR}"
say "محلي:     http://127.0.0.1:${PORT}"
say "من الموبايل/الشبكة: ${C_BOLD}http://${IP}:${PORT}${C_RESET}"
if [ -f "${DIR}/.env" ]; then
  warn "في ملف .env داخل هذا المجلد — السكربت يخدم ملفات ثابتة فقط، لكن لا تضع أسرار هنا."
fi

cleanup() { printf '\n%s\n' "${C_DIM}تم الإيقاف.${C_RESET}"; exit 0; }
trap cleanup INT TERM

if [ "$OPEN" = "1" ] && is_termux && have termux-open-url; then
  termux-open-url "http://127.0.0.1:${PORT}"
fi

step "تشغيل (${MODE}) — Ctrl+C للإيقاف"
if [ "$MODE" = "node" ] || { [ "$MODE" = "auto" ] && have node && [ -f "${DIR}/package.json" ]; }; then
  have node || die "node غير مثبّت"
  if have npm && [ -f "${DIR}/package.json" ] && grep -q '"dev"' "${DIR}/package.json"; then
    exec env PORT="$PORT" HOST="0.0.0.0" npm --prefix "$DIR" run dev
  fi
  exec node "${DIR}/server.js"
fi

if have python3; then
  cd "$DIR"
  exec python3 - "$PORT" <<'PY'
import http.server
import socketserver
import sys

port = int(sys.argv[1])
# مسارات لا يجوز أن تُخدم من سيرفر تطوير مكشوف على الشبكة
SENSITIVE = (".env", ".git", "id_rsa", "id_ed25519", ".npmrc", ".ssh/", "node_modules/.package-lock.json")


def blocked(path: str) -> bool:
    p = "/" + path.replace("\\", "/").lstrip("/")
    return any(seg in p for seg in SENSITIVE)


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        if blocked(self.path.split("?", 1)[0]):
            self.send_error(403, "Blocked by termux-dev serve.sh (sensitive path)")
            return None
        return super().send_head()

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s %s\n" % (self.address_string(), fmt % args))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with Server(("0.0.0.0", port), Handler) as httpd:
    print("  serving on 0.0.0.0:%d  (Ctrl+C للإيقاف)" % port)
    httpd.serve_forever()
PY
fi

have node || die "لا python3 ولا node متاحان — نفّذ: bash setup.sh -y"
