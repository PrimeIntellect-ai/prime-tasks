#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl
pip3 install pytest

mkdir -p /home/user/data /home/user/server

# Create the QA server script
cat << 'EOF' > /home/user/server/server.py
import http.server
import socketserver
import os

class SimpleHTTPRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/upload':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            with open('/home/user/server/received.json', 'wb') as f:
                f.write(post_data)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'Success')
        else:
            self.send_response(404)
            self.end_headers()

os.chdir('/home/user/server')
with socketserver.TCPServer(("127.0.0.1", 8080), SimpleHTTPRequestHandler) as httpd:
    httpd.serve_forever()
EOF

# Generate the translations.jsonl file
cat << 'EOF' > /home/user/data/generate.py
import json

with open('/home/user/data/translations.jsonl', 'w') as f:
    for i in range(1, 101):
        if 20 <= i <= 30:
            # Anomalous data: length ratio is exactly 3.0
            en = "A" * 10
            es = "B" * 30
        else:
            # Normal data: length ratio is exactly 1.0
            en = "A" * 10
            es = "B" * 10

        f.write(json.dumps({"id": i, "en": en, "es": es}) + '\n')
EOF

python3 /home/user/data/generate.py
rm /home/user/data/generate.py

# Ensure the server starts when a shell is opened
echo "nohup python3 /home/user/server/server.py > /dev/null 2>&1 &" >> /etc/bash.bashrc

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
