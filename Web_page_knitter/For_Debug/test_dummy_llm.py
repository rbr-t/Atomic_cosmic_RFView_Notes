from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class DummyHandler(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        try:
            data = json.loads(body) if body else {}
        except Exception:
            data = {}
        # respond with both common shapes so client parsing logic can pick one
        resp = {
            "message": {"content": "Dummy reply: received your prompt."},
            "choices": [{"message": {"content": "Dummy choice reply."}}],
            "output": {"text": "Dummy output text."}
        }
        self._set_headers()
        self.wfile.write(json.dumps(resp).encode('utf-8'))

    def log_message(self, format, *args):
        # silence default logging
        return

if __name__ == '__main__':
    server_address = ('127.0.0.1', 8001)
    httpd = HTTPServer(server_address, DummyHandler)
    print('Dummy LLM server running on http://127.0.0.1:8001')
    httpd.serve_forever()
