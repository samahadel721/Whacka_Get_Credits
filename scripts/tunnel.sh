#!/usr/bin/env bash
# ============================================================
#  tunnel.sh — فتح رابط مؤقت للتجربة أثناء التطوير (dev only)
#  مفيد لما تكون بتطوّر API على الموبايل وعايز تجرّبه من جهاز/متصفح تاني
#  أو تستقبل webhook من خدمة خارجية أثناء التطوير.
#  التشغيل:
#    bash tunnel.sh 8080
#  ⚠️  الرابط الذي سيظهر عام على الإنترنت: لا تترك سيرفر فيه أسرار أو بيانات مستخدمين مفتوحاً.
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

PORT="${1:-8080}"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "منفذ غير صالح: $PORT"

step "نفق تجريبي للمنفذ ${PORT}"
warn "الرابط الناتج يمكن لأي شخص معرفته الوصول له — استخدمه للتحربة فقط وأغلقه بعدها."

start_cloudflared() {
  say "استخدام cloudflared (quick tunnel — بدون حساب)"
  exec cloudflared tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate
}

start_ngrok() {
  say "استخدام ngrok"
  exec ngrok http "$PORT"
}

start_ssh() {
  # fallback بلا أي تثبيت: serveo عبر SSH (خدمة تجارب عامة)
  say "استخدام serveo.net عبر ssh"
  exec ssh -tt -R 80:localhost:"${PORT}" nokey@serveo.net 2>/dev/null
}

if have cloudflared; then start_cloudflared; fi
if have ngrok; then start_ngrok; fi
if have npx; then
  say "لا cloudflared ولا ngrok — سنستخدم localtunnel عبر npx (أول تشغيل يحمّل الحزمة)"
  exec npx --yes localtunnel --port "$PORT" --print-url
fi
if have ssh; then start_ssh; fi

die "ما فيش أداة أنفاق متاحة. ثبّت إحداهما:
  pkg install -y openssh                       # serveo (الأخف)
  npm install -g localtunnel                   # أو متاحة تلقائياً عبر npx
  # cloudflared: حمّل أحدث إصدار من github.com/cloudflare/cloudflared/releases (linux-arm64 يعمل على Termux)"
