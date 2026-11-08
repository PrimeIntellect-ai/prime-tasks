#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_repo
    cd /home/user/app_repo
    git init
    git config user.name "Admin"
    git config user.email "admin@localhost"

    head -c 500 /dev/urandom > /home/user/app_repo/users.db

    cat << 'EOF' > /home/user/app_repo/auth.py
import http.server
import json

class AuthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status": "AUTH_SUCCESS"}')
    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    server = http.server.HTTPServer(('127.0.0.1', 8123), AuthHandler)
    server.serve_forever()
EOF

    cat << 'EOF' > /home/user/app_repo/api.py
import json
import urllib.request
import sys

with open('/home/user/app_repo/config.json', 'r') as f:
    config = json.load(f)

port = config.get('auth_port')

try:
    req = urllib.request.urlopen(f'http://127.0.0.1:{port}', timeout=2)
    data = json.loads(req.read().decode())
    if data.get('status') == 'AUTH_SUCCESS':
        print("API_SUCCESS")
        sys.exit(0)
except Exception as e:
    print("API_FAIL")
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/app_repo/config.json
{
    "auth_port": 8199
}
EOF

    cat << 'EOF' > /home/user/app_repo/run_tests.py
import subprocess
import time
import sys

auth_proc = subprocess.Popen([sys.executable, '/home/user/app_repo/auth.py'])
time.sleep(1) # wait for server to start

try:
    api_proc = subprocess.run([sys.executable, '/home/user/app_repo/api.py'], capture_output=True, text=True)
    if "API_SUCCESS" in api_proc.stdout:
        with open('/home/user/test_results.log', 'w') as f:
            f.write("PIPELINE_PASSED\n")
        sys.exit(0)
    else:
        sys.exit(1)
finally:
    auth_proc.terminate()
    auth_proc.wait()
EOF

    git add auth.py api.py config.json run_tests.py users.db
    git commit -m "Initial commit"

    chmod -R 777 /home/user
