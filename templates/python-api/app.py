#!/usr/bin/env python3
"""
__PROJECT_NAME__ — REST API صغير بمكتبات بايثون القياسية فقط (لا يحتاج pip install).

لماذا stdlib؟ لأن تثبيت الحزم على Termux أحياناً يحتاج compiles طويلة؛ ابدأ بدون اعتماديات،
وانتقل إلى FastAPI/Flask عندما تحتاج Swagger أو WebSockets أو ORM.

التشغيل:
    python3 app.py
    PORT=3000 python3 app.py
    python3 -m pytest -q            # (اختياري: pip install pytest)
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))
DB_PATH = os.environ.get("DB_PATH", os.path.join(os.path.dirname(__file__), "data", "app.db"))
MAX_BODY = 64 * 1024
RATE_LIMIT_PER_MIN = int(os.environ.get("RATE_LIMIT_PER_MIN", "120"))

# ---------------------------------------------------------------- طبقة البيانات
_db_lock = threading.Lock()


def db() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, check_same_thread=False, timeout=10)
    conn.row_factory = sqlite3.Row
    # WAL يمنع خطأ "database is locked" تحت الضغط من خيوط متعددة
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


CONN = db()


def migrate() -> None:
    with _db_lock:
        CONN.executescript(
            """
            CREATE TABLE IF NOT EXISTS items (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                title      TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
                done       INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
            """
        )
        CONN.commit()


def list_items(limit: int, offset: int) -> dict:
    with _db_lock:
        rows = CONN.execute(
            "SELECT id, title, done, created_at FROM items ORDER BY id DESC LIMIT ? OFFSET ?",
            (limit, offset),
        ).fetchall()
        total = CONN.execute("SELECT COUNT(*) c FROM items").fetchone()["c"]
    return {"items": [dict(r) for r in rows], "total": total, "limit": limit, "offset": offset}


def add_item(title: str) -> dict:
    with _db_lock:
        cur = CONN.execute("INSERT INTO items(title) VALUES (?)", (title,))
        CONN.commit()
        row = CONN.execute(
            "SELECT id, title, done, created_at FROM items WHERE id=?", (cur.lastrowid,)
        ).fetchone()
    return dict(row)


def get_item(item_id: int) -> dict | None:
    with _db_lock:
        row = CONN.execute(
            "SELECT id, title, done, created_at FROM items WHERE id=?", (item_id,)
        ).fetchone()
    return dict(row) if row else None


def toggle_item(item_id: int) -> dict | None:
    with _db_lock:
        cur = CONN.execute("UPDATE items SET done = 1 - done WHERE id = ?", (item_id,))
        CONN.commit()
        if cur.rowcount == 0:
            return None
        row = CONN.execute("SELECT id, title, done, created_at FROM items WHERE id=?", (item_id,)).fetchone()
    return dict(row)


def delete_item(item_id: int) -> bool:
    with _db_lock:
        cur = CONN.execute("DELETE FROM items WHERE id = ?", (item_id,))
        CONN.commit()
    return cur.rowcount > 0


# ------------------------------------------------------------- Rate limiting
_buckets: dict[str, list[float]] = {}
_bucket_lock = threading.Lock()


def allowed(ip: str) -> tuple[bool, int]:
    """نافذة منزلقة بسيطة لكل IP. يعيد (مسموح?, ثوانٍ للانتظار)."""
    now = time.time()
    with _bucket_lock:
        arr = [t for t in _buckets.get(ip, []) if now - t < 60]
        if len(arr) >= RATE_LIMIT_PER_MIN:
            _buckets[ip] = arr
            return False, max(1, int(60 - (now - arr[0])))
        arr.append(now)
        _buckets[ip] = arr
        return True, 0


# ------------------------------------------------------------------- الخادم
ID_ROUTE = re.compile(r"^/api/items/(?P<id>\d+)$")


class Handler(BaseHTTPRequestHandler):
    server_version = "termux-dev/1.0"

    def log_message(self, fmt: str, *args) -> None:  # سجل أقصر وأنظف
        print(f"{time.strftime('%H:%M:%S')} {self.address_string()} {fmt % args}", flush=True)

    # ---- أدوات
    def _json(self, status: int, payload=None, headers: dict | None = None) -> None:
        body = b"" if payload is None else json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        if length > MAX_BODY:
            raise HttpError(413, "payload_too_large")
        try:
            return json.loads(self.rfile.read(length).decode())
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise HttpError(400, "invalid_json")

    def _ip(self) -> str:
        fwd = self.headers.get("X-Forwarded-For", "")
        return fwd.split(",")[0].strip() or self.client_address[0]

    # ---- المعالجة
    def do_GET(self) -> None:
        self._dispatch("GET")

    def do_POST(self) -> None:
        self._dispatch("POST")

    def do_PATCH(self) -> None:
        self._dispatch("PATCH")

    def do_DELETE(self) -> None:
        self._dispatch("DELETE")

    def do_HEAD(self) -> None:
        self._dispatch("GET")

    def do_PUT(self) -> None:
        # لا يوجد PUT في هذا الـ API — نعيد 405 صراحة بدل 501 الافتراضية
        self._dispatch("PUT")

    def do_OPTIONS(self) -> None:
        self._json(204, None, {"Allow": "GET, POST, PATCH, DELETE, OPTIONS"})

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        ok, retry = allowed(self._ip())
        if not ok:
            return self._json(429, {"error": "rate_limited"}, {"Retry-After": str(retry)})
        try:
            if path == "/api/health":
                return self._json(200, {"status": "ok", "db": DB_PATH, "rateLimit": RATE_LIMIT_PER_MIN})
            if path == "/api/items":
                if method == "POST":
                    body = self._body()
                    title = str(body.get("title") or "").strip()
                    if not title or len(title) > 200:
                        raise HttpError(422, "title_required (1..200)")
                    item = add_item(title)
                    return self._json(201, item, {"Location": f"/api/items/{item['id']}"})
                if method != "GET":
                    raise HttpError(405, "method_not_allowed")
                q = parse_qs(parsed.query)
                limit = min(int((q.get("limit") or ["50"])[0]), 200)
                offset = int((q.get("offset") or ["0"])[0])
                return self._json(200, list_items(limit, max(offset, 0)))
            m = ID_ROUTE.match(path)
            if m:
                item_id = int(m.group("id"))
                if method == "GET":
                    row = get_item(item_id)
                    return self._json(200, row) if row else self._json(404, {"error": "not_found"})
                if method == "DELETE":
                    return self._json(204) if delete_item(item_id) else self._json(404, {"error": "not_found"})
                if method == "PATCH":
                    row = toggle_item(item_id)
                    return self._json(200, row) if row else self._json(404, {"error": "not_found"})
            if path == "/" :
                return self._json(200, {"name": "__PROJECT_NAME__", "endpoints": ["/api/health", "/api/items"]})
            raise HttpError(404, "not_found")
        except HttpError as e:
            return self._json(e.status, {"error": e.message})
        except Exception as e:  # لا نسرّب stack trace للعميل
            print(f"  ! {type(e).__name__}: {e}", flush=True)
            return self._json(500, {"error": "internal_error"})


class HttpError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


def main() -> None:
    migrate()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"✅ __PROJECT_NAME__ على http://{HOST}:{PORT}  (Ctrl+C للإيقاف)", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nإيقاف…", flush=True)
        httpd.shutdown()
    finally:
        CONN.close()


if __name__ == "__main__":
    main()
