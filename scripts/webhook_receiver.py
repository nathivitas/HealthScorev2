from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from datetime import datetime
from pathlib import Path

OUTPUT_DIR = Path("./webhook_output")
OUTPUT_DIR.mkdir(exist_ok=True)

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_length)

        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        output_file = OUTPUT_DIR / f"webhook_{timestamp}.json"

        try:
            payload = json.loads(raw_body)
            print("\nReceived JSON:")
            print(json.dumps(payload, indent=2))

            with open(output_file, "w") as f:
                json.dump(payload, f, indent=2)

        except json.JSONDecodeError:
            print("\nReceived non-JSON payload:")
            print(raw_body.decode("utf-8", errors="replace"))

            with open(output_file, "wb") as f:
                f.write(raw_body)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"received"}')

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), WebhookHandler)
    print("Webhook receiver running on http://localhost:8080")
    server.serve_forever()