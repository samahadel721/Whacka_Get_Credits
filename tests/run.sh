#!/usr/bin/env bash
# ============================================================
#  tests/run.sh — اختبارات تكامل لهذا المستودع.
#  تشغّل الخوادم فعليًا على منافذ عشوائية وتتحقق من الاستجابات،
#  وتختبر سكربتات الـ toolkit داخل HOME وهمي حتى لا تلمس جهازك.
#  تشغيل:  bash tests/run.sh      (أو: make test)
# ============================================================
# لا -u هنا: مصادرة غير مقصودة لمتغيّر داخل نص مُمرَّر لـ bash -c كانت تُسكت
# السكربت في منتصف الملف. سكربتات الأدوات نفسها تبقى على set -u.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1     # لا ملفات .pyc داخل القوالب أثناء الاختبار
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${ROOT}/.tmp-tests-XXXXXX")"
PIDS=""
cleanup() {
  for pid in $PIDS; do kill "$pid" 2>/dev/null; done
  # إغلاق بالمنفذ: يقتل حتى العمليات التي تنفصل عن الأب (python/node children)
  local pp
  for pp in $PORTS_USED; do
    bash "$ROOT/scripts/serve.sh" --stop --port "$pp" >/dev/null 2>&1
  done
  pkill -f "$TMP" 2>/dev/null
  rm -rf "$TMP"
  # نظافة المستودع بعد الاختبارات: لا مجلدات ولا كاش متروك
  if ls -d "$ROOT"/.tmp-tests-* >/dev/null 2>&1; then
    printf '  %s!%s مجلد اختبار لم يُحذف: %s\n' "$R" "$N" "$(ls -d "$ROOT"/.tmp-tests-* | head -1 | xargs basename 2>/dev/null)"
  fi
  if find "$ROOT/templates" -name '__pycache__' -o -name '*.pyc' | grep -q .; then
    printf '  %s!%s بقايا __pycache__ داخل القوالب\n' "$R" "$N"
  fi
  # py_compile/unittest يخلّفان __pycache__ داخل القوالب — لا نترك أثرًا في المستودع
  rm -rf "$ROOT"/templates/*/__pycache__ "$ROOT"/templates/*/*/__pycache__
}
trap cleanup EXIT INT TERM

PASS=0 FAIL=0
PORTS_USED=""
track_port() { # <port> — يسجّل المنفذ ليُغلق في التنظيف (لا يُنادى داخل $() )
  PORTS_USED="$PORTS_USED $1"
}
if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; D=$'\033[2m'; N=$'\033[0m'
else
  G=""; R=""; Y=""; B=""; D=""; N=""
fi

t() { # "اسم الاختبار" — أمر...
  local name="$1"; shift
  local out
  # </dev/null: لازم — وإلا أي أمر يقرأ stdin سيلتهم بقية هذا السكربت
  if out="$("$@" 2>&1 </dev/null)"; then
    printf '  %s✓%s %s\n' "$G" "$N" "$name"; PASS=$((PASS + 1))
  else
    printf '  %s✗%s %s\n' "$R" "$N" "$name"; FAIL=$((FAIL + 1))
    printf '%s\n' "$out" | sed "s/^/      ${D}/" | tail -6
  fi
}
py_check() { python3 "$TMP/pycheck.py" "$1"; }

# لا نعدّ سيرفرات المستخدم الشغّالة فعلًا (مثلًا preview على 8080) — نفحص فقط
# العمليات التي تعمل من داخل مجلد هذا التشغيل أو من داخل القوالب.
no_stray_servers() {
  local d cwd pid cmd bad=""
  for d in /proc/[0-9]*/cwd; do
    cwd="$(readlink "$d" 2>/dev/null)" || continue
    case "$cwd" in
      "$TMP"*|"$ROOT"/templates*) ;;
      *) continue ;;
    esac
    pid="${d#/proc/}"; pid="${pid%/cwd}"
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
    case "$cmd" in
      *server.js*|*app.py*|*http.server*|*serve.sh*) bad="$bad ${pid}($(basename "$cwd"))" ;;
    esac
  done
  if [ -n "$bad" ]; then
    printf '      شاردة من الاختبارات: %s\n' "$bad"
    return 1
  fi
  return 0
}
json_shape_ok() {
  local out
  if ! out="$( { bash "$ROOT/scripts/disk.sh" --json 2>&1 </dev/null | python3 "$TMP/jsonshape.py"; } 2>&1)"; then
    printf '%s\n' "$out"
    return 1
  fi
  printf '%s\n' "$out"
  return 0
}
section() { printf '\n%s%s%s\n' "$B" "$1" "$N"; }
skip()    { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }

code()      { curl -sS -m 5 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
post_code() { curl -sS -m 5 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data "$2" "$1" 2>/dev/null || echo 000; }
get()       { curl -sS -m 5 "$1" 2>/dev/null; }
# جلب حقل من JSON عبر مسار نقطي:  jsonget <url> items.0.id
jsonget()   { get "$1" | node "$TMP/jsonget.js" "${2:-}"; }

wait_port() { # host port [ثوانٍ]
  local host="$1" port="$2" deadline=$((SECONDS + ${3:-20}))
  while [ $SECONDS -lt $deadline ]; do
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then exec 3<&- 2>/dev/null; return 0; fi
    sleep 0.25
  done
  return 1
}

free_port() {
  if [ "$HAVE_PY" = "1" ]; then
    python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()' 2>/dev/null
  else
    echo $(( (RANDOM % 2000) + 18000 ))
  fi
}

HAVE_NODE=0; command -v node    >/dev/null 2>&1 && HAVE_NODE=1
HAVE_PY=0;   command -v python3 >/dev/null 2>&1 && HAVE_PY=1
HAVE_CURL=0; command -v curl    >/dev/null 2>&1 && HAVE_CURL=1
HAVE_GIT=0;  command -v git     >/dev/null 2>&1 && HAVE_GIT=1

# كتابة الملفات المساعدة سطرًا بسطر — بديل here-doc: السكربت يُقرأ تدريجيًا،
# وhere-doc وقت التشغيل يعتمد على إعادة القراءة من نفس الـ fd، وهو ما ينكسر إذا
# لامست عملية فرعية ذلك الـ fd (سبب توقف صامت في منتصف الملف).
emit() { # <path> <mode> <سطر...>
  local f="$1" mode="$2" line
  shift 2
  : > "$f"
  for line in "$@"; do printf '%s\n' "$line" >> "$f"; done
  chmod "$mode" "$f"
}

emit "$TMP/pycheck.py" 644 \
  'import sys' \
  'path = sys.argv[1]' \
  'compile(open(path, encoding="utf-8").read(), path, "exec")'

emit "$TMP/jsonshape.py" 644 \
  'import json' \
  'import sys' \
  '' \
  'd = json.load(sys.stdin)' \
  'for key in ("repo_apparent_bytes", "repo_kb", "files", "lines", "free_kb"):' \
  '    assert key in d, "missing key: " + key' \
  'assert d["repo_kb"] > 0, "repo_kb is zero"' \
  'assert d["repo_apparent_bytes"] > 10000, "implausible repo size"' \
  'print("      repo_kb=%s files=%s lines=%s" % (d["repo_kb"], d["files"], d["lines"]))'

emit "$TMP/jsonget.js" 755 \
  'let d = "";' \
  'process.stdin.on("data", (c) => (d += c)).on("end", () => {' \
  '  const path = String(process.argv[2] || "").split(".").filter(Boolean);' \
  '  let v;' \
  '  try {' \
  '    v = JSON.parse(d);' \
  '    for (const k of path) v = Array.isArray(v) ? v[Number(k)] : v[k];' \
  '  } catch {' \
  '    process.exit(1);' \
  '  }' \
  '  if (v === undefined || v === null) process.exit(1);' \
  '  console.log(typeof v === "object" ? JSON.stringify(v) : String(v));' \
  '});'

long_title_code() { # <url> → كود استجابة لعنوان بطول 250 حرفًا (الحد المسموح 200)
  local url="$1" long code
  long="$(printf 'x%.0s' $(seq 1 250))"
  code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X POST \
      -H 'content-type: application/json' \
      --data "{\"title\":\"$long\"}" "$url" 2>/dev/null || echo 000)"
  printf '%s' "$code"
}

long_title_is_422() { # <port>
  local code
  code="$(long_title_code "http://127.0.0.1:$1/api/items")"
  [ "$code" = "422" ]
}

printf '%s\n' "${B}termux-dev — اختبارات التكامل${N}"
printf '%s\n' "${D}node=$HAVE_NODE python=$HAVE_PY curl=$HAVE_CURL git=$HAVE_GIT${N}"

# ================================================================ 1
section "1) صيغة كل الملفات"
for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh "$ROOT"/tests/run.sh; do
  t "bash -n $(basename "$f")" bash -n "$f"
done
if [ "$HAVE_NODE" = "1" ]; then
  while IFS= read -r f; do t "node --check ${f#"$ROOT"/}" node --check "$f"; done < <(find "$ROOT/templates" -name '*.js' | sort)
else
  skip "node غير متوفر"
fi
if [ "$HAVE_PY" = "1" ]; then
  for f in $(find "$ROOT/templates" -name '*.py' | sort); do t "compile-check ${f#"$ROOT"/}" py_check "$f"; done
else
  skip "python3 غير متوفر"
fi

# ================================================================ 2
section "2) اكتمال ملفات القوالب"
check_template() {
  local tpl="$1"; shift
  local f
  for f in "$@"; do t "$tpl/$f" test -f "$ROOT/templates/$tpl/$f"; done
}
check_template node-api server.js package.json .env.example .gitignore README.md src/store.js src/rateLimit.js public/index.html test/api.test.js
check_template python-api app.py requirements.txt .gitignore README.md tests/test_api.py
check_template web-static index.html styles.css app.js .gitignore README.md

t "node-api/.gitignore يخفي data/"        bash -c "grep -q '^data/' '$ROOT/templates/node-api/.gitignore'"
t "node-api/.gitignore يخفي .env"         bash -c "grep -q '^\.env$' '$ROOT/templates/node-api/.gitignore'"
t "python-api/.gitignore يخفي data/"       bash -c "grep -q '^data/' '$ROOT/templates/python-api/.gitignore'"
t "كل قالب له README"                     bash -c "[ \$(ls -d $ROOT/templates/*/ | wc -l) -eq \$(ls $ROOT/templates/*/README.md | wc -l) ]"
t "لا اعتماديات تشغيل في package.json"     bash -c "! grep -q '\"dependencies\"' '$ROOT/templates/node-api/package.json'"

# ================================================================ 3
section "3) project.sh — توليد مشروع فعلي"
if [ "$HAVE_GIT" = "1" ]; then
  gen() { bash "$ROOT/scripts/project.sh" "$1" -t "$2" -d "$TMP/$1"; }
  t "توليد demo-node" gen demo-node node-api
  t "توليد demo-py"   gen demo-py python-api
  t "توليد demo-web"  gen demo-web web-static
  t "git init + أول commit"   git -C "$TMP/demo-node" log --oneline -1
  t "استبدال اسم المشروع"      bash -c "grep -q 'demo-node' '$TMP/demo-node/package.json'"
  t "لم يبقَ __PROJECT_NAME__" bash -c "! grep -rq '__PROJECT_NAME__' '$TMP/demo-node' '$TMP/demo-py' '$TMP/demo-web'"
  t "TEMPLATE.md غير منسوخ"    bash -c "! test -e '$TMP/demo-node/TEMPLATE.md'"
  t ".env نُسخ من .env.example" bash -c "test -f '$TMP/demo-node/.env' && cmp -s '$TMP/demo-node/.env' '$TMP/demo-node/.env.example'"
  t "رفض اسم فيه مسافة"         bash -c "! bash '$ROOT/scripts/project.sh' 'bad name' -t node-api -d '$TMP/nope' >/dev/null 2>&1"
  t "رفض قالب غير موجود"        bash -c "! bash '$ROOT/scripts/project.sh' x -t nope -d '$TMP/nope2' >/dev/null 2>&1"
  t "رفض وجهة موجودة مسبقًا"    bash -c "! bash '$ROOT/scripts/project.sh' demo-node -t node-api -d '$TMP/demo-node' >/dev/null 2>&1"
  t "project.sh --list"          bash "$ROOT/scripts/project.sh" --list
  t "project.sh --help"          bash "$ROOT/scripts/project.sh" --help
else
  skip "git غير متوفر — تخطي قسم project.sh"
fi

# ================================================================ 4
if [ "$HAVE_NODE" = "1" ] && [ "$HAVE_CURL" = "1" ]; then
  section "4) node-api — خادم حقيقي"
  P1="$(free_port)"; track_port "$P1"
  ( cd "$ROOT/templates/node-api" && PORT="$P1" HOST=127.0.0.1 DATA_DIR="$TMP/n1" node server.js >"$TMP/node.log" 2>&1 ) &
  N1=$!; PIDS="$PIDS $N1"
  U1="http://127.0.0.1:$P1"
  if wait_port 127.0.0.1 "$P1"; then
    t "GET /api/health → 200"      bash -c "[ \"$(code "$U1/api/health")\" = 200 ]"
    t "health يقول status ok"      bash -c "[ \"$(jsonget "$U1/api/health" status)\" = ok ]"
    t "POST /api/items → 201"      bash -c "[ \"$(post_code "$U1/api/items" '{"title":"اختبار"}')\" = 201 ]"
    t "العنصر ظهر في القائمة"      bash -c "[ \"$(jsonget "$U1/api/items" total)\" = 1 ]"
    t "العنوان محفوظ بالعربي"      bash -c "[ \"$(jsonget "$U1/api/items" 'items.0.title')\" = اختبار ]"
    t "title فارغ → 422"           bash -c "[ \"$(post_code "$U1/api/items" '{"title":""}')\" = 422 ]"
    t "title طويل جدًا → 422"      long_title_is_422 "$P1"
    t "JSON تالف → 400"            bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X POST --data '{oops' '$U1/api/items')\" = 400 ]"
    t "مسار مجهول → 404"           bash -c "[ \"$(code "$U1/api/zzz")\" = 404 ]"
    t "HEAD / → 200"               bash -c "[ \"\$(curl -sS -m 5 -I -o /dev/null -w '%{http_code}' '$U1/')\" = 200 ]"
    t "لوحة المتابعة تُخدم من /"  bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' '$U1/')\" = 200 ]"
    t "لوحة المتابعة فيها الإحصاءات" bash -c "curl -sS -m 5 '$U1/' | grep -q 's-items'"
    t "رؤوس أمان على الاستجابة"     bash -c "curl -sS -m 5 -D - -o /dev/null '$U1/api/health' | grep -qi 'x-content-type-options: nosniff'"
    t "path traversal محجوب"        bash -c "c=\$(curl -sS -m 5 --path-as-is -o /dev/null -w '%{http_code}' '$U1/../server.js'); [ \"\$c\" != 200 ] && [ \"\$c\" != 000 ]"
    t "ملف نقطة (.env) محجوب"       bash -c "c=\$(curl -sS -m 5 --path-as-is -o /dev/null -w '%{http_code}' '$U1/.env'); [ \"\$c\" = 403 ] || [ \"\$c\" = 404 ]"
    t "حذف العنصر → 204" bash -c "
        id=\$(curl -sS -m 5 '$U1/api/items' | node '$TMP/jsonget.js' items.0.id)
        c=\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X DELETE '$U1/api/items/'\"\$id\")
        [ \"\$c\" = 204 ]"
    t "حذف غير موجود → 404"         bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X DELETE '$U1/api/items/nope')\" = 404 ]"
    t "405 على PUT"                 bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X PUT '$U1/api/items')\" = 405 ]"
    t "بيانات كُتبت في DATA_DIR"     test -f "$TMP/n1/items.json"
    t "Rate limit: 429 بعد الحد"     bash -c "
        hit=0
        for i in \$(seq 1 150); do
          c=\$(curl -s -o /dev/null -w '%{http_code}' -H 'X-Forwarded-For: 203.0.113.7' '$U1/api/health')
          if [ \"\$c\" = 429 ]; then hit=1; break; fi
        done
        [ \"\$hit\" = 1 ]"
    t "IP آخر ما زال مسموحًا"        bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -H 'X-Forwarded-For: 198.51.100.4' '$U1/api/health')\" = 200 ]"
    t "SIGTERM يغلق بلا خطأ"         bash -c "kill -TERM $N1; for i in \$(seq 1 40); do kill -0 $N1 2>/dev/null || exit 0; sleep 0.1; done; exit 1"
    PIDS="${PIDS/ $N1/}"
    t "npm test الخاص بالقالب"       bash -c "cd '$ROOT/templates/node-api' && node --test --test-reporter=tap >/dev/null 2>&1"
  else
    skip "لم يبدأ node-api خلال 20 ثانية — node.log:"
    tail -15 "$TMP/node.log" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
fi

# ================================================================ 5
if [ "$HAVE_PY" = "1" ] && [ "$HAVE_CURL" = "1" ] && [ -d "$TMP/demo-py" ]; then
  section "5) python-api — خادم حقيقي"
  P2="$(free_port)"; track_port "$P2"
  ( cd "$TMP/demo-py" && PORT="$P2" HOST=127.0.0.1 DB_PATH="$TMP/py.db" python3 app.py >"$TMP/py.log" 2>&1 ) &
  P2PID=$!; PIDS="$PIDS $P2PID"
  U2="http://127.0.0.1:$P2"
  if wait_port 127.0.0.1 "$P2"; then
    t "GET /api/health → 200"      bash -c "[ \"$(code "$U2/api/health")\" = 200 ]"
    t "POST item → 201"            bash -c "[ \"$(post_code "$U2/api/items" '{"title":"بايثون"}')\" = 201 ]"
    t "العنصر محفوظ ومقروء"        bash -c "curl -sS -m 5 '$U2/api/items' | grep -q 'بايثون'"
    t "PATCH يبدّل done إلى 1"      bash -c "curl -sS -m 5 -X PATCH '$U2/api/items/1' | grep -q '\"done\": 1'"
    t "GET /api/items/1"            bash -c "curl -sS -m 5 '$U2/api/items/1' | grep -q '\"id\": 1'"
    t "title فارغ → 422"            bash -c "[ \"$(post_code "$U2/api/items" '{"title":""}')\" = 422 ]"
    t "limit مقيّد بـ 200"           bash -c "curl -sS -m 5 '$U2/api/items?limit=99999' | grep -q '\"limit\": 200'"
    t "PUT → 405 وليس 501"          bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X PUT '$U2/api/items')\" = 405 ]"
    t "مسار مجهول → 404"            bash -c "[ \"$(code "$U2/nope")\" = 404 ]"
    t "DELETE → 204"                bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X DELETE '$U2/api/items/1')\" = 204 ]"
    t "حذف مكرر → 404"              bash -c "[ \"\$(curl -sS -m 5 -o /dev/null -w '%{http_code}' -X DELETE '$U2/api/items/1')\" = 404 ]"
    t "حقن SQL لا يكسر الجدول"      bash -c "
        curl -sS -m 5 -o /dev/null -X POST -H 'content-type: application/json' --data '{\"title\":\"x; DROP TABLE items;--\"}' '$U2/api/items' >/dev/null
        curl -sS -m 5 '$U2/api/items' | grep -q 'DROP TABLE'"
    t "قيد CHECK يمنع عنصراً فارغاً" python3 -c "import sqlite3,sys
c=sqlite3.connect('$TMP/py.db')
try:
    c.execute(\"INSERT INTO items(title) VALUES ('')\"); sys.exit(1)
except sqlite3.IntegrityError:
    sys.exit(0)"
    t "WAL مفعّل على قاعدة البيانات" python3 -c "import sqlite3,sys
print(sqlite3.connect('$TMP/py.db').execute('PRAGMA journal_mode').fetchone()[0])" | grep -qi wal
    t "لا تسريب لـ stack trace"     bash -c "! curl -sS -m 5 '$U2/nope' | grep -q Traceback"
    t "اختبارات unittest للقالب"     bash -c "cd '$ROOT/templates/python-api' && python3 -m unittest discover -s tests -q >/dev/null 2>&1"
  else
    skip "لم يبدأ python-api خلال 20 ثانية — py.log:"
    tail -15 "$TMP/py.log" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
fi

# ================================================================ 6
if [ "$HAVE_PY" = "1" ] && [ "$HAVE_CURL" = "1" ]; then
  section "6) serve.sh — حجب الملفات الحساسة"
  mkdir -p "$TMP/webroot/.git"
  cp "$ROOT/templates/web-static/index.html" "$TMP/webroot/" 2>/dev/null
  printf 'SECRET_TOKEN=leak-me\n' > "$TMP/webroot/.env"
  printf 'pk-leak\n' > "$TMP/webroot/id_rsa"
  printf 'ref: refs/heads/main\n' > "$TMP/webroot/.git/HEAD"
  P3="$(free_port)"; track_port "$P3"
  ( bash "$ROOT/scripts/serve.sh" "$TMP/webroot" --port "$P3" >"$TMP/serve.log" 2>&1 ) &
  SPID=$!; PIDS="$PIDS $SPID"
  U3="http://127.0.0.1:$P3"
  if wait_port 127.0.0.1 "$P3"; then
    t "index.html → 200"        bash -c "[ \"$(code "$U3/index.html")\" = 200 ]"
    t ".env محجوب (403)"         bash -c "[ \"$(code "$U3/.env")\" = 403 ]"
    t "id_rsa محجوب (403)"       bash -c "[ \"$(code "$U3/id_rsa")\" = 403 ]"
    t ".git/HEAD محجوب (403)"    bash -c "[ \"$(code "$U3/.git/HEAD")\" = 403 ]"
    t "قيمة السر لم تتسرب"      bash -c "! curl -sS -m 5 '$U3/.env' | grep -q leak-me"
    t "منفذ مشغول → فشل واضح"   bash -c "! bash '$ROOT/scripts/serve.sh' '$TMP/webroot' --port '$P3' >/dev/null 2>&1"
    t "--status يكشف المشغول"   bash -c "bash '$ROOT/scripts/serve.sh' --status --port '$P3' | grep -q 'مشغول'"
    t "--stop يوقف السيرفر"       bash -c "bash '$ROOT/scripts/serve.sh' --stop --port '$P3' >/dev/null 2>&1; sleep 1; ! curl -sS -m 2 -o /dev/null 'http://127.0.0.1:$P3/index.html'"
    t "المنفذ أصبح حرًا بعد الإيقاف" bash -c "bash '$ROOT/scripts/serve.sh' --status --port '$P3' | grep -q 'حر'"
    t "إعادة التشغيل بعد --stop تنجح" bash -c "( bash '$ROOT/scripts/serve.sh' '$TMP/webroot' --port '$P3' >/dev/null 2>&1 & ) ; for i in \$(seq 1 40); do curl -sS -m 1 -o /dev/null 'http://127.0.0.1:$P3/index.html' && exit 0; sleep 0.25; done; exit 1"
    t "بورت حر: --stop يفشل برسالة"  bash -c "! bash '$ROOT/scripts/serve.sh' --stop --port '$(free_port)' >/dev/null 2>&1"
    t "منفذ خارج المدى → رفض"    bash -c "! bash '$ROOT/scripts/serve.sh' '$TMP/webroot' --port 99999 >/dev/null 2>&1"
    t "مجلد غير موجود → رفض"     bash -c "! bash '$ROOT/scripts/serve.sh' '$TMP/does-not-exist' >/dev/null 2>&1"
    t "serve.sh --help"          bash "$ROOT/scripts/serve.sh" --help
  else
    skip "لم يبدأ serve.sh — serve.log:"
    tail -15 "$TMP/serve.log" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
fi

# ================================================================ 7
section "7) setup.sh / doctor.sh / backup.sh في HOME وهمي"
FAKE="$TMP/fakehome"; mkdir -p "$FAKE"
cat > "$FAKE/.gitconfig" <<CFG
[user]
	name = ci-test
	email = ci@test.local
[init]
	defaultBranch = main
CFG
FH() { env HOME="$FAKE" NO_COLOR=1 bash "$@"; }
t "setup.sh يعمل خارج Termux (dry-run)" FH "$ROOT/scripts/setup.sh" -y
t "أنشأ ~/projects"                        test -d "$FAKE/projects"
t "أنشأ ~/backups"                         test -d "$FAKE/backups"
t "أنشأ ~/.npm-global"                     test -d "$FAKE/.npm-global"
t "كتب بلوك في .bashrc"                    bash -c "grep -q 'termux-dev >>>' '$FAKE/.bashrc'"
t "أنشأ termux.properties"                  test -f "$FAKE/.termux/termux.properties"
t "سطر extra-keys مضبوط"                    bash -c "grep -q '^extra-keys' '$FAKE/.termux/termux.properties'"
printf 'export ORIGINAL=1\n' >> "$FAKE/.bashrc"
t "التشغيل الثاني لا يكرر البلوك"          bash -c "env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/setup.sh' -y >/dev/null 2>&1; [ \$(grep -c 'termux-dev >>>' '$FAKE/.bashrc') = 1 ]"
t "يحافظ على محتوى .bashrc القديم"         bash -c "grep -q 'export ORIGINAL=1' '$FAKE/.bashrc'"
t "doctor.sh يعمل ويعيد 0 أو 1"            bash -c "out=\$(env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/doctor.sh'); rc=\$?; [ \$rc -le 1 ] && printf '%s' \"\$out\" | grep -q 'النتيجة'"
t "doctor.sh --json مصفوفة صالحة"          bash -c "env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/doctor.sh' --json 2>/dev/null | tail -1 | python3 -m json.tool >/dev/null"
t "tunnel.sh يرفض منفذاً غير رقمي"         bash -c "! bash '$ROOT/scripts/tunnel.sh' notaport >/dev/null 2>&1"
t "backup.sh --help"                        bash "$ROOT/scripts/backup.sh" --help

# ================================================================ 8
section "8) backup.sh على مشروع مولّد"
if [ "$HAVE_GIT" = "1" ] && [ -d "$TMP/demo-node/.git" ]; then
  t "commit عند وجود تغيير"  bash -c "echo '# change' >> '$TMP/demo-node/README.md'; env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/backup.sh' '$TMP/demo-node' >/dev/null 2>&1; git -C '$TMP/demo-node' log --oneline | head -1 | grep -q 'backup\|scaffold'"
  t "أنشأ أرشيف tar.gz"       bash -c "ls $FAKE/backups/*.tar.gz >/dev/null 2>&1"
  t "الأرشيف بلا node_modules" bash -c "f=\$(ls $FAKE/backups/*.tar.gz | head -1); ! tar tzf \"\$f\" | grep -q node_modules"
  t "الأرشيف قابل للاستعادة"   bash -c "f=\$(ls $FAKE/backups/*.tar.gz | head -1); mkdir -p '$TMP/restored'; tar -xzf \"\$f\" -C '$TMP/restored'; test -f '$TMP/restored/server.js'"
  t "push بلا remote يفشل"     bash -c "! env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/backup.sh' '$TMP/demo-node' --push >/dev/null 2>&1"
  t "pull بلا remote يفشل بأدب" bash -c "! env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/backup.sh' '$TMP/demo-node' --pull >/dev/null 2>&1"
else
  skip "لا يوجد مشروع مولّد — تخطي backup.sh"
fi

# ================================================================ 9
section "9) التوثيق والنظافة"
t "README.md موجود" test -f "$ROOT/README.md"
for d in INSTALL TROUBLESHOOTING CHEATSHEET DEPLOY; do t "docs/$d.md موجود" test -f "$ROOT/docs/$d.md"; done
t "كل سكربت يبدأ بـ shebang" bash -c '
  for f in "$1"/scripts/*.sh "$1"/tests/run.sh; do
    head -1 "$f" | grep -q "^#!" || { echo "      بدون shebang: $f"; exit 1; }
  done' _ "$ROOT"
t "لا اعتماديات غير معلنة في docs" bash -c "! grep -rn 'pip install' '$ROOT/README.md' '$ROOT/docs' | grep -v 'اختياري\|--user\|fastapi\|locust' >/dev/null"
t "روابط docs الداخلية سليمة" bash -c '
  cd "$1"; miss=0
  for f in README.md docs/*.md; do
    while IFS= read -r link; do
      tgt="${link%%#*}"
      case "$tgt" in ""|http*|mailto:*|./*) ;; esac
      [ -z "$tgt" ] && continue
      case "$tgt" in http*|mailto:*) continue;; esac
      if [ ! -e "$(dirname "$f")/$tgt" ]; then echo "      مفقود: $f → $link"; miss=1; fi
    done < <(grep -oE "\]\([^)]+\)" "$f" | sed "s/^](//; s/)$//")
  done
  exit $miss' _ "$ROOT"
t "لا مفاتيح خاصة/توكنات في المستودع" bash -c "! grep -rIlE '(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' '$ROOT' --exclude-dir=.git >/dev/null 2>&1"
t "لا إشارات لأدوات غش/احتيال" bash -c "! grep -rniE 'botnet|sybil|sms.?bypass|otp.?bypass|cookie.?steal|brute.?force' '$ROOT/README.md' '$ROOT/docs' '$ROOT/scripts' >/dev/null 2>&1"
t "لا بقايا tmp في الريبو" bash -c "! find '$ROOT' -name '*.tmp' -o -name '.td_blocklist.py' | grep -q ."
t "docs/INSTALL.md يحذر من نسخة Play Store" bash -c "grep -qi 'Google Play' '$ROOT/docs/INSTALL.md'"

section "10) التنظيف: لا شاردة ولا منافذ معلّقة"
# نُغلق كل منفذ استخدمناه ثم نتحقق أنه تحرّر — نفس المنطق الذي يستخدمه cleanup()
for pp in $PORTS_USED; do
  bash "$ROOT/scripts/serve.sh" --stop --port "$pp" >/dev/null 2>&1 </dev/null
done
for i in $(seq 1 20); do
  remaining=0
  for pp in $PORTS_USED; do
    bash -c "curl -sS -m 1 -o /dev/null 'http://127.0.0.1:$pp/'" 2>/dev/null && remaining=$((remaining + 1))
  done
  [ "$remaining" = 0 ] && break
  sleep 0.25
done
for pp in $PORTS_USED; do
  t "المنفذ $pp تحرّر" bash -c "! curl -sS -m 1 -o /dev/null 'http://127.0.0.1:$pp/'"
done
t "لا سيرفرات شاردة من القوالب" no_stray_servers

# ================================================================ 11
section "11) disk.sh — قياسات المساحة وملفات التثبيت"
# مساعدات في نطاق الأب: بلا استبدال متأخر داخل bash -c (مصدر أخطاء صامتة)
disk_out() { bash "$ROOT/scripts/disk.sh" "$@" 2>&1 </dev/null; }
disk_has() { # <نص متوقع> [وسيط]
  local needle="$1" arg="${2:-}" out
  out="$(disk_out $arg)"
  printf '%s' "$out" | grep -qF -- "$needle" || { printf '      ناقص: %s\n' "$needle"; return 1; }
}
plan_has() { # <profile>
  local out; out="$(disk_out --plan)"
  printf '%s' "$out" | grep -qE "(^|[[:space:]])$1([[:space:]]|$)"
}

for key in 'المستودع نفسه' 'مساحة كل ملف' 'القرص الآن' 'الكاشات' 'بعد التوليد'; do
  t "تقرير: يحتوي «$key»" disk_has "$key"
done
for pr in full minimal python tools; do
  t "--plan يعرض profile «$pr»" plan_has "$pr"
done
t "disk.sh --project على الريبو"    disk_has "مساحة المشروع" "--project $ROOT"
t "disk.sh --project لمسار وهمي يفشل" bash -c "! bash '$ROOT/scripts/disk.sh' --project /nonexistent-xyz >/dev/null 2>&1"
t "disk.sh --json صالح"             json_shape_ok
t "disk.sh --help"                  bash "$ROOT/scripts/disk.sh" --help
t "disk.sh --clean لا ينكسر"        bash -c "env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/disk.sh' --clean >/dev/null 2>&1; [ \$? -le 1 ]"

# محوّل التقدير: apt وهمي بمخرج Termux القياسي
mkdir -p "$TMP/fakeapt"
emit "$TMP/fakeapt/apt-sim.txt" 644 \
  "Reading package lists..." \
  "Building dependency tree..." \
  "The following NEW packages will be installed:" \
  "  curl fd git jq nano nodejs-lts openssh python python-pip ripgrep tmux tree unzip wget zip" \
  "Need to get 62.4 MB of archives." \
  "After this operation, 318 MB of additional disk space will be used." \
  "0 upgraded, 18 newly installed, 0 to remove and 0 not upgraded."
# البيئة الوهمية لـ apt: أمر apt-get بديل يطبع نص محاكاة جاهزًا
allowed_root_dirs=" ci docs scripts templates tests .github "
root_dirs_ok() {
  local d name bad=""
  for d in "$ROOT"/*/ "$ROOT"/.*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    case "$name" in .git|.gitignore|.tmp-*|.nox|node_modules|.venv|__pycache__) continue;; esac
    case " $allowed_root_dirs " in *" $name "*) continue;; esac
    bad="$bad $name/"
  done
  [ -z "$bad" ] || { printf '      مجلد غير متوقع في الجذر:%s\n' "$bad"; return 1; }
  return 0
}

apt_env() {
  PATH="$TMP/fakeapt:$PATH"
  TD_APT_SIM="$TMP/fakeapt/apt-sim.txt"
  HOME="$FAKE"
  NO_COLOR=1
  export TD_APT_SIM HOME NO_COLOR
}
apt_parser_ok() {
  local out
  out="$( ( apt_env; bash -c '. "$1/scripts/lib/common.sh"; apt_projection full' _ "$ROOT" ) 2>&1 </dev/null )"
  [ "$out" = "18|62.4 MB|318 MB" ] || { printf '      وصل: [%s]\n' "$out"; return 1; }
}
plan_uses_sim() {
  local out
  out="$( ( apt_env; bash "$ROOT/scripts/disk.sh" --plan ) 2>&1 </dev/null )"
  printf '%s' "$out" | grep -q "318 MB" || { printf '%s\n' "$out" | tail -6 | sed 's/^/      /'; return 1; }
}
profile_sizes_stair() {
  local a b c
  a="$(. "$ROOT/scripts/lib/common.sh"; td_profile_packages tools | wc -l)"
  b="$(. "$ROOT/scripts/lib/common.sh"; td_profile_packages minimal | wc -l)"
  c="$(. "$ROOT/scripts/lib/common.sh"; td_profile_packages full | wc -l)"
  [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] || { printf '      tools=%s minimal=%s full=%s\n' "$a" "$b" "$c"; return 1; }
}
setup_prints_projection() {
  local out
  out="$( ( apt_env; bash "$ROOT/scripts/setup.sh" -y ) 2>&1 </dev/null )"
  printf '%s' "$out" | grep -q "التقدير من apt" || { printf '%s\n' "$out" | tail -6 | sed 's/^/      /'; return 1; }
}

emit "$TMP/fakeapt/apt-get" 755 \
  '#!/usr/bin/env bash' \
  'exec cat "$TD_APT_SIM"'

t "apt_projection يحلّل مخرج apt" apt_parser_ok
t "--plan يستعمل نتيجة المحاكاة"  plan_uses_sim

# ملفات التثبيت في setup.sh
t "setup.sh --minimal يمرّ"        env HOME="$FAKE" NO_COLOR=1 bash "$ROOT/scripts/setup.sh" -y --minimal
t "setup.sh --tools-only يمرّ"     env HOME="$FAKE" NO_COLOR=1 bash "$ROOT/scripts/setup.sh" -y --tools-only
t "setup.sh --python-only يمرّ"    env HOME="$FAKE" NO_COLOR=1 bash "$ROOT/scripts/setup.sh" -y --python-only
t "setup.sh --profile=bogus يرفض"  bash -c "! env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/scripts/setup.sh' -y --profile=bogus >/dev/null 2>&1"
t "setup.sh يعرض التقدير عند توفر apt" setup_prints_projection
t "حزم الملفات تتدرّج (tools < minimal < full)" profile_sizes_stair
t "profile أصغر لا يثبّت Node/Python" bash -c "
  . '$ROOT/scripts/lib/common.sh'
  ! td_profile_packages tools | grep -Eq 'nodejs|^python\$'"

# ------------------------- 12) نقطة الدخول install.sh + سلامة الجذر -------------------------
t "جذر المستودع فيه المجلدات المتوقعة فقط" root_dirs_ok
t "install.sh موجود ويعمل --help" bash -c "test -f '$ROOT/install.sh' && bash '$ROOT/install.sh' --help | grep -q 'check-only'"
t "install.sh --check-only يمرّ" bash -c "env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/install.sh' --check-only >/dev/null 2>&1"
t "install.sh يرفض خيارًا مجهولًا" bash -c "! env HOME='$FAKE' NO_COLOR=1 bash '$ROOT/install.sh' --nope >/dev/null 2>&1"

PDP="$(free_port)"; track_port "$PDP"
demo_health_ok() {
  local i
  for i in $(seq 1 160); do   # حتى 40 ثانية: install.sh يشغّل setup + doctor قبل أن يفتح الخادم
    if curl -sS -m 2 "http://127.0.0.1:$PDP/api/health" 2>/dev/null | grep -qF '"status":"ok"'; then
      return 0
    fi
    sleep 0.25
  done
  printf '      لم يستجب الخادم — آخر السجل:\n'
  tail -6 "$TMP/demo.log" 2>/dev/null | sed 's/^/        /'
  return 1
}
demo_stopped() {
  kill "$DPID" 2>/dev/null
  sleep 0.5
  ! curl -sS -m 2 -o /dev/null "http://127.0.0.1:$PDP/api/health" 2>/dev/null
}
( env HOME="$FAKE" NO_COLOR=1 PORT="$PDP" bash "$ROOT/install.sh" --demo --tools-only >"$TMP/demo.log" 2>&1 ) &
DPID=$!; PIDS="$PIDS $DPID"
t "install.sh --demo يولّد مشروعًا ويشغّله" demo_health_ok
t "install.sh أنشأ المشروع في HOME الهدف" test -f "$FAKE/projects/termux-dev-demo/server.js"
t "إيقاف خادم الـdemo" demo_stopped
PIDS="${PIDS/ $DPID/}"

printf '\n%sالنتيجة%s\n  %sPASS: %s%s   %sFAIL: %s%s\n' "$B" "$N" "$G" "$PASS" "$N" "$R" "$FAIL" "$N"
if [ "$FAIL" -gt 0 ]; then
  printf '  %sبعض الاختبارات فشلت — راجع السطور أعلاه.%s\n' "$R" "$N"
  exit 1
fi
printf '  %sكل الاختبارات نجحت ✅%s\n' "$G" "$N"
