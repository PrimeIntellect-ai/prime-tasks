#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_server.log
[2023/10/12 08:14:02] INFO system started
[12 Oct 23 08:15:00 UTC] ERROR [CODE-1052] Database connection timeout
[2023/10/12 08:16:00] WARNING low memory detected
[2023/10/12 08:17:33] ERROR [CODE-2099] User auth failed: invalid token
[12 Oct 23 08:18:00 UTC] ERROR [CODE-1052] Database connection timeout (retry)
[12 Oct 23 08:19:12 UTC] ERROR [CODE-3001] File not found: /etc/passwd
[2023/10/12 08:20:00] ERROR [CODE-2099] User auth failed: expired
[2023/10/12 08:21:05] ERROR [CODE-A123] Invalid format
EOF

    cat << 'EOF' > /home/user/siem_mock.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class SIEMHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/ingest':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            with open('/home/user/siem_ingest.json', 'w') as f:
                f.write(post_data.decode('utf-8'))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Ingested")

if __name__ == '__main__':
    server = HTTPServer(('localhost', 8080), SIEMHandler)
    server.serve_forever()
EOF

    # Start the mock SIEM server in the background upon container execution
    echo "nohup python3 /home/user/siem_mock.py >/dev/null 2>&1 &" >> $SINGULARITY_ENVIRONMENT

    chmod -R 777 /home/user
