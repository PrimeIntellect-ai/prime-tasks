#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest requests

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/admin/flag':
            auth_header = self.headers.get('X-Incident-Auth')
            cookie = self.headers.get('Cookie')
            ua = self.headers.get('User-Agent')

            if auth_header == 'Alpha-99-Bravo' and ua == 'IR-Ops-Tool/1.0' and cookie == 'session=valid_admin_77812':
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"FLAG{byp4ss3d_l0c4l_4uth_9921}")
            else:
                self.send_response(403)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Forbidden")
        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(('127.0.0.1', 13337), Handler).serve_forever()
EOF

    cat << 'EOF' > /home/user/traffic.log
{"timestamp": "2023-10-24T10:01:22Z", "method": "GET", "path": "/admin/flag", "status": 403, "headers": {"User-Agent": "curl/7.68.0", "X-Incident-Auth": "Alpha-99-Bravo"}, "cookies": "session=guest"}
{"timestamp": "2023-10-24T10:05:11Z", "method": "GET", "path": "/admin/flag", "status": 403, "headers": {"User-Agent": "IR-Ops-Tool/1.0", "X-Incident-Auth": "Invalid"}, "cookies": "session=valid_admin_77812"}
{"timestamp": "2023-10-24T10:08:45Z", "method": "GET", "path": "/admin/flag", "status": 200, "headers": {"User-Agent": "IR-Ops-Tool/1.0", "X-Incident-Auth": "Alpha-99-Bravo"}, "cookies": "session=valid_admin_77812"}
{"timestamp": "2023-10-24T10:11:02Z", "method": "GET", "path": "/admin/flag", "status": 403, "headers": {"User-Agent": "Mozilla/5.0", "X-Incident-Auth": "Alpha-99-Bravo"}, "cookies": "session=valid_admin_77812"}
EOF

    chmod 644 /home/user/traffic.log

    cat << 'EOF' >> /etc/bash.bashrc
if ! pgrep -f "/tmp/server.py" > /dev/null; then
    python3 /tmp/server.py > /dev/null 2>&1 &
    sleep 0.5
fi
EOF

    chmod -R 777 /home/user
