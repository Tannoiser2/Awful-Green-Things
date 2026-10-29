#!/usr/bin/env python3
"""Finto Firebase (Realtime Database REST + accesso anonimo) per provare il gioco online in locale.
Uso: python3 tests/firebase_mock.py 8765
Poi: AGT_DB_URL=http://127.0.0.1:8765/db AGT_AUTH_URL=http://127.0.0.1:8765/signup
     AGT_REFRESH_URL=http://127.0.0.1:8765/refresh godot ...
"""
import json, sys, time, threading, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

DB = {}
LOCK = threading.Lock()


def resolve_sv(v):
    if isinstance(v, dict):
        if v.get(".sv") == "timestamp":
            return int(time.time() * 1000)
        return {k: resolve_sv(x) for k, x in v.items()}
    return v


def path_parts(p):
    return [x for x in p.split("/") if x]


def get(parts):
    cur = DB
    for k in parts:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur


def put(parts, val):
    if not parts:
        return
    cur = DB
    for k in parts[:-1]:
        if k not in cur or not isinstance(cur[k], dict):
            cur[k] = {}
        cur = cur[k]
    if val is None:
        cur.pop(parts[-1], None)
    else:
        cur[parts[-1]] = val


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n).decode() if n else ""

    def _db(self, method):
        u = urlparse(self.path)
        p = u.path
        if not p.startswith("/db/") or not p.endswith(".json"):
            return self._send(404, {"error": "?"})
        parts = path_parts(p[4:-5])
        with LOCK:
            if method == "GET":
                return self._send(200, get(parts))
            body = self._body()
            val = resolve_sv(json.loads(body)) if body else None
            if method == "PUT":
                put(parts, val)
                return self._send(200, val)
            if method == "PATCH":
                for k, v in (val or {}).items():
                    put(parts + path_parts(k), v)
                return self._send(200, val)
            if method == "DELETE":
                put(parts, None)
                return self._send(200, None)

    def do_GET(self):
        self._db("GET")

    def do_PUT(self):
        self._db("PUT")

    def do_PATCH(self):
        self._db("PATCH")

    def do_DELETE(self):
        self._db("DELETE")

    def do_POST(self):
        self._body()
        if self.path.startswith("/signup"):
            uid = uuid.uuid4().hex[:12]
            return self._send(200, {"idToken": "t" + uid, "refreshToken": "r" + uid, "localId": uid})
        if self.path.startswith("/refresh"):
            return self._send(200, {"id_token": "t", "refresh_token": "r", "user_id": "u"})
        self._send(404, {})


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8765), H).serve_forever()
