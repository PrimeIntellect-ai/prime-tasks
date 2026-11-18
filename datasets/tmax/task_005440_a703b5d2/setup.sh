#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest

    mkdir -p /home/user/backend

    cat << 'EOF' > /home/user/backend/config.json
{
    "status": "Service_Operational_9921"
}
EOF

    cat << 'EOF' > /home/user/backend/app.py
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/health':
            try:
                with open('config.json', 'r') as f:
                    data = json.load(f)
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(data).encode('utf-8'))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    # Deliberately crash if config.json is not in the current working directory
    if not os.path.exists('config.json'):
        raise FileNotFoundError("config.json not found in the current working directory. Startup failed.")
    server = HTTPServer(('127.0.0.1', 9090), RequestHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/watcher.sh
#!/bin/bash
# Simulates a cron-like stripped environment runner
cd /home/user
python3 /home/user/backend/app.py &
EOF

    chmod +x /home/user/watcher.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
