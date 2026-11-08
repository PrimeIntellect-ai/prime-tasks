#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip haproxy curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/restored_apps

    cat << 'EOF' > /home/user/restored_apps/app1.py
#!/usr/bin/env python3
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"app1 ok\n")

HTTPServer(('127.0.0.1', 9001), Handler).serve_forever()
EOF

    cat << 'EOF' > /home/user/restored_apps/app2.py
#!/usr/bin/env python3
import sys
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not os.path.exists('/home/user/restored_apps/db.sqlite'):
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"db missing\n")
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"app2 ok\n")

HTTPServer(('127.0.0.1', 9002), Handler).serve_forever()
EOF

    cat << 'EOF' > /home/user/restored_apps/app3.py
#!/usr/bin/env python3
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"app3 ok\n")

HTTPServer(('127.0.0.1', 9003), Handler).serve_forever()
EOF

    chmod +x /home/user/restored_apps/*.py
    chmod -R 777 /home/user
