#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip nginx openssl curl
pip3 install pytest

mkdir -p /app/corpus
cat << 'EOF' > /app/backend.py
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
class SimpleHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"BACKEND_OK")
HTTPServer(('127.0.0.1', 8080), SimpleHandler).serve_forever()
EOF
chmod +x /app/backend.py

cat << 'EOF' > /app/corpus/clean.txt
/
/dashboard
/images/logo.png
/login?redirect=/home
/api/v1/data?user=john_doe&sort=asc
/profile?id=12345
/about-us.html
EOF

cat << 'EOF' > /app/corpus/evil.txt
/login?redirect=http://attacker.com
/login?redirect=https://evil.org
/login?redirect=//malicious.site
/api/data?query=1;cat+/etc/shadow
/upload?filename=test.sh;`/bin/bash`
/profile?id=$(sudo+su)
/admin|/bin/bash
/login?redirect=/home&cmd=sudo+cat+/etc/shadow
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
