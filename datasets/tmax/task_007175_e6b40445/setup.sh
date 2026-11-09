#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Create the vulnerable server script
cat << 'EOF' > /opt/vulnerable_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import base64

class VulnerableHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/run':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data)
                code = base64.b64decode(data['payload']).decode('utf-8')
                exec(code)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"Executed")
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())

server = HTTPServer(('127.0.0.1', 8014), VulnerableHandler)
server.serve_forever()
EOF

# Create an environment script to start the server in the background when the container is executed
cat << 'EOF' > /.singularity.d/env/99-start-server.sh
if ! python3 -c "import socket; s=socket.socket(); s.settimeout(0.1); s.connect(('127.0.0.1', 8014))" 2>/dev/null; then
    python3 /opt/vulnerable_server.py >/dev/null 2>&1 &
    sleep 0.5
fi
EOF

# Create user and set up directory
useradd -m -s /bin/bash user || true
mkdir -p /home/user/ssh_keys

# Create dummy SSH keys
echo "dummy key 1" > /home/user/ssh_keys/id_rsa1.pem
echo "dummy key 2" > /home/user/ssh_keys/id_rsa2.pem
echo "dummy key 3" > /home/user/ssh_keys/id_rsa3.pem

# Set permissions for home directory
chmod -R 777 /home/user

# Set specific permissions for SSH keys (must be done after chmod -R 777 /home/user)
chmod 644 /home/user/ssh_keys/id_rsa1.pem
chmod 777 /home/user/ssh_keys/id_rsa2.pem
chmod 600 /home/user/ssh_keys/id_rsa3.pem
