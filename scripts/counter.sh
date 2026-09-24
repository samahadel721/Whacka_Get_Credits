#!/usr/bin/env bash
# ============================================================
#  counter.sh — يفحص «عداد الزوار» في موقعك: توصل للموقع؟ العدّاد موجود في
#  الـ HTML؟ وبيتحرك فعلًا مع كل طلب؟
#
#  الأداة بتعمل طلبات HTTP عادية زي اللي المتصفح بيعمله وبتقرا الرد.
#  مفيش أي توليد زيارات ولا أرقام مزوّرة — دي أداة تشخيص لموقع أنت صاحبه.
#
#  التشغيل:
#    bash counter.sh https://example.com             # فحص سريع (3 طلبات)
#    bash counter.sh http://192.168.1.20:3000 --tries 6 --gap 2
#    bash counter.sh https://example.com --bust      # يكسر كاش الـ CDN
#    bash counter.sh https://example.com --json      # للـ scripts/CI
#    bash counter.sh https://example.com --save /tmp/page.html
#
#  أرقام الخروج:
#    0 = عدّاد شغال وبيتحرك · 3 = عدّاد موجود بس ثابت
#    5 = عنصر العدّاد موجود فاضي (الرقم بيتحقن بالـ JS أو API فاشل)
#    1 = مفيش عدّاد خالص        ·   2 = مفيش وصول   ·  4 = استخدام غلط
# ============================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${HERE}/lib/common.sh"

URL=""
TRIES=3
GAP="1.2"
JSON=0
BUST=0
SAVE=""
UA="termux-dev-counter/1.0 (+تشخيص ذاتي)"

usage() { awk 'NR > 1 { if (!/^#/) exit; line = $0; sub(/^# ?/, "", line); if (line ~ /^=+$/) next; print line }' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tries=*) TRIES="${1#*=}" ;;
    --tries)   TRIES="${2:-3}"; shift ;;
    --gap=*)   GAP="${1#*=}" ;;
    --gap)     GAP="${2:-1.2}"; shift ;;
    --ua=*)    UA="${1#*=}" ;;
    --ua)      UA="${2:-}"; shift ;;
    --save=*)  SAVE="${1#*=}" ;;
    --save)    SAVE="${2:-}"; shift ;;
    --json)    JSON=1 ;;
    --bust)    BUST=1 ;;
    -h|--help) usage; exit 0 ;;
    -*)        printf 'خيار غير معروف: %s (جرّب --help)\n' "$1" >&2; exit 4 ;;
    *)
      if [ -z "$URL" ]; then URL="$1"; else printf 'رابط واحد بس.\n' >&2; exit 4; fi
      ;;
  esac
  shift
done

if ! [[ "$URL" =~ ^https?:// ]]; then
  printf 'لازم رابط يبدأ بـ http:// أو https://\n' >&2
  exit 4
fi
if ! [[ "$TRIES" =~ ^[0-9]+$ ]] || [ "$TRIES" -lt 1 ] || [ "$TRIES" -gt 25 ]; then
  printf '--tries بين 1 و25\n' >&2
  exit 4
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/td-counter.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

CURL_EXTRA=()
if [ "$BUST" = "1" ]; then
  CURL_EXTRA+=(-H 'Cache-Control: no-cache' -H 'Pragma: no-cache')
fi

# ── جلب الصفحة ───────────────────────────────────────────────────────────
fetch() { # <رقم المحاولة> → "code|time|bytes|redirects|type"
  local i="$1" target="$URL"
  if [ "$BUST" = "1" ]; then
    case "$URL" in
      *\?*) target="${URL}&_bust=${i}.${RANDOM}" ;;
      *)    target="${URL}?_bust=${i}.${RANDOM}" ;;
    esac
  fi
  curl -sS -L --max-time 25 -A "$UA" ${CURL_EXTRA[@]+"${CURL_EXTRA[@]}"} \
    -D "${WORK}/${i}.head" -o "${WORK}/${i}.html" \
    -w '%{http_code}|%{time_total}|%{size_download}|%{num_redirects}|%{content_type}' \
    "$target" 2>"${WORK}/${i}.err"
}

# ── مرشّحات العدّاد ──────────────────────────────────────────────────────
markup_lines() { # <ملف> → وسوم فيها اسم «عدّاد» + ما بعدها
  grep -oiE '(id|class|data-[a-z0-9-]+)="[^"]*(visit(ors?|_?(count|counter))?|counter|hit[_-]?(count|tracker)|page[_-]?views?|views?|زائر(ين)?|زيارات|مشاهدات|عدّاد|عداد)[^"]*"[^>]{0,60}(>[^<]{0,60})?' "$1" 2>/dev/null | head -8 || true
}

text_lines() { # <ملف> → نص مقروء زي «عدد الزوار: 42»
  sed 's/<[^>]*>/ /g; s/&nbsp;/ /g' "$1" 2>/dev/null \
    | tr '\n' ' ' | tr -s ' \t' ' ' \
    | grep -oiE '(عدد[[:space:]]*)?(الزوار|زيارات|زائر|مشاهدات|views?|visitors?|hits?|counter)[^0-9<]{0,25}[0-9][0-9,.]{0,12}' \
    | head -6 || true
}

first_number() { # <سطر> → أول رقم بلا فواصل (أو فراغ)
  local n
  n="$(printf '%s' "${1:-}" | grep -oE '[0-9][0-9,.]{0,12}' | head -1 || true)"
  n="${n//,/}"
  n="${n%%.}"
  printf '%s' "$n"
}

VENDOR_NAMES=(
  "Google Analytics 4/gtag" "Google Tag Manager" "Plausible" "Fathom" "Matomo/Piwik"
  "amung.us" "Histats" "StatCounter" "Clicky" "Cloudflare Insights" "Yandex Metrica" "Hotjar"
)
VENDOR_RES=(
  'googletagmanager\.com/gtag/js|gtag\(["'\'']\.?config'
  'googletagmanager\.com/(gtm|ns)\.js'
  'plausible\.io'
  'cdn\.usefathom\.com'
  'matomo|piwik\.js'
  'amung\.us'
  'histats\.com'
  'statcounter\.com'
  'getclicky'
  'static\.cloudflareinsights\.com'
  'mc\.yandex\.ru'
  'static\.hotjar\.com'
)

measure_id() { # <ملف> → معرّف GA4/GTM لو موجود
  grep -oE 'G-[A-Z0-9]{6,12}|UA-[0-9]{4,10}-[0-9]+|GTM-[A-Z0-9]{4,10}' "$1" 2>/dev/null | head -1 || true
}

vendors_in() { # <ملف> → أسماء خدمات الإحصاء الموجودة
  local f="$1" i
  for i in "${!VENDOR_NAMES[@]}"; do
    if grep -qiE "${VENDOR_RES[$i]}" "$f" 2>/dev/null; then
      printf '%s\n' "${VENDOR_NAMES[$i]}"
    fi
  done
}

cache_lines() { # <ملف هيدرات>
  grep -iE '^(cache-control|x-cache|age|cf-cache-status|expires|via|x-varnish|x-fastly)' "$1" 2>/dev/null \
    | tr -d '\r' | head -4 || true
}

# ── التشغيل ────────────────────────────────────────────────────────────────
meta="$(fetch 1)" || meta="000|0|0|0|-"
IFS='|' read -r CODE TTIME BYTES REDIRS CTYPE <<<"$meta"
if [ -z "${CODE:-}" ]; then CODE="000"; fi

if [ "$CODE" = "000" ]; then
  if [ "$JSON" = "1" ]; then
    printf '{"url":"%s","reachable":false,"http_code":0,"error":"%s"}\n' \
      "${URL//\"/\\\"}" "$(tr -d '"\n\r' <"${WORK}/1.err" 2>/dev/null | head -c 120 || true)"
  else
    err "مفيش وصول للرابط ($(tr -d '\n' <"${WORK}/1.err" 2>/dev/null | head -c 160 || true))"
    say "اتأكد من الرابط والمنفذ. لو السيرفر المحلي شايل الموقع: bash scripts/serve.sh ~/projects/demo"
  fi
  exit 2
fi

if [ -n "$SAVE" ]; then
  cp "${WORK}/1.html" "$SAVE" 2>/dev/null || true
fi

VALUES=()
MARKUP_COUNT=0
VALUE_SEEN=0
VENDORS=""
GA_ID=""
i=1
while [ "$i" -le "$TRIES" ]; do
  if [ "$i" != "1" ]; then
    sleep "$GAP"
    meta="$(fetch "$i")" || meta="000|0|0|0|-"
    IFS='|' read -r c2 _t2 _b2 _r2 _ct2 <<<"$meta"
    if [ "$c2" = "000" ]; then
      VALUES+=("-")
      i=$((i + 1))
      continue
    fi
  fi
  mk="$(markup_lines "${WORK}/${i}.html")"
  tx="$(text_lines "${WORK}/${i}.html")"
  if [ "$i" = "1" ]; then
    if [ -n "$mk" ]; then
      MARKUP_COUNT="$(printf '%s\n' "$mk" | grep -c . || true)"
    fi
    VENDORS="$(vendors_in "${WORK}/1.html")"
    GA_ID="$(measure_id "${WORK}/1.html")"
  fi
  val="$(printf '%s\n%s\n' "$mk" "$tx" | grep -oE '[0-9][0-9,.]{0,12}' | head -1 || true)"
  num="$(first_number "$val")"
  VALUES+=("$num")
  if [ -n "$num" ]; then VALUE_SEEN=1; fi
  i=$((i + 1))
done

# العدّاد «مُقيّم» فعلًا لما يبقى فيه رقم في الرد؛ وجود وسم باسم عدّاد بس
# معناه إن الرقم بيتحقن بالـ JS أو إن السيرفر بيرجّعه فاضي.
INC=0
prev=""
for v in "${VALUES[@]}"; do
  if [ "$v" = "-" ] || [ -z "$v" ]; then continue; fi
  if [ -n "$prev" ] && [ "$v" != "$prev" ]; then INC=1; fi
  prev="$v"
done

VERDICT="absent"
RC=1
if [ "$VALUE_SEEN" = "1" ]; then
  if [ "$INC" = "1" ]; then VERDICT="working"; RC=0; else VERDICT="static"; RC=3; fi
elif [ "${MARKUP_COUNT:-0}" -gt 0 ]; then
  VERDICT="unpopulated"; RC=5
fi

CACHE="$(cache_lines "${WORK}/1.head")"
HAS_COOKIE=0
if grep -qiE '^set-cookie' "${WORK}/1.head" 2>/dev/null; then HAS_COOKIE=1; fi

# ── الإخراج ────────────────────────────────────────────────────────────────
if [ "$JSON" = "1" ]; then
  vals=""
  for v in "${VALUES[@]}"; do
    case "$v" in ''|-) v="null" ;; esac
    vals="${vals:+$vals,}$v"
  done
  vend=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    vend="${vend:+$vend,}\"$line\""
  done <<EOF
$VENDORS
EOF
  printf '{"url":"%s","reachable":true,"http_code":%s,"time_total_s":"%s","bytes":%s,"redirects":%s,"content_type":"%s","counter_found":%s,"markup_candidates":%s,"counter_value_present":%s,"counter_values":[%s],"increments":%s,"vendors":[%s],"measure_id":"%s","set_cookie":%s,"verdict":"%s"}\n' \
    "${URL//\"/\\\"}" "$CODE" "${TTIME:-0}" "${BYTES:-0}" "${REDIRS:-0}" "${CTYPE:-}" \
    "$([ "$VALUE_SEEN" = 1 ] || [ "${MARKUP_COUNT:-0}" -gt 0 ] && echo true || echo false)" \
    "${MARKUP_COUNT:-0}" \
    "$([ "$VALUE_SEEN" = 1 ] && echo true || echo false)" \
    "$vals" \
    "$([ "$INC" = 1 ] && echo true || echo false)" \
    "$vend" "$GA_ID" "$HAS_COOKIE" "$VERDICT"
  exit "$RC"
fi

printf '\n── فحص عدّاد الزوار ──\n'
printf 'الرابط: %s\n' "$URL"
if [ "$BUST" = "1" ]; then printf 'كسر الكاش: مفعل (--bust)\n'; fi

step "1) الوصول"
ok "HTTP ${CODE} · ${TTIME}s · ${BYTES} بايت · ${CTYPE:-?}"
if [ "${REDIRS:-0}" != "0" ]; then say "عدد التحويلات: ${REDIRS} (طبيعي لو فيه http→https أو www)"; fi
if [ "${CODE:-0}" -ge 400 ]; then warn "الرد فيه خطأ HTTP ${CODE} — صلّح ده الأول"; fi

step "2) عدّاد في الـ HTML؟"
if [ "${MARKUP_COUNT:-0}" -gt 0 ]; then
  printf '  لقيت %s عنصر مرشّح:\n' "${MARKUP_COUNT}"
  markup_lines "${WORK}/1.html" | sed 's/^/      /'
  tx="$(text_lines "${WORK}/1.html")"
  if [ -n "$tx" ]; then
    printf '    نص مقروء:\n'
    printf '%s\n' "$tx" | sed 's/^/      /'
  fi
  if [ "$VALUE_SEEN" != "1" ]; then
    warn "العنصر موجود بس مفيش فيه رقم في الرد — الرقم بيتحقن بالـ JS أو السيرفر بيرجّعه فاضي"
  fi
elif [ -n "$VENDORS" ]; then
  warn "مفيش عدّاد ظاهر في الـ HTML — فيه خدمة إحصاء بس (الرقم بيتحسّب في المتصفح/الخادم)"
else
  err "مفيش أي عنصر عدّاد في الـ HTML"
fi

step "3) خدمات إحصاء"
if [ -n "$VENDORS" ]; then
  printf '%s\n' "$VENDORS" | sed 's/^/  ✓ /'
  if [ -n "$GA_ID" ]; then say "معرّف القياس: ${GA_ID} (تلاقيه في GA4 → Reports → Realtime)"; fi
else
  say "مفيش خدمة إحصاء معروفة في الصفحة"
fi

step "4) الرقم بيتحرك؟ (${TRIES} طلبات، فاصل ${GAP}ث، من غير كوكيز)"
vals_pretty=""
for v in "${VALUES[@]}"; do
  vals_pretty="${vals_pretty:+$vals_pretty · }${v:--}"
done
printf '  القيم: %s\n' "$vals_pretty"
if [ -n "$CACHE" ]; then
  printf '  هيدرات الكاش:\n'
  printf '%s\n' "$CACHE" | sed 's/^/      /'
  case "$CACHE" in
    *HIT*|*'max-age'*) warn "الرقم ممكن يكون ثابت بسبب الكاش — جرّب --bust" ;;
  esac
fi
if [ "$HAS_COOKIE" = "1" ]; then
  say "السيرفر بيحط Set-Cookie: لو العدّاد بيعتمد على الكوكيز فمش منطقية تزيد من غير متصفح — ده سلوك سليم مش عطل."
fi

step "الحكم"
case "$VERDICT" in
  working)
    ok "العدّاد شغال: بيرقّم رقم وبيتغير مع كل طلب." ;;
  static)
    warn "لقيت عدّاد بس الرقم ما اتغيرش بين الطلبات."
    say "الأسباب المحتملة: بيعدّ زائر جديد مرة واحدة في اليوم/IP · كاش CDN (جرّب --bust) ·"
    say "الصفحة بيتعملها توليد مرة واحدة (static) · الرقم بيتقرا من كوكيز."
    say "التأكيد النهائي: افتحها في متصفح الموبايل، وبعدين في نافذة تصفح خفي، وقارن." ;;
  unpopulated)
    warn "في عنصر عدّاد في الـ HTML بس فاضي من جوه (مفيش رقم في الرد)."
    say "ده معناه عادةً: السكربت اللي بيملى العدّاد فشل/ممنوع (CSP أو CORS)، أو بيوصل لـ API بيرجع خطأ."
    say "جرّب:  curl -i <عنوان الـ API بتاع العدّاد>  وشوف الكود، وافتح الكونسول في المتصفح." ;;
  absent)
    err "مفيش عدّاد زيارات في الصفحة."
    say "لو المفروض يوجد: اتأكد إن العدّاد بيتطبع في الرد (مش في قالب تاني/بيُحقن بالـ JS)"
    say "وإن الطلب بيوصل أصلًا لنقطة التسجيل. شوف docs/TROUBLESHOOTING.md لخطوات التتبع." ;;
esac
exit "$RC"
