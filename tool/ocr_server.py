"""Serves a folder of photos to integration_test/ocr_dump_test.dart and saves
the OCR results it posts back.

Usage: python tool/ocr_server.py PHOTO_DIR OUT_JSON [PORT]

HTTP/1.1 on purpose: Python's default HTTP/1.0 handler cuts big files short
over the emulator's 10.0.2.2 bridge.
"""
import json
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PHOTOS = Path(sys.argv[1])
OUT = Path(sys.argv[2])
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8765
NAMES = sorted(str(p.relative_to(PHOTOS)).replace("\\", "/") for p in PHOTOS.rglob("*")
               if p.suffix.lower() in {".jpg", ".jpeg", ".png"})


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body, kind="application/octet-stream"):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/index.json":
            return self._send(200, json.dumps(NAMES).encode(), "application/json")
        if self.path.startswith("/img/"):
            name = urllib.parse.unquote(self.path[5:])
            if name in NAMES:
                return self._send(200, (PHOTOS / name).read_bytes(), "image/jpeg")
        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        OUT.write_bytes(body)
        print(f"saved {len(body)} bytes to {OUT}", flush=True)
        self._send(200, b"ok", "text/plain")


print(f"serving {len(NAMES)} photos on :{PORT}", flush=True)
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
