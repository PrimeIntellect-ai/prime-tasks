#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl jq
pip3 install pytest

useradd -m -s /bin/bash user || true
cd /home/user

# 1. Generate CA and Server Certs
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=InternalCA"
openssl req -newkey rsa:2048 -keyout server.key -out server.csr -nodes -subj "/C=US/ST=State/L=City/O=Org/CN=localhost"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365

# 2. Create the Vault Python Server
cat << 'EOF' > /home/user/vault_server.py
import http.server
import ssl

class SecureHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/secrets':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"DB_PASS": "VaultPass2024!", "API_KEY": "SecKey9988"}')
        else:
            self.send_response(404)
            self.end_headers()

httpd = http.server.HTTPServer(('localhost', 8443), SecureHandler)
httpd.socket = ssl.wrap_socket(httpd.socket, keyfile="/home/user/server.key", certfile="/home/user/server.crt", server_side=True)
httpd.serve_forever()
EOF

# 3. Create the App Script
cat << 'EOF' > /home/user/app.py
#!/usr/bin/env python3
import os
import sys

env = dict(os.environ)

if 'DB_PASS' not in env or 'API_KEY' not in env:
    print("ERROR: Missing credentials.")
    sys.exit(1)

if env['DB_PASS'] != 'VaultPass2024!' or env['API_KEY'] != 'SecKey9988':
    print("ERROR: Invalid credentials.")
    sys.exit(1)

# Check for environment leakage
if 'USER' in env or 'HOME' in env or 'PATH' in env:
    print("ERROR: Environment leakage detected. Please use strict process isolation (e.g. env -i).")
    sys.exit(1)

print("ROTATION_COMPLETE_882910")
EOF
chmod +x /home/user/app.py

chmod -R 777 /home/user
