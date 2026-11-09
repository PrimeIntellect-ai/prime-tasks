#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cron
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

port = int(sys.argv[1])
server = HTTPServer(('127.0.0.1', port), HealthHandler)
server.serve_forever()
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
python3 /app/server.py 8080 >/dev/null 2>&1 &
python3 /app/server.py 8081 >/dev/null 2>&1 &
EOF

    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
