#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl netcat-openbsd
    pip3 install pytest requests flask fastapi uvicorn

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/upstream.py
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class UpstreamHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()

        # Echo back what was received to verify sanitization
        response = {
            "received_path": self.path,
            "received_body": body.decode('utf-8')
        }
        self.wfile.write(json.dumps(response).encode('utf-8'))

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 9000), UpstreamHandler)
    server.serve_forever()
EOF

    echo 'python3 -c "import socket; s=socket.socket(); s.connect((\"127.0.0.1\", 9000))" 2>/dev/null || python3 /home/user/upstream.py &' >> /etc/bash.bashrc

    useradd -m -s /bin/bash user || true

    echo 'python3 -c "import socket; s=socket.socket(); s.connect((\"127.0.0.1\", 9000))" 2>/dev/null || python3 /home/user/upstream.py &' >> /home/user/.bashrc

    chmod -R 777 /home/user
