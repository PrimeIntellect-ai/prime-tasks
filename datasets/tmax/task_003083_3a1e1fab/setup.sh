#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/api_server.py
#!/usr/bin/env python3
import http.server
import socketserver

PORT = 8080
EXPECTED_TOKEN = "secret_admin_token_1019"
FLAG = "FLAG{proc_cmdline_leak_secured}"

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/flag':
            auth_header = self.headers.get('Authorization')
            if auth_header == f"Bearer {EXPECTED_TOKEN}":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(FLAG.encode())
            else:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized")
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/worker.sh
#!/bin/bash
# Simulates the vulnerable client
TOKEN_B64="c2VjcmV0X2FkbWluX3Rva2VuXzEwMTk="

# Create a dummy executable to show up in ps/proc
cat << 'INNER_EOF' > /home/user/api_client
#!/bin/bash
sleep 2
INNER_EOF
chmod +x /home/user/api_client

while true; do
    /home/user/api_client --auth-token $TOKEN_B64 > /dev/null 2>&1
    sleep 1
done
EOF

    chmod +x /home/user/api_server.py
    chmod +x /home/user/worker.sh

    chmod -R 777 /home/user
