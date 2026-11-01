#!/usr/bin/env python3
"""Minimal fake of the Kasm public API, only for the kasm_session Molecule tests.

It implements the six endpoints the role calls and mimics the details the role
depends on:

* get_users returns UUIDs WITH dashes; get_images and get_kasms return them
  WITHOUT dashes (the role normalises both).
* request_kasm / get_kasm_status / destroy_kasm only accept the canonical
  dashed UUID form (HTTP 400 otherwise).
* every call needs the right api_key / api_key_secret (HTTP 401 otherwise).

Test-only control endpoints (not part of Kasm):
  GET  /_state   -> counters per endpoint and the current sessions
  POST /_reset   -> forget all sessions and counters; optional JSON body:
                    {"starting_polls": N,      # get_kasm_status answers
                                               # "starting" N times before "running"
                     "limit_reached": true}    # request_kasm returns no kasm_id

It only listens on 127.0.0.1 and holds all state in memory. This tests the
role's logic against the API as the role understands it; the real API is
exercised in the end-to-end run against a real Kasm server.
"""
import argparse
import json
import re
import sys
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

API_KEY = "molecule-key"
API_KEY_SECRET = "molecule-secret"
DASHED = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

USERS = [
    {"username": "admin@kasm.local", "user_id": "11111111-1111-4111-8111-111111111111"},
    {"username": "user@kasm.local", "user_id": "22222222-2222-4222-8222-222222222222"},
]
IMAGES = [
    {"name": "pepesan/core-ubuntu-resolute:1.20", "friendly_name": "Core Ubuntu Resolute",
     "image_id": "aaaaaaaaaaaa4aaa8aaaaaaaaaaaaaaa"},
    {"name": "user/other:1.0", "friendly_name": "Other Desktop",
     "image_id": "bbbbbbbbbbbb4bbb8bbbbbbbbbbbbbbb"},
    # Two different workspaces with the same friendly name: an ambiguous match.
    {"name": "user/dup-a:1.0", "friendly_name": "Duplicated",
     "image_id": "cccccccccccc4ccc8ccccccccccccccc"},
    {"name": "user/dup-b:1.0", "friendly_name": "Duplicated",
     "image_id": "dddddddddddd4ddd8ddddddddddddddd"},
]


class State:
    def __init__(self):
        self.reset({})

    def reset(self, options):
        self.kasms = {}
        self.counts = {}
        self.polls = {}
        self.starting_polls = int(options.get("starting_polls", 0))
        self.limit_reached = bool(options.get("limit_reached", False))


STATE = State()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep the Molecule output quiet
        pass

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            return json.loads(raw or b"{}")
        except ValueError:
            return None

    def do_GET(self):
        if self.path == "/_state":
            self._send(200, {"counts": STATE.counts, "kasms": list(STATE.kasms.values())})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        body = self._body()
        if body is None:
            return self._send(400, {"error": "invalid json"})
        if self.path == "/_reset":
            STATE.reset(body)
            return self._send(200, {"ok": True})

        match = re.fullmatch(r"/api/public/([a-z_]+)", self.path)
        if not match:
            return self._send(404, {"error": "not found"})
        endpoint = match.group(1)
        STATE.counts[endpoint] = STATE.counts.get(endpoint, 0) + 1

        if body.get("api_key") != API_KEY or body.get("api_key_secret") != API_KEY_SECRET:
            return self._send(401, {"error": "invalid api key"})

        handler = getattr(self, "api_" + endpoint, None)
        if handler is None:
            return self._send(404, {"error": "unknown endpoint"})
        return handler(body)

    # --- Kasm public API -------------------------------------------------
    def api_get_users(self, body):
        self._send(200, {"users": USERS})

    def api_get_images(self, body):
        self._send(200, {"images": IMAGES})

    def api_get_kasms(self, body):
        self._send(200, {"kasms": [
            {"kasm_id": k["kasm_id"], "user_id": k["user_id"].replace("-", ""),
             "image_id": k["image_id"].replace("-", "")}
            for k in STATE.kasms.values()]})

    def api_request_kasm(self, body):
        user_id, image_id = body.get("user_id", ""), body.get("image_id", "")
        if not DASHED.match(user_id) or not DASHED.match(image_id):
            return self._send(400, {"error": "ids must be dashed UUIDs",
                                    "user_id": user_id, "image_id": image_id})
        if STATE.limit_reached:
            return self._send(200, {"error_message": "session limit reached"})
        kasm_id = str(uuid.uuid4())
        STATE.kasms[kasm_id] = {"kasm_id": kasm_id, "user_id": user_id, "image_id": image_id}
        STATE.polls[kasm_id] = 0
        self._send(200, {"kasm_id": kasm_id, "session_token": "never-log-this"})

    def api_get_kasm_status(self, body):
        kasm_id = body.get("kasm_id", "")
        if not DASHED.match(body.get("user_id", "")) or kasm_id not in STATE.kasms:
            return self._send(400, {"error": "unknown session or bad user_id"})
        STATE.polls[kasm_id] += 1
        status = "running" if STATE.polls[kasm_id] > STATE.starting_polls else "starting"
        self._send(200, {"kasm": {"operational_status": status,
                                  "container_id": "container-" + kasm_id[:8]}})

    def api_destroy_kasm(self, body):
        kasm_id = body.get("kasm_id", "")
        if not DASHED.match(body.get("user_id", "")) or kasm_id not in STATE.kasms:
            return self._send(400, {"error": "unknown session or bad user_id"})
        del STATE.kasms[kasm_id]
        self._send(200, {})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()
    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"mock kasm api on 127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
