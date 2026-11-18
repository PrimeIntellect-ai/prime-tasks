#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip net-tools curl
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/suspicious_service.py
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer

class SuspiciousHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        if self.path == '/admin':
            self.send_header('Set-Cookie', 'Secret-Admin-Cookie=b4ckd00r_t0k3n_991; Path=/')
        self.end_headers()
        self.wfile.write(b"Service running\n")

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8765), SuspiciousHandler)
    server.serve_forever()
EOF

    chmod +x /home/user/suspicious_service.py

    # Start the service in the background whenever the container is executed
    echo "nohup /home/user/suspicious_service.py > /dev/null 2>&1 &" >> $APPTAINER_ENVIRONMENT
    echo "sleep 0.5" >> $APPTAINER_ENVIRONMENT

    chmod -R 777 /home/user
