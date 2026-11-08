#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest supervisor

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/service_a.py
import http.server
import socketserver
import json

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        response = {"status": "ok", "payload": "pipeline_ready"}
        self.wfile.write(json.dumps(response).encode())

PORT = 8000
with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/src/service_b.py
import urllib.request
import json
import time
import os
import sys

# Misconfigured port
URL = "http://127.0.0.1:9090/"
TARGET_DIR = "/home/user/app/active_data"

while True:
    try:
        req = urllib.request.urlopen(URL)
        data = json.loads(req.read().decode())
        if data.get("status") == "ok":
            if os.path.exists(TARGET_DIR) and os.path.islink(TARGET_DIR):
                target_file = os.path.join(TARGET_DIR, "pipeline_success.json")
                with open(target_file, "w") as f:
                    json.dump({"result": "success", "source": data["payload"]}, f)
                print("Successfully processed data and wrote output.")
            else:
                print("Target directory/symlink does not exist.", file=sys.stderr)
    except Exception as e:
        print(f"Failed to fetch or process: {e}", file=sys.stderr)
    time.sleep(2)
EOF

    chmod +x /home/user/src/service_a.py /home/user/src/service_b.py
    chmod -R 777 /home/user
