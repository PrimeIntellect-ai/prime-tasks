#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/app.py
import os
import sys
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            with open("config.json", "r") as f:
                config = json.load(f)
        except Exception:
            config = {}

        if os.environ.get("DEPLOY_ENV") != "production":
            self.send_response(500)
            self.end_headers()
            self.wfile.write(b"Error: Not in production")
            return

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()

        response = {"status": "ok", "message": "Backend operational", "config_loaded": config.get("proxy_active", False)}
        self.wfile.write(json.dumps(response).encode())

if __name__ == "__main__":
    if os.environ.get("DEPLOY_ENV") != "production":
        print("Crash: DEPLOY_ENV not set to production")
        sys.exit(1)

    # Simulate crashing if not in the right working directory
    if os.path.basename(os.getcwd()) != "app":
        print("Crash: Wrong working directory")
        sys.exit(1)

    server = HTTPServer(("localhost", 8081), BackendHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/launch.sh
#!/bin/bash
# Incorrect script: wrong directory, missing env var
python3 /home/user/app/app.py &
EOF

    echo '{"original_key": "do_not_delete"}' > /home/user/app/config.json

    chmod +x /home/user/launch.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
