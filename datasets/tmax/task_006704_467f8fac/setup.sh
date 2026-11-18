#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_app.py
def get_deps():
    return [('requests', '2.25.1'), ('urllib3', '1.26.4'), ('flask', '1.1.2')]
EOF

    python3 -c "import py_compile; py_compile.compile('/home/user/legacy_app.py', cfile='/home/user/legacy_app.pyc')"
    rm /home/user/legacy_app.py

    cat << 'EOF' > /home/user/requirements.txt
requests==2.26.0
urllib3==1.25.0
werkzeug==1.0.1
click==8.0.0
EOF

    cat << 'EOF' > /home/user/api_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import time
from urllib.parse import urlparse, parse_qs

class RateLimitedServer(BaseHTTPRequestHandler):
    request_times = []
    valid_deps = {('requests', '2.25.1'), ('urllib3', '1.26.4'), ('flask', '1.1.2'), ('click', '8.0.0')}

    def do_GET(self):
        now = time.time()
        RateLimitedServer.request_times = [t for t in RateLimitedServer.request_times if now - t < 1.0]
        if len(RateLimitedServer.request_times) >= 2:
            self.send_response(429)
            self.end_headers()
            self.wfile.write(b"Too Many Requests")
            return

        RateLimitedServer.request_times.append(now)

        qs = parse_qs(urlparse(self.path).query)
        pkg = qs.get('pkg', [''])[0]
        ver = qs.get('ver', [''])[0]

        if (pkg, ver) in RateLimitedServer.valid_deps:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Valid")
        else:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid")

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    HTTPServer(('127.0.0.1', 8080), RateLimitedServer).serve_forever()
EOF

    chmod -R 777 /home/user
