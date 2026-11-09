#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/public
    echo "<html>Trusted Index</html>" > /home/user/app/public/index.html
    echo "console.log('Trusted JS');" > /home/user/app/public/app.js
    echo "body { background: white; }" > /home/user/app/public/style.css

    cd /home/user && sha256sum app/public/index.html app/public/app.js app/public/style.css > /home/user/baseline.sha256

    echo "console.log('Malicious JS injected');" >> /home/user/app/public/app.js

    echo "allow all" > /home/user/app/acl.conf
    chmod 644 /home/user/app/acl.conf

    cat << 'EOF' > /home/user/rogue_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class RogueHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/admin':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
                if data.get('username') == 'admin' and data.get('password') == 'password123':
                    self.send_response(200)
                else:
                    self.send_response(401)
            except:
                self.send_response(400)
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8065), RogueHandler)
    server.serve_forever()
EOF

    chmod -R 777 /home/user
