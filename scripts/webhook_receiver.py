from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from datetime import datetime
from pathlib import Path

OUTPUT_DIR = Path("./webhook_output")
OUTPUT_DIR.mkdir(exist_ok=True)

class WebhookHandler(BaseHTTPRequestHandler):

    def _send_json_response(self, status_code=200, payload=None):
        if payload is None:
            payload = {"status": "ok"}

        response = json.dumps(payload).encode("utf-8")

        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def do_GET(self):
        self._send_json_response(
            200,
            {
                "status": "healthy",
                "service": "webhook-receiver"
            }
        )

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_length)

        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")
        output_file = OUTPUT_DIR / f"webhook_{timestamp}.json"

        try:
            payload = json.loads(raw_body)

            print("\n=== WEBHOOK RECEIVED ===")
            print(json.dumps(payload, indent=2))

            with open(output_file, "w") as f:
                json.dump(payload, f, indent=2)

        except json.JSONDecodeError:
            print("\n=== NON-JSON PAYLOAD RECEIVED ===")
            print(raw_body.decode("utf-8", errors="replace"))

            with open(output_file, "wb") as f:
                f.write(raw_body)

        self._send_json_response(
            200,
            {
                "status": "received",
                "saved": str(output_file)
            }
        )

    def log_message(self, format, *args):
        print(
            f"{self.address_string()} - "
            f"[{self.log_date_time_string()}] "
            f"{format % args}"
        )

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), WebhookHandler)
    print("Webhook receiver running on http://0.0.0.0:8080")
    server.serve_forever()