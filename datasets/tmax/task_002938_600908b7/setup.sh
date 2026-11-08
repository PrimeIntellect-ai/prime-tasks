#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx curl libcurl4-openssl-dev procps
    pip3 install pytest

    mkdir -p /home/user/backends
    cat << 'EOF' > /home/user/backends/server.py
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[1])

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

httpd = HTTPServer(('127.0.0.1', port), HealthHandler)
httpd.serve_forever()
EOF

    cat << 'EOF' > /.singularity.d/env/99-start.sh
if ! pgrep -f "server.py 9001" > /dev/null; then
    python3 /home/user/backends/server.py 9001 >/dev/null 2>&1 &
    python3 /home/user/backends/server.py 9002 >/dev/null 2>&1 &
    python3 /home/user/backends/server.py 9003 >/dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
