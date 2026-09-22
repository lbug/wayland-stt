"""Minimal stand-in for OpenRouter's /audio/transcriptions used by tests/run.sh."""
import base64, json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = os.environ["MOCK_LOG"]

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        auth = self.headers.get("Authorization", "")
        req = json.loads(body)
        audio = base64.b64decode(req["input_audio"]["data"])
        with open(LOG, "a") as f:
            f.write(json.dumps({"auth": auth, "ctype": self.headers["Content-Type"],
                                "format": req["input_audio"]["format"],
                                "has_ogg": audio[:4] == b"OggS", "model": req["model"],
                                "language": req.get("language"),
                                "provider": req.get("provider")}) + "\n")
        mode = os.environ.get("MOCK_MODE", "ok")
        if auth != "Bearer test-key":
            code, resp = 401, {"error": {"message": "No auth credentials found"}}
        elif mode == "empty":
            code, resp = 200, {"text": "  "}
        else:
            code, resp = 200, {"text": "  Hallo Welt, äöü ß – Test.\n", "usage": {"seconds": 2}}
        out = json.dumps(resp).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
