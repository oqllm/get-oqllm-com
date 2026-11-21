"""Loopback SubLLM server for the installed Bielik model."""
import json
import http.client
from http.server import ThreadingHTTPServer

from subllm.proxy import SubLLMProxyHandler

OLLAMA_PORT = 11439
MODEL = "bielik"


class JetsonHandler(SubLLMProxyHandler):
    ollama_upstream = f"http://127.0.0.1:{OLLAMA_PORT}"

    def do_GET(self):
        if not self._local_host():
            return self.send_error(421)
        if self.path == "/v1/models":
            return self._json(200, {"object": "list", "data": [
                {"id": MODEL, "object": "model", "owned_by": "local"}
            ]})
        if self.path == "/health":
            conn = http.client.HTTPConnection("127.0.0.1", OLLAMA_PORT, timeout=5)
            try:
                conn.request("GET", "/api/tags")
                response = conn.getresponse()
                models = json.loads(response.read())["models"] if response.status == 200 else []
                ready = any(x.get("name") in (MODEL, MODEL + ":latest") for x in models)
            except (OSError, ValueError, KeyError, http.client.HTTPException):
                ready = False
            finally:
                conn.close()
            return self._json(200 if ready else 503, {"ready": ready, "model": MODEL, "gateway": "subllm"})
        self.send_error(404)

    def do_POST(self):
        if not self._local_host():
            return self.send_error(421)
        if self.path not in ("/v1/chat/completions", "/api/chat", "/api/generate"):
            return self.send_error(404)
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 1048576:
                return self.send_error(413)
            payload = json.loads(self.rfile.read(size))
            if not isinstance(payload, dict) or payload.get("model") not in (MODEL, MODEL + ":latest"):
                return self._json(400, {"error": "Use the local model bielik"})
        except (ValueError, UnicodeError):
            return self.send_error(400)
        if not payload.get("stream", self.path.startswith("/api/")):
            return self._forward_upstream("POST", self.path, payload)

        conn = http.client.HTTPConnection("127.0.0.1", OLLAMA_PORT, timeout=180)
        headers_sent = False
        try:
            conn.request("POST", self.path, json.dumps(payload).encode(), {"Content-Type": "application/json"})
            response = conn.getresponse()
            self.send_response(response.status)
            self.send_header("Content-Type", response.getheader("Content-Type", "application/octet-stream"))
            self.send_header("Connection", "close")
            self.end_headers()
            headers_sent = True
            self.close_connection = True
            while chunk := response.read1(16384):
                self.wfile.write(chunk)
                self.wfile.flush()
        except (OSError, http.client.HTTPException):
            if not headers_sent:
                self.send_error(502)
        finally:
            conn.close()


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 11437), JetsonHandler) as server:
        server.serve_forever()
