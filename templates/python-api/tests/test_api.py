"""
اختبار دخان بدون pytest — يعمل بمكتبات بايثون القياسية:
    python3 -m unittest -v
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ApiSmokeTest(unittest.TestCase):
    proc: subprocess.Popen | None = None
    base: str = ""

    @classmethod
    def setUpClass(cls) -> None:
        tmp = tempfile.mkdtemp(prefix="td-py-")
        port = free_port()
        cls.base = f"http://127.0.0.1:{port}"
        cls.proc = subprocess.Popen(
            [sys.executable, str(ROOT / "app.py")],
            cwd=str(ROOT),
            env={**os.environ, "PORT": str(port), "HOST": "127.0.0.1", "DB_PATH": f"{tmp}/t.db"},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
            # مجموعة عمليات مستقلة: نقتل الشجرة كلها ولا نترك يتيماً
            start_new_session=True,
        )
        for _ in range(80):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                    return
            except OSError:
                time.sleep(0.05)
        raise RuntimeError("الخادم لم يبدأ")

    @classmethod
    def tearDownClass(cls) -> None:
        if not cls.proc:
            return
        import signal

        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(os.getpgid(cls.proc.pid), sig)
            except (ProcessLookupError, PermissionError):
                break
            try:
                cls.proc.wait(timeout=3)
                return
            except subprocess.TimeoutExpired:
                continue

    def call(self, method: str, path: str, body: dict | None = None):
        import urllib.error
        import urllib.request

        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            self.base + path, data=data, method=method, headers={"Content-Type": "application/json"}
        )
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            return e.code, (json.loads(raw) if raw else None)

    def test_health(self):
        status, payload = self.call("GET", "/api/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "ok")

    def test_item_lifecycle(self):
        status, item = self.call("POST", "/api/items", {"title": "مهمة تجريبية"})
        self.assertEqual(status, 201, item)
        item_id = item["id"]

        status, listed = self.call("GET", "/api/items?limit=5")
        self.assertEqual(status, 200)
        self.assertGreaterEqual(listed["total"], 1)

        status, toggled = self.call("PATCH", f"/api/items/{item_id}")
        self.assertEqual(status, 200)
        self.assertEqual(toggled["done"], 1)

        status, _ = self.call("DELETE", f"/api/items/{item_id}")
        self.assertEqual(status, 204)

    def test_validation_rejects_empty_title(self):
        status, payload = self.call("POST", "/api/items", {"title": ""})
        self.assertEqual(status, 422, payload)

    def test_unknown_route_404(self):
        status, _ = self.call("GET", "/api/nope")
        self.assertEqual(status, 404)


if __name__ == "__main__":
    unittest.main()
